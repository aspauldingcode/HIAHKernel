/**
 * HIAHKernel.m
 * Virtual Kernel Implementation
 *
 * Copyright (c) 2025 Alex Spaulding - MIT License
 */

#import "HIAHKernel.h"
#import "HIAHProcess.h"
#import "HIAHLogging.h"
#import "HIAHMachOUtils.h"
#import <dlfcn.h>
#import <errno.h>
#import <pthread.h>
#import <sys/socket.h>
#import <sys/un.h>
#import <sys/wait.h>
#import <unistd.h>

// MARK: - Notifications & Error Domain

NSNotificationName const HIAHKernelProcessSpawnedNotification = @"HIAHKernelProcessSpawned";
NSNotificationName const HIAHKernelProcessExitedNotification = @"HIAHKernelProcessExited";
NSNotificationName const HIAHKernelProcessOutputNotification = @"HIAHKernelProcessOutput";
NSErrorDomain const HIAHKernelErrorDomain = @"HIAHKernelErrorDomain";

// MARK: - Private Interface

@interface HIAHKernel ()
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, HIAHProcess *> *processTable;
@property (nonatomic, strong) NSRecursiveLock *lock;
@property (nonatomic, assign) pid_t nextPID;
@property (nonatomic, assign) int controlSocket;
@property (nonatomic, copy, readwrite) NSString *controlSocketPath;
@property (nonatomic, assign) BOOL isShuttingDown;
@property (nonatomic, strong) dispatch_queue_t ioQueue;
@end

// MARK: - Implementation

@implementation HIAHKernel

#pragma mark - Singleton

+ (instancetype)sharedKernel {
    static HIAHKernel *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[self alloc] init];
    });
    return shared;
}

#pragma mark - Init

- (instancetype)init {
    if (self = [super init]) {
        _processTable = [NSMutableDictionary dictionary];
        _lock = [[NSRecursiveLock alloc] init];
        _nextPID = 1000;
        _controlSocket = -1;
        _isShuttingDown = NO;
        _ioQueue = dispatch_queue_create("hiah.kernel.io", DISPATCH_QUEUE_SERIAL);
        
        // Defaults
        _appGroupIdentifier = @"group.com.aspauldingcode.HIAHDesktop";
        _extensionIdentifier = @"com.aspauldingcode.HIAHDesktop.ProcessRunner";
        
        [self setupControlSocket];
    }
    return self;
}

- (void)dealloc {
    [self shutdown];
}

#pragma mark - Control Socket

- (void)setupControlSocket {
    NSString *socketDir = NSTemporaryDirectory();
    NSString *socketName = @"hiah.sock";
    self.controlSocketPath = [socketDir stringByAppendingPathComponent:socketName];
    
    int sock = socket(AF_UNIX, SOCK_STREAM, 0);
    if (sock < 0) return;
    
    struct sockaddr_un addr = {0};
    addr.sun_family = AF_UNIX;
    const char *path = [self.controlSocketPath UTF8String];
    if (strlen(path) >= sizeof(addr.sun_path)) {
        close(sock);
        return;
    }
    strlcpy(addr.sun_path, path, sizeof(addr.sun_path));
    unlink(path);
    
    if (bind(sock, (struct sockaddr *)&addr, sizeof(addr)) == 0 && listen(sock, 5) == 0) {
        self.controlSocket = sock;
        [self startControlListener];
    } else {
        close(sock);
    }
}

- (void)startControlListener {
    dispatch_async(self.ioQueue, ^{
        while (!self.isShuttingDown && self.controlSocket >= 0) {
            int client = accept(self.controlSocket, NULL, NULL);
            if (client >= 0) {
                [self handleClient:client];
            }
        }
    });
}

- (void)handleClient:(int)sock {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        char buf[4096];
        ssize_t n = read(sock, buf, sizeof(buf) - 1);
        if (n > 0) {
            buf[n] = '\0';
            NSData *data = [NSData dataWithBytes:buf length:n];
            NSDictionary *req = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if (req) {
                [self handleRequest:req socket:sock];
            }
        }
        close(sock);
    });
}

- (void)handleRequest:(NSDictionary *)req socket:(int)sock {
    NSString *cmd = req[@"command"];
    NSDictionary *resp;
    
    if ([cmd isEqualToString:@"spawn"]) {
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        __block pid_t resultPid = -1;
        __block NSError *resultErr = nil;
        
        [self spawnProcessWithPath:req[@"path"]
                         arguments:req[@"args"]
                       environment:req[@"env"]
                        completion:^(pid_t pid, NSError *error) {
            resultPid = pid;
            resultErr = error;
            dispatch_semaphore_signal(sem);
        }];
        
        dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
        resp = resultErr ? @{@"error": resultErr.localizedDescription}
                         : @{@"pid": @(resultPid)};
    } else if ([cmd isEqualToString:@"list"]) {
        NSMutableArray *list = [NSMutableArray array];
        for (HIAHProcess *p in [self allProcesses]) {
            [list addObject:@{
                @"pid": @(p.pid),
                @"path": p.executablePath ?: @"",
                @"state": @(p.state)
            }];
        }
        resp = @{@"processes": list};
    } else if ([cmd isEqualToString:@"kill"]) {
        [self killProcess:[req[@"pid"] intValue] signal:[req[@"signal"] intValue]];
        resp = @{@"ok": @YES};
    } else {
        resp = @{@"error": @"unknown command"};
    }
    
    NSData *respData = [NSJSONSerialization dataWithJSONObject:resp options:0 error:nil];
    write(sock, respData.bytes, respData.length);
}

#pragma mark - Process Table

- (void)registerProcess:(HIAHProcess *)process {
    [self.lock lock];
    self.processTable[@(process.pid)] = process;
    [self.lock unlock];
    
    [[NSNotificationCenter defaultCenter]
        postNotificationName:HIAHKernelProcessSpawnedNotification
                      object:self
                    userInfo:@{@"process": process}];
}

- (void)unregisterProcessWithPID:(pid_t)pid {
    [self.lock lock];
    HIAHProcess *proc = self.processTable[@(pid)];
    [self.processTable removeObjectForKey:@(pid)];
    [self.lock unlock];
    
    if (proc) {
        [[NSNotificationCenter defaultCenter]
            postNotificationName:HIAHKernelProcessExitedNotification
                          object:self
                        userInfo:@{@"process": proc}];
    }
}

- (HIAHProcess *)processForPID:(pid_t)pid {
    [self.lock lock];
    HIAHProcess *proc = self.processTable[@(pid)];
    [self.lock unlock];
    return proc;
}

- (NSArray<HIAHProcess *> *)allProcesses {
    [self.lock lock];
    NSArray *procs = [self.processTable allValues];
    [self.lock unlock];
    return procs;
}

- (pid_t)allocatePID {
    [self.lock lock];
    pid_t pid = self.nextPID++;
    [self.lock unlock];
    return pid;
}

#pragma mark - Process Spawning

- (void)spawnProcessWithPath:(NSString *)path
                   arguments:(NSArray<NSString *> *)arguments
                 environment:(NSDictionary<NSString *, NSString *> *)environment
                  completion:(void (^)(pid_t, NSError *))completion {
    
    if (!path.length) {
        if (completion) {
            completion(-1, [self errorWithCode:HIAHKernelErrorInvalidPath
                                       message:@"Empty path"]);
        }
        return;
    }
    
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *execPath = path;
    
    // Handle .app bundles
    BOOL isDir = NO;
    if ([fm fileExistsAtPath:path isDirectory:&isDir] && isDir && [path hasSuffix:@".app"]) {
        NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:
                              [path stringByAppendingPathComponent:@"Info.plist"]];
        NSString *execName = info[@"CFBundleExecutable"];
        if (execName) {
            execPath = [path stringByAppendingPathComponent:execName];
        }
    }
    
    if (![fm fileExistsAtPath:execPath]) {
        if (completion) {
            completion(-1, [self errorWithCode:HIAHKernelErrorInvalidPath
                                       message:@"File not found"]);
        }
        return;
    }
    
    // Patch binary if needed
    NSString *finalPath = execPath;
    if ([HIAHMachOUtils isMHExecute:execPath]) {
        NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                              [execPath.lastPathComponent stringByAppendingString:@".patched"]];
        [fm removeItemAtPath:tempPath error:nil];
        
        if (![fm copyItemAtPath:execPath toPath:tempPath error:nil] ||
            ![HIAHMachOUtils patchBinaryForJITLessMode:tempPath]) {
            if (completion) {
                completion(-1, [self errorWithCode:HIAHKernelErrorBinaryPatchFailed
                                           message:@"Failed to patch binary"]);
            }
            return;
        }
        [HIAHMachOUtils removeCodeSignature:tempPath];
        finalPath = tempPath;
    }
    
    // Create process
    HIAHProcess *proc = [HIAHProcess processWithPath:path
                                           arguments:arguments
                                         environment:environment];
    proc.pid = [self allocatePID];
    proc.physicalPid = getpid();
    proc.state = HIAHProcessStateCreated;
    
    // Load via dlopen
    void *handle = dlopen([finalPath UTF8String], RTLD_NOW | RTLD_LOCAL);
    if (!handle) {
        if (completion) {
            completion(-1, [self errorWithCode:HIAHKernelErrorSpawnFailed
                                       message:[NSString stringWithFormat:@"dlopen: %s", dlerror()]]);
        }
        return;
    }
    
    proc.handle = handle;
    proc.state = HIAHProcessStateRunning;
    [self registerProcess:proc];
    
    // Find entry point
    typedef int (*MainFunc)(int, char **, char **);
    MainFunc mainFunc = dlsym(handle, "main");
    if (!mainFunc) mainFunc = dlsym(handle, "_main");
    
    if (mainFunc) {
        // Execute in thread
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
            @autoreleasepool {
                // Build argv
                int argc = (int)(arguments.count + 1);
                char **argv = calloc(argc + 1, sizeof(char *));
                argv[0] = strdup([path UTF8String]);
                for (int i = 0; i < (int)arguments.count; i++) {
                    argv[i + 1] = strdup([arguments[i] UTF8String]);
                }
                
                // Build envp
                NSMutableDictionary *fullEnv = environment ? [environment mutableCopy] : [NSMutableDictionary dictionary];
                if (weakSelf.controlSocketPath) {
                    fullEnv[@"HIAH_KERNEL_SOCKET"] = weakSelf.controlSocketPath;
                }
                
                int envCount = (int)fullEnv.count;
                char **envp = calloc(envCount + 1, sizeof(char *));
                int idx = 0;
                for (NSString *key in fullEnv) {
                    envp[idx++] = strdup([[NSString stringWithFormat:@"%@=%@", key, fullEnv[key]] UTF8String]);
                }
                
                // Call main
                int exitCode = mainFunc(argc, argv, envp);
                
                // Cleanup
                for (int i = 0; i < argc; i++) free(argv[i]);
                free(argv);
                for (int i = 0; i < envCount; i++) free(envp[i]);
                free(envp);
                
                [weakSelf handleExitForPID:proc.pid exitCode:exitCode];
            }
        });
    }
    
    if (completion) {
        completion(proc.pid, nil);
    }
}

#pragma mark - Process Control

- (void)killProcess:(pid_t)pid signal:(int)signal {
    HIAHProcess *proc = [self processForPID:pid];
    if (!proc || proc.state >= HIAHProcessStateZombie) return;
    
    if (signal == SIGKILL || signal == SIGTERM) {
        [self handleExitForPID:pid exitCode:128 + signal];
    } else if (signal == SIGSTOP) {
        proc.state = HIAHProcessStateStopped;
    } else if (signal == SIGCONT) {
        if (proc.state == HIAHProcessStateStopped) {
            proc.state = HIAHProcessStateRunning;
        }
    }
}

- (pid_t)waitForProcess:(pid_t)pid status:(int *)status options:(int)options {
    [self.lock lock];
    
    // Find a zombie process
    HIAHProcess *found = nil;
    for (HIAHProcess *proc in self.processTable.allValues) {
        if (proc.state == HIAHProcessStateZombie) {
            if (pid == -1 || pid == proc.pid || pid == 0 || pid == -proc.pgid) {
                found = proc;
                break;
            }
        }
    }
    
    [self.lock unlock];
    
    if (!found) {
        if (options & WNOHANG) return 0;
        return -1; // Would block, but no blocking implemented
    }
    
    if (status) {
        if (found.exitSignal) {
            *status = found.exitSignal;
        } else {
            *status = (found.exitCode & 0xFF) << 8;
        }
    }
    
    found.state = HIAHProcessStateTerminated;
    return found.pid;
}

- (void)handleExitForPID:(pid_t)pid exitCode:(int)exitCode {
    HIAHProcess *proc = [self processForPID:pid];
    if (proc) {
        proc.exitCode = exitCode;
        proc.state = HIAHProcessStateZombie;
        
        // Close handle
        if (proc.handle) {
            dlclose(proc.handle);
            proc.handle = NULL;
        }
        
        [[NSNotificationCenter defaultCenter]
            postNotificationName:HIAHKernelProcessExitedNotification
                          object:self
                        userInfo:@{@"process": proc, @"exitCode": @(exitCode)}];
    }
}

#pragma mark - Lifecycle

- (void)shutdown {
    self.isShuttingDown = YES;
    
    if (self.controlSocket >= 0) {
        close(self.controlSocket);
        self.controlSocket = -1;
    }
    
    if (self.controlSocketPath) {
        unlink([self.controlSocketPath UTF8String]);
    }
    
    // Terminate all processes
    for (HIAHProcess *proc in [self allProcesses]) {
        if (proc.state < HIAHProcessStateZombie) {
            [self killProcess:proc.pid signal:SIGKILL];
        }
    }
}

#pragma mark - Helpers

- (NSError *)errorWithCode:(HIAHKernelError)code message:(NSString *)message {
    return [NSError errorWithDomain:HIAHKernelErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

@end
