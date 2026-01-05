/**
 * HIAHGuestHooks.m
 * POSIX Syscall Interception
 *
 * Copyright (c) 2025 Alex Spaulding - MIT License
 */

#import "HIAHGuestHooks.h"
#import "HIAHHook.h"
#import "HIAHKernel.h"
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <errno.h>
#import <pthread.h>
#import <spawn.h>
#import <sys/socket.h>
#import <sys/un.h>
#import <sys/wait.h>
#import <unistd.h>

// MARK: - State

static BOOL g_hooksInstalled = NO;
static __thread BOOL g_inHook = NO;

// MARK: - Thread Control

void HIAHDisableHooksForCurrentThread(void) { g_inHook = YES; }
void HIAHEnableHooksForCurrentThread(void)  { g_inHook = NO; }
BOOL HIAHHooksInstalled(void) { return g_hooksInstalled; }

// MARK: - Original Function Pointers

static int (*orig_posix_spawn)(pid_t *, const char *,
                               const posix_spawn_file_actions_t *,
                               const posix_spawnattr_t *,
                               char *const[], char *const[]);
static int (*orig_execve)(const char *, char *const[], char *const[]);
static pid_t (*orig_waitpid)(pid_t, int *, int);
static pid_t (*orig_fork)(void);

// MARK: - Helpers

static BOOL isSystemBinary(const char *path) {
    if (!path) return NO;
    return strncmp(path, "/usr/", 5) == 0 ||
           strncmp(path, "/bin/", 5) == 0 ||
           strncmp(path, "/sbin/", 6) == 0 ||
           strncmp(path, "/System/", 8) == 0;
}

static int forwardToKernel(const char *path, char *const argv[], char *const envp[], pid_t *outPid) {
    const char *socketPath = getenv("HIAH_KERNEL_SOCKET");
    if (!socketPath) return -1;
    
    int sock = socket(AF_UNIX, SOCK_STREAM, 0);
    if (sock < 0) return -1;
    
    struct sockaddr_un addr = {0};
    addr.sun_family = AF_UNIX;
    strlcpy(addr.sun_path, socketPath, sizeof(addr.sun_path));
    
    if (connect(sock, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
        close(sock);
        return -1;
    }
    
    // Build request
    NSMutableArray *args = [NSMutableArray array];
    if (argv) {
        for (int i = 1; argv[i]; i++) {
            [args addObject:@(argv[i])];
        }
    }
    
    NSMutableDictionary *env = [NSMutableDictionary dictionary];
    if (envp) {
        for (int i = 0; envp[i]; i++) {
            char *eq = strchr(envp[i], '=');
            if (eq) {
                NSString *key = [[NSString alloc] initWithBytes:envp[i]
                                                         length:eq - envp[i]
                                                       encoding:NSUTF8StringEncoding];
                NSString *val = @(eq + 1);
                if (key && val) env[key] = val;
            }
        }
    }
    
    NSDictionary *req = @{@"command": @"spawn", @"path": @(path), @"args": args, @"env": env};
    NSData *data = [NSJSONSerialization dataWithJSONObject:req options:0 error:nil];
    write(sock, data.bytes, data.length);
    
    // Read response
    char buf[1024];
    ssize_t n = read(sock, buf, sizeof(buf) - 1);
    close(sock);
    
    if (n > 0) {
        buf[n] = '\0';
        NSDictionary *resp = [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:buf length:n]
                                                             options:0 error:nil];
        if (resp[@"pid"]) {
            if (outPid) *outPid = [resp[@"pid"] intValue];
            return 0;
        }
    }
    return -1;
}

// MARK: - Hook Implementations

static int hook_posix_spawn(pid_t *pid, const char *path,
                            const posix_spawn_file_actions_t *fa,
                            const posix_spawnattr_t *attr,
                            char *const argv[], char *const envp[]) {
    if (g_inHook || getenv("HIAH_NO_HOOKS") || isSystemBinary(path)) {
        return orig_posix_spawn(pid, path, fa, attr, argv, envp);
    }
    
    g_inHook = YES;
    
    // Try forwarding to kernel
    pid_t resultPid = 0;
    if (forwardToKernel(path, argv, envp, &resultPid) == 0) {
        if (pid) *pid = resultPid;
        g_inHook = NO;
        return 0;
    }
    
    // Fallback to original
    g_inHook = NO;
    return orig_posix_spawn(pid, path, fa, attr, argv, envp);
}

static int hook_execve(const char *path, char *const argv[], char *const envp[]) {
    if (g_inHook || getenv("HIAH_NO_HOOKS") || isSystemBinary(path)) {
        return orig_execve(path, argv, envp);
    }
    
    g_inHook = YES;
    
    // Forward to kernel
    pid_t pid = 0;
    if (forwardToKernel(path, argv, envp, &pid) == 0) {
        _exit(0); // exec replaces process
    }
    
    g_inHook = NO;
    return orig_execve(path, argv, envp);
}

static pid_t hook_waitpid(pid_t pid, int *status, int options) {
    if (g_inHook || getenv("HIAH_NO_HOOKS")) {
        return orig_waitpid(pid, status, options);
    }
    
    // Handle virtual PIDs (>= 1000)
    if (pid >= 1000 || pid == -1) {
        HIAHKernel *kernel = [HIAHKernel sharedKernel];
        pid_t result = [kernel waitForProcess:pid status:status options:options];
        if (result > 0) return result;
    }
    
    // Fallback to real waitpid
    return orig_waitpid(pid, status, options);
}

static pid_t hook_fork(void) {
    if (g_inHook || getenv("HIAH_NO_HOOKS")) {
        return orig_fork();
    }
    
    // On iOS, fork() always fails. Return virtual PID for the "child"
    // This is a stub - real fork semantics require copy-on-write which iOS doesn't support
    errno = ENOSYS;
    return -1;
}

// MARK: - Installation

void HIAHInstallHooks(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Get original functions
        orig_posix_spawn = dlsym(RTLD_DEFAULT, "posix_spawn");
        orig_execve = dlsym(RTLD_DEFAULT, "execve");
        orig_waitpid = dlsym(RTLD_DEFAULT, "waitpid");
        orig_fork = dlsym(RTLD_DEFAULT, "fork");
        
        // Install hooks (uses fishhook or similar)
        if (orig_posix_spawn) {
            HIAHHookIntercept(HIAHHookScopeGlobal, NULL, orig_posix_spawn, hook_posix_spawn);
        }
        if (orig_execve) {
            HIAHHookIntercept(HIAHHookScopeGlobal, NULL, orig_execve, hook_execve);
        }
        if (orig_waitpid) {
            HIAHHookIntercept(HIAHHookScopeGlobal, NULL, orig_waitpid, hook_waitpid);
        }
        if (orig_fork) {
            HIAHHookIntercept(HIAHHookScopeGlobal, NULL, orig_fork, hook_fork);
        }
        
        g_hooksInstalled = YES;
    });
}

__attribute__((constructor))
static void HIAHHooksConstructor(void) {
    HIAHInstallHooks();
}
