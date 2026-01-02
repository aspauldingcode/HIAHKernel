/**
 * HIAHGuestHooks.m
 * HIAHKernel – House in a House Virtual Kernel (for iOS)
 *
 * Robust hooks for posix_spawn, execve, and related functions.
 * Intercepts process creation and enables virtual multi-process execution.
 */

#import "HIAHGuestHooks.h"
#import "HIAHHook.h"
#import <Foundation/Foundation.h>
#import <spawn.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <unistd.h>
#import <errno.h>
#import <string.h>
#import <sys/socket.h>
#import <sys/un.h>
#import <sys/wait.h>
#import <sys/stat.h>
#import <pthread.h>
#import <fcntl.h>
#import <stdint.h>

#pragma mark - File Actions Tracking

typedef enum {
    HIAHActionClose,
    HIAHActionDup2,
    HIAHActionOpen
} HIAHActionType;

typedef struct {
    HIAHActionType type;
    int fd;
    int new_fd;
    char *path;
    int oflag;
    mode_t mode;
} HIAHAction;

typedef struct HIAHThreadArgs {
    char *path;
    int argc;
    char **argv;
    NSArray *actions;
} HIAHThreadArgs;

static NSMutableDictionary<NSValue *, NSMutableArray *> *g_actions_map = nil;
static NSLock *g_actions_lock = nil;
static BOOL g_hooksInstalled = NO;

static void HIAHInitActions(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        g_actions_map = [[NSMutableDictionary alloc] init];
        g_actions_lock = [[NSLock alloc] init];
    });
}

#pragma mark - Thread-Local Hook Control

static __thread BOOL gInHook = NO;

void HIAHDisableHooksForCurrentThread(void) {
    gInHook = YES;
}

void HIAHEnableHooksForCurrentThread(void) {
    gInHook = NO;
}

BOOL HIAHHooksInstalled(void) {
    return g_hooksInstalled;
}

#pragma mark - File Action Hooks

typedef int (*ps_fa_adddup2_t)(posix_spawn_file_actions_t *, int, int);
typedef int (*ps_fa_addclose_t)(posix_spawn_file_actions_t *, int);

DEFINE_HOOK(posix_spawn_file_actions_adddup2, int, (posix_spawn_file_actions_t *fa, int fd, int new_fd)) {
    HIAHInitActions();
    [g_actions_lock lock];
    NSValue *key = [NSValue valueWithPointer:fa];
    if (!g_actions_map[key]) g_actions_map[key] = [NSMutableArray array];
    
    HIAHAction *a = calloc(1, sizeof(HIAHAction));
    a->type = HIAHActionDup2;
    a->fd = fd;
    a->new_fd = new_fd;
    [g_actions_map[key] addObject:[NSValue valueWithPointer:a]];
    NSLog(@"[HIAHHook] Captured file action: dup2(%d, %d)", fd, new_fd);
    [g_actions_lock unlock];
    
    return ORIG_FUNC(posix_spawn_file_actions_adddup2)(fa, fd, new_fd);
}

DEFINE_HOOK(posix_spawn_file_actions_addclose, int, (posix_spawn_file_actions_t *fa, int fd)) {
    HIAHInitActions();
    [g_actions_lock lock];
    NSValue *key = [NSValue valueWithPointer:fa];
    if (!g_actions_map[key]) g_actions_map[key] = [NSMutableArray array];
    
    HIAHAction *a = calloc(1, sizeof(HIAHAction));
    a->type = HIAHActionClose;
    a->fd = fd;
    [g_actions_map[key] addObject:[NSValue valueWithPointer:a]];
    [g_actions_lock unlock];
    
    return ORIG_FUNC(posix_spawn_file_actions_addclose)(fa, fd);
}

#pragma mark - Forward Declarations

static void *HIAHGuestThread(void *data);
static int HIAHForwardSpawn(pid_t *pid, const char *path, char *const argv[], char *const envp[]);
static int HIAHInProcessSpawn(pid_t *pid, const char *path,
                              const posix_spawn_file_actions_t *file_actions,
                              const posix_spawnattr_t *attr,
                              char *const argv[], char *const envp[]);

#pragma mark - Main Hooks

typedef int (*posix_spawn_t)(pid_t * __restrict, const char * __restrict,
                             const posix_spawn_file_actions_t * __restrict,
                             const posix_spawnattr_t * __restrict,
                             char *const [ __restrict], char *const [ __restrict]);
typedef int (*execve_t)(const char *, char *const [], char *const []);
typedef pid_t (*waitpid_t)(pid_t, int *, int);

DEFINE_HOOK(posix_spawn, int, (pid_t * __restrict pid, const char * __restrict path,
                               const posix_spawn_file_actions_t * __restrict file_actions,
                               const posix_spawnattr_t * __restrict attr,
                               char *const argv[ __restrict], char *const envp[ __restrict]));

DEFINE_HOOK(execve, int, (const char *path, char *const argv[], char *const envp[]));
DEFINE_HOOK(waitpid, pid_t, (pid_t pid, int *stat_loc, int options));

static int hook_posix_spawn(pid_t * __restrict pid, const char * __restrict path,
                            const posix_spawn_file_actions_t * __restrict file_actions,
                            const posix_spawnattr_t * __restrict attr,
                            char *const argv[ __restrict], char *const envp[ __restrict]) {
    
    if (gInHook || getenv("HIAH_NO_HOOKS")) {
        return ORIG_FUNC(posix_spawn)(pid, path, file_actions, attr, argv, envp);
    }
    
    // Skip system binaries to avoid recursion
    if (path && (strncmp(path, "/usr/bin/", 9) == 0 || 
                 strncmp(path, "/bin/", 5) == 0 ||
                 strncmp(path, "/sbin/", 6) == 0 ||
                 strncmp(path, "/usr/sbin/", 10) == 0)) {
        return ORIG_FUNC(posix_spawn)(pid, path, file_actions, attr, argv, envp);
    }
    
    gInHook = YES;
    NSLog(@"[HIAHHook] Intercepted posix_spawn: %s", path);
    
    // Handle SSH specially - use dlopen approach
    if (path && (strstr(path, "ssh") != NULL || (argv && argv[0] && strstr(argv[0], "ssh") != NULL))) {
        NSLog(@"[HIAHHook] SSH detected - using in-process dlopen");
        
        NSBundle *extensionBundle = [NSBundle mainBundle];
        NSString *extensionPath = [extensionBundle bundlePath];
        NSString *mainAppPath = [[extensionPath stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
        NSFileManager *fm = [NSFileManager defaultManager];
        
        NSArray<NSString *> *dylibCandidates = @[
            [mainAppPath stringByAppendingPathComponent:@"bin/ssh.dylib"],
            [mainAppPath stringByAppendingPathComponent:@"lib/ssh.dylib"],
            [mainAppPath stringByAppendingPathComponent:@"ssh.dylib"],
        ];
        
        NSString *sshDylibPath = nil;
        for (NSString *candidate in dylibCandidates) {
            if ([fm fileExistsAtPath:candidate]) {
                sshDylibPath = candidate;
                NSLog(@"[HIAHHook] Found ssh.dylib: %@", sshDylibPath);
                break;
            }
        }
        
        if (sshDylibPath) {
            HIAHThreadArgs *targs = calloc(1, sizeof(HIAHThreadArgs));
            targs->path = strdup([sshDylibPath UTF8String]);
            int argc = 0;
            while (argv[argc]) argc++;
            targs->argc = argc;
            targs->argv = malloc(sizeof(char *) * (argc + 1));
            for (int i = 0; i < argc; i++) targs->argv[i] = strdup(argv[i]);
            targs->argv[argc] = NULL;
            
            HIAHInitActions();
            [g_actions_lock lock];
            NSValue *key = [NSValue valueWithPointer:file_actions];
            if (g_actions_map[key]) {
                targs->actions = [g_actions_map[key] copy];
            }
            [g_actions_lock unlock];
            
            pthread_t thread;
            if (pthread_create(&thread, NULL, HIAHGuestThread, targs) != 0) {
                gInHook = NO;
                return EAGAIN;
            }
            
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Wint-to-pointer-cast"
            #pragma clang diagnostic ignored "-Wpointer-to-int-cast"
            if (pid) *pid = (pid_t)(uintptr_t)thread;
            #pragma clang diagnostic pop
            NSLog(@"[HIAHHook] SSH started in thread (pseudo-PID: %lu)", (unsigned long)thread);
            gInHook = NO;
            return 0;
        }
    }
    
    // Handle .dylib files with in-process spawn
    if (path && strstr(path, ".dylib") != NULL) {
        int result = HIAHInProcessSpawn(pid, path, file_actions, attr, (char *const *)argv, (char *const *)envp);
        if (result == 0) {
            gInHook = NO;
            return 0;
        }
    }
    
    // Try kernel socket forwarding
    const char *kernelSocketPath = getenv("HIAH_KERNEL_SOCKET");
    if (!kernelSocketPath) {
        gInHook = NO;
        return ORIG_FUNC(posix_spawn)(pid, path, file_actions, attr, argv, envp);
    }
    
    int result = HIAHForwardSpawn(pid, path, (char *const *)argv, (char *const *)envp);
    if (result == 0) {
        gInHook = NO;
        return 0;
    }
    
    gInHook = NO;
    return ORIG_FUNC(posix_spawn)(pid, path, file_actions, attr, argv, envp);
}

static int hook_execve(const char *path, char *const argv[], char *const envp[]) {
    if (gInHook || getenv("HIAH_NO_HOOKS")) {
        return ORIG_FUNC(execve)(path, argv, envp);
    }

    gInHook = YES;
    NSLog(@"[HIAHHook] Intercepted execve: %s", path);

    // Handle SSH with posix_spawn to keep extension alive
    if (path && (strstr(path, "ssh") != NULL || (argv && argv[0] && strstr(argv[0], "ssh") != NULL))) {
        // Merge environment
        extern char **environ;
        NSMutableDictionary *mergedEnv = [NSMutableDictionary dictionary];
        
        for (int i = 0; environ[i] != NULL; i++) {
            char *entry = environ[i];
            char *eq = strchr(entry, '=');
            if (eq) {
                NSString *key = [[NSString alloc] initWithBytes:entry length:(eq - entry) encoding:NSUTF8StringEncoding];
                NSString *val = [NSString stringWithUTF8String:eq + 1];
                if (key && val) mergedEnv[key] = val;
            }
        }
        
        if (envp) {
            for (int i = 0; envp[i] != NULL; i++) {
                char *eq = strchr(envp[i], '=');
                if (eq) {
                    NSString *key = [[NSString alloc] initWithBytes:envp[i] length:(eq - envp[i]) encoding:NSUTF8StringEncoding];
                    NSString *val = [NSString stringWithUTF8String:eq + 1];
                    if (key && val) mergedEnv[key] = val;
                }
            }
        }
        
        // Propagate SSH password
        if (!mergedEnv[@"SSH_ASKPASS_PASSWORD"]) {
            const char *pass = getenv("HIAH_SSH_PASSWORD");
            if (pass && strlen(pass) > 0) {
                mergedEnv[@"SSH_ASKPASS_PASSWORD"] = [NSString stringWithUTF8String:pass];
                mergedEnv[@"SSHPASS"] = [NSString stringWithUTF8String:pass];
            }
        }
        
        NSUInteger envCount = mergedEnv.count;
        char **mergedEnvp = calloc(envCount + 1, sizeof(char *));
        NSUInteger idx = 0;
        for (NSString *key in mergedEnv) {
            NSString *entry = [NSString stringWithFormat:@"%@=%@", key, mergedEnv[key]];
            mergedEnvp[idx++] = strdup([entry UTF8String]);
        }
        mergedEnvp[envCount] = NULL;
        
        pid_t sshPid = 0;
        int spawnResult = ORIG_FUNC(posix_spawn)(&sshPid, path, NULL, NULL, argv, mergedEnvp);
        
        for (NSUInteger i = 0; i < envCount; i++) free(mergedEnvp[i]);
        free(mergedEnvp);
        
        if (spawnResult == 0) {
            int status = 0;
            ORIG_FUNC(waitpid)(sshPid, &status, 0);
            int exitCode = WIFEXITED(status) ? WEXITSTATUS(status) : 1;
            _exit(exitCode);
        }
        
        gInHook = NO;
        errno = spawnResult;
        return -1;
    }

    // Try forwarding
    pid_t pid;
    int result = HIAHForwardSpawn(&pid, path, (char *const *)argv, (char *const *)envp);
    if (result == 0) {
        exit(0);
    }

    gInHook = NO;
    return ORIG_FUNC(execve)(path, argv, envp);
}

static pid_t hook_waitpid(pid_t pid, int *stat_loc, int options) {
    if (gInHook || getenv("HIAH_NO_HOOKS")) {
        return ORIG_FUNC(waitpid)(pid, stat_loc, options);
    }
    
    // Handle thread-based pseudo-PIDs
    if (pid > 100000) {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wint-to-pointer-cast"
        pthread_t thread = (pthread_t)(uintptr_t)pid;
        #pragma clang diagnostic pop
        if (options & WNOHANG) return 0;
        pthread_join(thread, NULL);
        if (stat_loc) *stat_loc = 0;
        return pid;
    }
    
    return ORIG_FUNC(waitpid)(pid, stat_loc, options);
}

#pragma mark - In-Process Thread Spawning

static void *HIAHGuestThread(void *data) {
    HIAHThreadArgs *args = (HIAHThreadArgs *)data;
    NSLog(@"[HIAHHook] Guest thread started: %s", args->path);
    
    // Apply file actions
    if (args->actions && args->actions.count > 0) {
        for (NSValue *val in args->actions) {
            HIAHAction *a = [val pointerValue];
            if (a->type == HIAHActionDup2) {
                dup2(a->fd, a->new_fd);
            } else if (a->type == HIAHActionClose) {
                close(a->fd);
            }
        }
    }
    
    // Ensure SSH password is available
    const char *sshPass = getenv("SSH_ASKPASS_PASSWORD");
    const char *hiahPass = getenv("HIAH_SSH_PASSWORD");
    if (!sshPass && hiahPass) {
        setenv("SSH_ASKPASS_PASSWORD", hiahPass, 1);
        setenv("SSHPASS", hiahPass, 1);
    }
    
    void *handle = dlopen(args->path, RTLD_NOW | RTLD_GLOBAL);
    if (!handle) {
        NSLog(@"[HIAHHook] dlopen failed: %s", dlerror());
        goto cleanup;
    }
    
    int (*entry)(int, char **) = dlsym(handle, "ssh_main");
    if (!entry) entry = dlsym(handle, "waypipe_main");
    if (!entry) entry = dlsym(handle, "hello_entry");
    if (!entry) entry = dlsym(handle, "main");
    
    if (entry) {
        NSLog(@"[HIAHHook] Calling entry point with %d args", args->argc);
        fflush(stdout);
        fflush(stderr);
        int rc = entry(args->argc, args->argv);
        fflush(stdout);
        fflush(stderr);
        NSLog(@"[HIAHHook] Guest thread finished: %d", rc);
    }
    
cleanup:
    for (int i = 0; i < args->argc; i++) free(args->argv[i]);
    free(args->argv);
    free(args->path);
    free(args);
    return NULL;
}

static int HIAHInProcessSpawn(pid_t *pid, const char *path,
                              const posix_spawn_file_actions_t *file_actions,
                              const posix_spawnattr_t *attr,
                              char *const argv[], char *const envp[]) {
    HIAHThreadArgs *targs = calloc(1, sizeof(HIAHThreadArgs));
    targs->path = strdup(path);
    int argc = 0;
    while (argv[argc]) argc++;
    targs->argc = argc;
    targs->argv = malloc(sizeof(char *) * (argc + 1));
    for (int i = 0; i < argc; i++) targs->argv[i] = strdup(argv[i]);
    targs->argv[argc] = NULL;
    
    HIAHInitActions();
    [g_actions_lock lock];
    NSValue *key = [NSValue valueWithPointer:file_actions];
    if (g_actions_map[key]) {
        targs->actions = [g_actions_map[key] copy];
    }
    [g_actions_lock unlock];
    
    pthread_t thread;
    if (pthread_create(&thread, NULL, HIAHGuestThread, targs) != 0) {
        free(targs->path);
        free(targs->argv);
        free(targs);
        return -1;
    }
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wint-to-pointer-cast"
    #pragma clang diagnostic ignored "-Wpointer-to-int-cast"
    if (pid) *pid = (pid_t)(uintptr_t)thread;
    #pragma clang diagnostic pop
    return 0;
}

static int HIAHForwardSpawn(pid_t *pid, const char *path, char *const argv[], char *const envp[]) {
    const char *kernelSocketPath = getenv("HIAH_KERNEL_SOCKET");
    if (!kernelSocketPath) return -1;

    int sock = socket(AF_UNIX, SOCK_STREAM, 0);
    if (sock < 0) return -1;

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, kernelSocketPath, sizeof(addr.sun_path) - 1);
    
    if (connect(sock, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
        close(sock);
        return -1;
    }

    NSMutableArray *args = [NSMutableArray array];
    if (argv) {
        for (int i = 1; argv[i] != NULL; i++) {
            [args addObject:[NSString stringWithUTF8String:argv[i]]];
        }
    }
    
    NSMutableDictionary *env = [NSMutableDictionary dictionary];
    if (envp) {
        for (int i = 0; envp[i] != NULL; i++) {
            NSString *entry = [NSString stringWithUTF8String:envp[i]];
            NSRange range = [entry rangeOfString:@"="];
            if (range.location != NSNotFound) {
                env[[entry substringToIndex:range.location]] = [entry substringFromIndex:range.location + 1];
            }
        }
    }

    NSDictionary *req = @{
        @"command": @"spawn",
        @"path": [NSString stringWithUTF8String:path],
        @"args": args,
        @"env": env
    };
    
    NSData *reqData = [NSJSONSerialization dataWithJSONObject:req options:0 error:nil];
    write(sock, reqData.bytes, reqData.length);
    write(sock, "\n", 1);

    char buffer[1024];
    ssize_t n = read(sock, buffer, sizeof(buffer) - 1);
    close(sock);
    
    if (n > 0) {
        buffer[n] = '\0';
        NSDictionary *resp = [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:buffer length:n] 
                                                             options:0 
                                                               error:nil];
        if ([resp[@"status"] isEqualToString:@"ok"]) {
            if (pid) *pid = [resp[@"pid"] intValue];
            return 0;
        }
    }
    return -1;
}

#pragma mark - Hook Installation

void HIAHInstallHooks(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        HIAHInitActions();
        
        // Initialize original function pointers
        orig_posix_spawn = dlsym(RTLD_DEFAULT, "posix_spawn");
        orig_execve = dlsym(RTLD_DEFAULT, "execve");
        orig_waitpid = dlsym(RTLD_DEFAULT, "waitpid");
        orig_posix_spawn_file_actions_adddup2 = dlsym(RTLD_DEFAULT, "posix_spawn_file_actions_adddup2");
        orig_posix_spawn_file_actions_addclose = dlsym(RTLD_DEFAULT, "posix_spawn_file_actions_addclose");
        
        // Install hooks
        if (orig_posix_spawn) {
            HIAHHookIntercept(HIAHHookScopeGlobal, NULL, orig_posix_spawn, hook_posix_spawn);
        }
        if (orig_execve) {
            HIAHHookIntercept(HIAHHookScopeGlobal, NULL, orig_execve, hook_execve);
        }
        if (orig_waitpid) {
            HIAHHookIntercept(HIAHHookScopeGlobal, NULL, orig_waitpid, hook_waitpid);
        }
        if (orig_posix_spawn_file_actions_adddup2) {
            HIAHHookIntercept(HIAHHookScopeGlobal, NULL, orig_posix_spawn_file_actions_adddup2, hook_posix_spawn_file_actions_adddup2);
        }
        if (orig_posix_spawn_file_actions_addclose) {
            HIAHHookIntercept(HIAHHookScopeGlobal, NULL, orig_posix_spawn_file_actions_addclose, hook_posix_spawn_file_actions_addclose);
        }
        
        g_hooksInstalled = YES;
        NSLog(@"[HIAHKernel] Virtual kernel hooks installed");
    });
}

__attribute__((constructor))
void HIAHConstructor(void) {
    HIAHInstallHooks();
}

