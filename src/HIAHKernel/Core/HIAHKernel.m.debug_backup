/**
 * HIAHKernel.m
 * HIAHKernel – House in a House Virtual Kernel (for iOS)
 *
 * Implementation of the virtual kernel core.
 *
 * Copyright (c) 2025 Alex Spaulding
 * Licensed under MIT License
 */

#import "HIAHKernel.h"
#import "HIAHLogging.h"
#import "HIAHMachOUtils.h"
#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <errno.h>
#import <sys/socket.h>
#import <sys/un.h>
#import <unistd.h>

// Callback for extension started notifications
static void extensionStartedCallback(CFNotificationCenterRef center,
                                     void *observer, CFStringRef name,
                                     const void *object,
                                     CFDictionaryRef userInfo) {
  HIAHKernel *kernel = (__bridge HIAHKernel *)observer;
  if (kernel) {
    // Read PIDs from App Group storage
    // CRITICAL: Read both the shared PID file AND all unique PID files
    // This ensures we enable JIT for ALL extension processes, not just the last
    // one
    NSFileManager *fm = [NSFileManager defaultManager];
    NSURL *groupURL = [fm containerURLForSecurityApplicationGroupIdentifier:
                              kernel.appGroupIdentifier];
    if (groupURL) {
      // Read shared PID file (may contain the latest extension PID)
      NSString *pidFile =
          [[groupURL.path stringByAppendingPathComponent:@"extension.pid"]
              stringByStandardizingPath];
      NSString *pidStr = [NSString stringWithContentsOfFile:pidFile
                                                   encoding:NSUTF8StringEncoding
                                                      error:nil];
      if (pidStr) {
        pid_t pid = pidStr.intValue;
        HIAHLogEx(HIAH_LOG_INFO, @"Kernel",
                  @"Extension started notification received (PID: %d from "
                  @"shared file) - enabling JIT immediately",
                  pid);
        [kernel enableJITForExtensionProcessWithRetries:pid];
      }

      // CRITICAL: Also scan for all unique PID files (extension.PID.pid)
      // This catches ALL extension processes, not just the one that wrote to
      // the shared file
      NSError *error = nil;
      NSArray<NSString *> *files = [fm contentsOfDirectoryAtPath:groupURL.path
                                                           error:&error];
      if (files) {
        for (NSString *filename in files) {
          if ([filename hasPrefix:@"extension."] &&
              [filename hasSuffix:@".pid"] &&
              ![filename isEqualToString:@"extension.pid"]) {
            // Extract PID from filename (extension.PID.pid)
            NSString *pidPart = [[filename stringByDeletingPathExtension]
                stringByReplacingOccurrencesOfString:@"extension."
                                          withString:@""];
            pid_t pid = pidPart.intValue;
            if (pid > 0) {
              HIAHLogEx(
                  HIAH_LOG_INFO, @"Kernel",
                  @"Found extension PID file: %@ (PID: %d) - enabling JIT",
                  filename, pid);
              [kernel enableJITForExtensionProcessWithRetries:pid];
            }
          }
        }
      }
    }
  }
}

NSNotificationName const HIAHKernelProcessSpawnedNotification =
    @"HIAHKernelProcessSpawned";
NSNotificationName const HIAHKernelProcessExitedNotification =
    @"HIAHKernelProcessExited";
NSNotificationName const HIAHKernelProcessOutputNotification =
    @"HIAHKernelProcessOutput";
NSErrorDomain const HIAHKernelErrorDomain = @"HIAHKernelErrorDomain";

@interface HIAHKernel ()
@property(nonatomic, strong)
    NSMutableDictionary<NSNumber *, HIAHProcess *> *processTable;
@property(nonatomic, strong) NSRecursiveLock *lock;
@property(nonatomic, strong) NSMutableArray *activeExtensions;
@property(nonatomic, assign) int controlSocket;
@property(nonatomic, copy, readwrite) NSString *controlSocketPath;
@property(nonatomic, assign) BOOL isShuttingDown;
@property(nonatomic, strong)
    NSString *socketDirectory; // Cached socket directory
@property(nonatomic, strong)
    NSXPCListener *xpcListener; // XPC listener for extension communication
@property(nonatomic, assign) pid_t nextVirtualPid;
@end

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

#pragma mark - Initialization

- (instancetype)init {
  self = [super init];
  if (self) {
    _processTable = [NSMutableDictionary dictionary];
    _lock = [[NSRecursiveLock alloc] init];
    _activeExtensions = [NSMutableArray array];
    _controlSocket = -1;
    _isShuttingDown = NO;
    _nextVirtualPid = 1000; // Start virtual PIDs at 1000

    // Default configuration
    _appGroupIdentifier = @"group.com.aspauldingcode.HIAH";
    _extensionIdentifier = @"com.aspauldingcode.HIAHDesktop.ProcessRunner";

    // Listen for extension started notifications (Darwin notifications)
    // This allows us to enable JIT immediately when an extension process starts
    CFNotificationCenterRef center =
        CFNotificationCenterGetDarwinNotifyCenter();
    if (center) {
      CFStringRef notificationName =
          CFSTR("com.aspauldingcode.HIAHDesktop.ExtensionStarted");
      CFNotificationCenterAddObserver(
          center, (__bridge const void *)self, extensionStartedCallback,
          notificationName, NULL,
          CFNotificationSuspensionBehaviorDeliverImmediately);
      HIAHLogInfo(HIAHLogKernel,
                  "Registered for extension started notifications");
    }

    [self setupControlSocket];
  }
  return self;
}

- (void)dealloc {
  [self shutdown];
}

#pragma mark - Control Socket

- (void)setupControlSocket {
  // Use NSTemporaryDirectory() - the iOS-proper way for temp files/sockets
  // This directory is always accessible, writable, and short enough for socket
  // paths
  self.socketDirectory = NSTemporaryDirectory();
  NSLog(@"[HIAHKernel] Using NSTemporaryDirectory for sockets: %@",
        self.socketDirectory);

  // Short socket name
  NSString *socketName = @"k.s";
  self.controlSocketPath =
      [self.socketDirectory stringByAppendingPathComponent:socketName];
  NSLog(@"[HIAHKernel] Control socket: %@", self.controlSocketPath);

  int serverSock = socket(AF_UNIX, SOCK_STREAM, 0);
  if (serverSock < 0) {
    NSLog(@"[HIAHKernel] Failed to create control socket: %s", strerror(errno));
    return;
  }

  struct sockaddr_un addr;
  memset(&addr, 0, sizeof(addr));
  addr.sun_family = AF_UNIX;

  // Use absolute path instead of chdir (iOS device sandboxing)
  const char *fullSocketPath = [self.controlSocketPath UTF8String];
  if (strlen(fullSocketPath) >= sizeof(addr.sun_path)) {
    NSLog(@"[HIAHKernel] Control socket path too long: %@",
          self.controlSocketPath);
    close(serverSock);
    return;
  }

  strncpy(addr.sun_path, fullSocketPath, sizeof(addr.sun_path) - 1);
  unlink(fullSocketPath); // Remove if exists

  if (bind(serverSock, (struct sockaddr *)&addr, sizeof(addr)) == 0) {
    listen(serverSock, 5);
    self.controlSocket = serverSock;
    [self startControlSocketListener];
    NSLog(@"[HIAHKernel] Control socket ready: %@", self.controlSocketPath);
  } else {
    NSLog(@"[HIAHKernel] Failed to bind control socket at %@: %s",
          self.controlSocketPath, strerror(errno));
    close(serverSock);
  }
}

- (void)startControlSocketListener {
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
    while (!self.isShuttingDown && self.controlSocket >= 0) {
      int clientSock = accept(self.controlSocket, NULL, NULL);
      if (clientSock >= 0) {
        [self handleControlClient:clientSock];
      }
    }
  });
}

- (void)handleControlClient:(int)sock {
  dispatch_async(
      dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSMutableData *data = [NSMutableData data];
        char buffer[1024];
        ssize_t n;

        while ((n = read(sock, buffer, sizeof(buffer))) > 0) {
          [data appendBytes:buffer length:n];
          // Simple newline-delimited JSON protocol
          if (buffer[n - 1] == '\n') {
            NSError *err;
            NSDictionary *req = [NSJSONSerialization JSONObjectWithData:data
                                                                options:0
                                                                  error:&err];
            if (req) {
              [self processControlRequest:req socket:sock];
            }
            [data setLength:0];
          }
        }
        close(sock);
      });
}

- (void)processControlRequest:(NSDictionary *)req socket:(int)sock {
  NSString *command = req[@"command"];

  if ([command isEqualToString:@"spawn"]) {
    NSString *path = req[@"path"];
    NSArray *args = req[@"args"];
    NSDictionary *env = req[@"env"];

    [self spawnVirtualProcessWithPath:path
                            arguments:args
                          environment:env
                           completion:^(pid_t pid, NSError *error) {
                             NSDictionary *resp;
                             if (error) {
                               resp = @{
                                 @"status" : @"error",
                                 @"error" : error.localizedDescription
                               };
                             } else {
                               resp = @{@"status" : @"ok", @"pid" : @(pid)};
                             }
                             NSData *respData =
                                 [NSJSONSerialization dataWithJSONObject:resp
                                                                 options:0
                                                                   error:nil];
                             write(sock, respData.bytes, respData.length);
                             write(sock, "\n", 1);
                           }];
  } else if ([command isEqualToString:@"list"]) {
    NSArray *procs = [self allProcesses];
    NSMutableArray *procList = [NSMutableArray array];
    for (HIAHProcess *p in procs) {
      [procList addObject:@{
        @"pid" : @(p.pid),
        @"path" : p.executablePath ?: @"",
        @"exited" : @(p.isExited),
        @"exitCode" : @(p.exitCode)
      }];
    }
    NSDictionary *resp = @{@"status" : @"ok", @"processes" : procList};
    NSData *respData = [NSJSONSerialization dataWithJSONObject:resp
                                                       options:0
                                                         error:nil];
    write(sock, respData.bytes, respData.length);
    write(sock, "\n", 1);
  }
}

#pragma mark - Process Management

- (void)registerProcess:(HIAHProcess *)process {
  [self.lock lock];
  self.processTable[@(process.pid)] = process;
  [self.lock unlock];

  NSLog(@"[HIAHKernel] Registered process %d (%@)", process.pid,
        process.executablePath);

  [[NSNotificationCenter defaultCenter]
      postNotificationName:HIAHKernelProcessSpawnedNotification
                    object:self
                  userInfo:@{@"process" : process}];
}

- (void)unregisterProcessWithPID:(pid_t)pid {
  [self.lock lock];
  HIAHProcess *process = self.processTable[@(pid)];
  [self.processTable removeObjectForKey:@(pid)];
  [self.lock unlock];

  NSLog(@"[HIAHKernel] Unregistered process %d", pid);

  if (process) {
    [[NSNotificationCenter defaultCenter]
        postNotificationName:HIAHKernelProcessExitedNotification
                      object:self
                    userInfo:@{@"process" : process}];
  }
}

- (HIAHProcess *)processForPID:(pid_t)pid {
  [self.lock lock];
  HIAHProcess *proc = self.processTable[@(pid)];
  [self.lock unlock];
  return proc;
}

- (HIAHProcess *)processForRequestIdentifier:(NSUUID *)uuid {
  [self.lock lock];
  __block HIAHProcess *result = nil;
  [self.processTable enumerateKeysAndObjectsUsingBlock:^(
                         NSNumber *key, HIAHProcess *obj, BOOL *stop) {
    if ([obj.requestIdentifier isEqual:uuid]) {
      result = obj;
      *stop = YES;
    }
  }];
  [self.lock unlock];
  return result;
}

- (NSArray<HIAHProcess *> *)allProcesses {
  [self.lock lock];
  NSArray *processes = [self.processTable allValues];
  [self.lock unlock];

  if (processes.count == 0) {
    HIAHLogDebug(HIAHLogKernel, "Process table is empty");
  }

  return processes;
}

- (void)handleExitForPID:(pid_t)pid exitCode:(int)exitCode {
  HIAHProcess *proc = [self processForPID:pid];
  if (proc) {
    proc.isExited = YES;
    proc.exitCode = exitCode;
    HIAHLogInfo(HIAHLogKernel, "Process %d exited with code %d", pid, exitCode);

    [[NSNotificationCenter defaultCenter]
        postNotificationName:HIAHKernelProcessExitedNotification
                      object:self
                    userInfo:@{@"process" : proc, @"exitCode" : @(exitCode)}];
  }
}

#pragma mark - Process Spawning

- (void)spawnVirtualProcessWithPath:(NSString *)path
                          arguments:(NSArray<NSString *> *)arguments
                        environment:
                            (NSDictionary<NSString *, NSString *> *)environment
                         completion:
                             (void (^)(pid_t pid, NSError *error))completion {

  if (!path || path.length == 0) {
    if (completion) {
      NSError *error = [NSError
          errorWithDomain:HIAHKernelErrorDomain
                     code:HIAHKernelErrorInvalidPath
                 userInfo:@{
                   NSLocalizedDescriptionKey : @"Invalid executable path"
                 }];
      completion(-1, error);
    }
    return;
  }

  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *actualExecutablePath = path;

  // Handle .app bundle paths
  // If the path points to a .app bundle, we need to find the executable inside
  // it
  BOOL isDirectory = NO;
  if ([fm fileExistsAtPath:path isDirectory:&isDirectory] && isDirectory &&
      [path hasSuffix:@".app"]) {
    NSLog(@"[HIAHKernel] Received .app bundle path, locating executable...");

    NSString *infoPlistPath =
        [path stringByAppendingPathComponent:@"Info.plist"];
    NSDictionary *infoPlist =
        [NSDictionary dictionaryWithContentsOfFile:infoPlistPath];
    NSString *executableName = infoPlist[@"CFBundleExecutable"];

    if (executableName) {
      // Try direct path: App.app/ExecutableName
      NSString *candidatePath =
          [path stringByAppendingPathComponent:executableName];
      if ([fm fileExistsAtPath:candidatePath]) {
        actualExecutablePath = candidatePath;
        NSLog(@"[HIAHKernel] Found executable at: %@", actualExecutablePath);
      } else {
        // Try Contents/MacOS path (rare on iOS but possible)
        candidatePath = [[path stringByAppendingPathComponent:@"Contents/MacOS"]
            stringByAppendingPathComponent:executableName];
        if ([fm fileExistsAtPath:candidatePath]) {
          actualExecutablePath = candidatePath;
          NSLog(@"[HIAHKernel] Found executable at: %@", actualExecutablePath);
        } else {
          NSLog(@"[HIAHKernel] ERROR: Could not find executable '%@' in bundle",
                executableName);
          if (completion) {
            NSError *error = [NSError
                errorWithDomain:HIAHKernelErrorDomain
                           code:HIAHKernelErrorInvalidPath
                       userInfo:@{
                         NSLocalizedDescriptionKey : [NSString
                             stringWithFormat:
                                 @"Executable '%@' not found in bundle",
                                 executableName]
                       }];
            completion(-1, error);
          }
          return;
        }
      }
    } else {
      NSLog(@"[HIAHKernel] ERROR: No CFBundleExecutable in Info.plist");
      if (completion) {
        NSError *error =
            [NSError errorWithDomain:HIAHKernelErrorDomain
                                code:HIAHKernelErrorInvalidPath
                            userInfo:@{
                              NSLocalizedDescriptionKey :
                                  @"No CFBundleExecutable in Info.plist"
                            }];
        completion(-1, error);
      }
      return;
    }
  }

  // Update path to actual executable
  path = actualExecutablePath;
  NSLog(@"[HIAHKernel] Final executable path: %@", path);

  // Verify the executable exists
  if (![fm fileExistsAtPath:path]) {
    NSLog(@"[HIAHKernel] ERROR: Executable not found at: %@", path);
    if (completion) {
      NSError *error = [NSError
          errorWithDomain:HIAHKernelErrorDomain
                     code:HIAHKernelErrorInvalidPath
                 userInfo:@{
                   NSLocalizedDescriptionKey : [NSString
                       stringWithFormat:@"Executable not found: %@", path]
                 }];
      completion(-1, error);
    }
    return;
  }

  // CRITICAL: Ensure executable has correct permissions
  NSDictionary *attrs = @{NSFilePosixPermissions : @0755};
  NSError *permError = nil;
  [fm setAttributes:attrs ofItemAtPath:path error:&permError];
  if (permError) {
    NSLog(@"[HIAHKernel] Warning: Could not set executable permissions: %@",
          permError);
  } else {
    NSLog(@"[HIAHKernel] Set executable permissions for: %@", path);
  }

  NSError *error = nil;

  // 1. Create stdout/stderr capture socket
  // Use NSTemporaryDirectory() - iOS-proper temporary storage
  NSString *socketDir = self.socketDirectory ?: NSTemporaryDirectory();

  // Short socket name
  NSString *socketName =
      [NSString stringWithFormat:@"%d.s", arc4random() % 100];
  NSString *socketPath = [socketDir stringByAppendingPathComponent:socketName];

  NSLog(@"[HIAHKernel] Spawn socket: %@", socketPath);

  int serverSock = socket(AF_UNIX, SOCK_STREAM, 0);
  if (serverSock < 0) {
    NSLog(@"[HIAHKernel] Failed to create socket: %s", strerror(errno));
    if (completion) {
      NSError *err = [NSError
          errorWithDomain:HIAHKernelErrorDomain
                     code:HIAHKernelErrorSocketCreationFailed
                 userInfo:@{
                   NSLocalizedDescriptionKey : @"Failed to create output socket"
                 }];
      completion(-1, err);
    }
    return;
  }

  struct sockaddr_un addr;
  memset(&addr, 0, sizeof(addr));
  addr.sun_family = AF_UNIX;

  // Use absolute path instead of chdir (iOS device doesn't allow chdir to app
  // group)
  const char *fullSocketPath = [socketPath UTF8String];
  if (strlen(fullSocketPath) >= sizeof(addr.sun_path)) {
    NSLog(@"[HIAHKernel] Socket path too long: %@", socketPath);
    close(serverSock);
    if (completion) {
      NSError *err =
          [NSError errorWithDomain:HIAHKernelErrorDomain
                              code:HIAHKernelErrorSocketCreationFailed
                          userInfo:@{
                            NSLocalizedDescriptionKey : @"Socket path too long"
                          }];
      completion(-1, err);
    }
    return;
  }

  strncpy(addr.sun_path, fullSocketPath, sizeof(addr.sun_path) - 1);
  unlink(fullSocketPath); // Remove if exists

  if (bind(serverSock, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
    NSLog(@"[HIAHKernel] Failed to bind stdout socket at %@: %s", socketPath,
          strerror(errno));
    close(serverSock);
    if (completion) {
      NSError *err = [NSError
          errorWithDomain:HIAHKernelErrorDomain
                     code:HIAHKernelErrorSocketCreationFailed
                 userInfo:@{
                   NSLocalizedDescriptionKey :
                       [NSString stringWithFormat:@"Failed to bind socket: %s",
                                                  strerror(errno)]
                 }];
      completion(-1, err);
    }
    return;
  }

  listen(serverSock, 1);

  // Start background thread to read from socket
  dispatch_async(
      dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        int clientSock = accept(serverSock, NULL, NULL);
        if (clientSock >= 0) {
          char buffer[1024];
          ssize_t n;
          while ((n = read(clientSock, buffer, sizeof(buffer) - 1)) > 0) {
            buffer[n] = '\0';
            NSString *output = [NSString stringWithUTF8String:buffer];
            if (output) {
              NSLog(@"[HIAHKernel Guest] %@", output);

              if (self.onOutput) {
                self.onOutput(0, output);
              }

              [[NSNotificationCenter defaultCenter]
                  postNotificationName:HIAHKernelProcessOutputNotification
                                object:self
                              userInfo:@{@"output" : output}];

              printf("%s", [output UTF8String]);
              fflush(stdout);
            }
          }
          close(clientSock);
        }
        close(serverSock);
        unlink([socketPath UTF8String]);
      });


  // 2. Patch binary for dlopen if needed
  NSString *executablePath = path;
  
  // Check if binary needs patching (MH_EXECUTE → MH_BUNDLE)
  if ([HIAHMachOUtils isMHExecute:path]) {
    HIAHLogInfo(HIAHLogKernel, "Binary is MH_EXECUTE, patching for dlopen...");
    
    // Create a temporary copy for patching
    NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                         [[path lastPathComponent] stringByAppendingString:@".patched"]];
    
    NSError *copyError = nil;
    if (![[NSFileManager defaultManager] copyItemAtPath:path
                                                  toPath:tempPath
                                                   error:&copyError]) {
      HIAHLogError(HIAHLogKernel, "Failed to copy binary for patching: %s",
                   [[copyError description] UTF8String]);
      if (completion) {
        completion(-1, copyError);
      }
      return;
    }
    
    // Patch the binary using JIT-less mode (LiveContainer approach)
    if (![HIAHMachOUtils patchBinaryForJITLessMode:tempPath]) {
      HIAHLogError(HIAHLogKernel, "Failed to patch binary for dlopen");
      if (completion) {
        NSError *err = [NSError errorWithDomain:HIAHKernelErrorDomain
                                           code:HIAHKernelErrorSpawnFailed
                                       userInfo:@{NSLocalizedDescriptionKey: @"Failed to patch binary"}];
        completion(-1, err);
      }
      return;
    }
    
    executablePath = tempPath;
    HIAHLogInfo(HIAHLogKernel, "Binary patched successfully: %s", [tempPath UTF8String]);
  }
  
  // 3. Load the binary via dlopen
  HIAHLogInfo(HIAHLogKernel, "Loading binary via dlopen: %s", [executablePath UTF8String]);
  
  void *handle = dlopen([executablePath UTF8String], RTLD_NOW | RTLD_GLOBAL);
  if (!handle) {
    const char *dlopen_error = dlerror();
    HIAHLogError(HIAHLogKernel, "dlopen failed: %s", dlopen_error ?: "(null)");
    
    if (completion) {
      NSError *err = [NSError errorWithDomain:HIAHKernelErrorDomain
                                         code:HIAHKernelErrorSpawnFailed
                                     userInfo:@{NSLocalizedDescriptionKey: 
                                       [NSString stringWithFormat:@"dlopen failed: %s", 
                                        dlopen_error ?: "(null)"]}];
      completion(-1, err);
    }
    return;
  }
  
  HIAHLogInfo(HIAHLogKernel, "Binary loaded successfully via dlopen");
  
  // 4. Create virtual process entry
  HIAHProcess *vproc = [HIAHProcess processWithPath:path
                                          arguments:arguments
                                        environment:environment];
  
  // Assign virtual PID
  [self.lock lock];
  vproc.pid = self.nextVirtualPid++;
  [self.lock unlock];
  
  // For dlopen-based execution, we don't have a separate physical PID
  // The code runs in our process
  vproc.physicalPid = getpid();
  
  [self registerProcess:vproc];
  
  HIAHLogInfo(HIAHLogKernel, "Spawned guest process via dlopen (Virtual PID: %d)", vproc.pid);
  
  // 5. Find and execute entry point
  // For command-line tools like ssh/waypipe, we need to find main()
  typedef int (*main_func_t)(int argc, char **argv, char **envp);
  main_func_t main_func = (main_func_t)dlsym(handle, "main");
  
  if (!main_func) {
    // Try _main (some binaries use this)
    main_func = (main_func_t)dlsym(handle, "_main");
  }
  
  if (main_func) {
    HIAHLogInfo(HIAHLogKernel, "Found entry point, executing in background thread...");
    
    // Execute main() in a background thread
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      // Prepare argc/argv
      int argc = (int)(arguments.count + 1);
      char **argv = malloc(sizeof(char *) * (argc + 1));
      argv[0] = strdup([path UTF8String]);
      for (int i = 0; i < arguments.count; i++) {
        argv[i + 1] = strdup([arguments[i] UTF8String]);
      }
      argv[argc] = NULL;
      
      // Prepare envp
      NSMutableDictionary *fullEnv = environment ? [environment mutableCopy] : [NSMutableDictionary dictionary];
      fullEnv[@"HIAH_STDOUT_SOCKET"] = socketPath;
      if (self.controlSocketPath) {
        fullEnv[@"HIAH_KERNEL_SOCKET"] = self.controlSocketPath;
      }
      
      int envCount = (int)fullEnv.count;
      char **envp = malloc(sizeof(char *) * (envCount + 1));
      int envIdx = 0;
      for (NSString *key in fullEnv) {
        NSString *value = fullEnv[key];
        NSString *envStr = [NSString stringWithFormat:@"%@=%@", key, value];
        envp[envIdx++] = strdup([envStr UTF8String]);
      }
      envp[envCount] = NULL;
      
      // Call main()
      HIAHLogInfo(HIAHLogKernel, "Calling main() with %d arguments", argc);
      int exitCode = main_func(argc, argv, envp);
      HIAHLogInfo(HIAHLogKernel, "main() returned with exit code: %d", exitCode);
      
      // Clean up
      for (int i = 0; i < argc; i++) {
        free(argv[i]);
      }
      free(argv);
      for (int i = 0; i < envCount; i++) {
        free(envp[i]);
      }
      free(envp);
      
      // Mark process as exited
      [self handleExitForPID:vproc.pid exitCode:exitCode];
    });
    
    // Return success immediately (execution is async)
    if (completion) {
      completion(vproc.pid, nil);
    }
  } else {
    HIAHLogWarning(HIAHLogKernel, "No main() entry point found, binary loaded but not executed");
    
    // Still return success - the binary is loaded
    if (completion) {
      completion(vproc.pid, nil);
    }
  }
}
