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
#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
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

  // 2. Load NSExtension from PlugIns folder
  Class extensionClass = NSClassFromString(@"NSExtension");

  if (!extensionClass) {
    HIAHLogError(HIAHLogKernel, "NSExtension class not available");
    if (completion) {
      NSError *err = [NSError
          errorWithDomain:HIAHKernelErrorDomain
                     code:HIAHKernelErrorExtensionNotFound
                 userInfo:@{
                   NSLocalizedDescriptionKey : @"NSExtension not available"
                 }];
      completion(-1, err);
    }
    return;
  }

  // Find the extension bundle in PlugIns folder
  NSString *plugInsPath = [[NSBundle mainBundle] builtInPlugInsPath];
  NSString *appexPath =
      [plugInsPath stringByAppendingPathComponent:@"HIAHProcessRunner.appex"];
  NSBundle *extensionBundle = [NSBundle bundleWithPath:appexPath];

  if (!extensionBundle) {
    HIAHLogError(HIAHLogKernel, "Extension bundle not found at %s",
                 [appexPath UTF8String]);
    if (completion) {
      NSError *err =
          [NSError errorWithDomain:HIAHKernelErrorDomain
                              code:HIAHKernelErrorExtensionNotFound
                          userInfo:@{
                            NSLocalizedDescriptionKey :
                                @"ProcessRunner extension not bundled"
                          }];
      completion(-1, err);
    }
    return;
  }

  NSString *extId = extensionBundle.bundleIdentifier;
  if (!extId) {
    extId = self.extensionIdentifier; // fallback to configured identifier
  }
  HIAHLogDebug(HIAHLogKernel, "Loading extension with identifier: %s",
               [extId UTF8String]);

  // Verify the extension bundle's principal class is set correctly
  NSDictionary *extInfo = extensionBundle.infoDictionary;
  NSDictionary *extConfig = extInfo[@"NSExtension"];
  NSString *principalClass = extConfig[@"NSExtensionPrincipalClass"];
  HIAHLogEx(HIAH_LOG_INFO, @"Kernel", @"Extension principal class: %@",
            principalClass);

  SEL selector = NSSelectorFromString(@"extensionWithIdentifier:error:");
  NSMethodSignature *signature =
      [extensionClass methodSignatureForSelector:selector];
  NSInvocation *invocation =
      [NSInvocation invocationWithMethodSignature:signature];
  [invocation setTarget:extensionClass];
  [invocation setSelector:selector];

  [invocation setArgument:&extId atIndex:2];
  [invocation setArgument:&error atIndex:3];
  [invocation invoke];

  __strong id extension = nil;
  [invocation getReturnValue:&extension];

  if (!extension) {
    HIAHLogError(HIAHLogKernel, "Failed to load extension %s: %s",
                 [extId UTF8String],
                 error ? [[error description] UTF8String] : "(null)");
    if (completion)
      completion(-1, error);
    return;
  }

  HIAHLogEx(HIAH_LOG_INFO, @"Kernel", @"Extension loaded successfully: %@",
            extension);
  [self.activeExtensions addObject:extension];

  // 3. Prepare Request
  Class extensionItemClass = NSClassFromString(@"NSExtensionItem");
  id item = [[extensionItemClass alloc] init];
  NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
  userInfo[@"LSExecutablePath"] = path;
  userInfo[@"LSArguments"] = arguments ?: @[];

  NSMutableDictionary *env = environment ? [environment mutableCopy]
                                         : [NSMutableDictionary dictionary];
  env[@"HIAH_STDOUT_SOCKET"] = socketPath;
  if (self.controlSocketPath) {
    env[@"HIAH_KERNEL_SOCKET"] = self.controlSocketPath;
  }
  userInfo[@"LSEnvironment"] = env;
  userInfo[@"LSServiceMode"] = @"spawn";

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
  [item performSelector:NSSelectorFromString(@"setUserInfo:")
             withObject:userInfo];
#pragma clang diagnostic pop

  void (^completionBlock)(NSUUID *) = ^(NSUUID *requestIdentifier) {
    if (!requestIdentifier) {
      HIAHLogError(HIAHLogKernel, "Failed to start extension request for %s",
                   [path UTF8String]);
      if (completion) {
        NSError *err = [NSError errorWithDomain:HIAHKernelErrorDomain
                                           code:HIAHKernelErrorSpawnFailed
                                       userInfo:nil];
        completion(-1, err);
      }
      return;
    }

    HIAHProcess *vproc = [HIAHProcess processWithPath:path
                                            arguments:arguments
                                          environment:environment];
    vproc.requestIdentifier = requestIdentifier;

    // Try to get physical PID
    pid_t physicalPid = -1;
    if ([extension respondsToSelector:NSSelectorFromString(
                                          @"pidForRequestIdentifier:")]) {
      NSInvocation *pidInv = [NSInvocation
          invocationWithMethodSignature:
              [extension
                  methodSignatureForSelector:NSSelectorFromString(
                                                 @"pidForRequestIdentifier:")]];
      [pidInv setTarget:extension];
      [pidInv setSelector:NSSelectorFromString(@"pidForRequestIdentifier:")];
      [pidInv setArgument:&requestIdentifier atIndex:2];
      [pidInv invoke];
      [pidInv getReturnValue:&physicalPid];
    }

    vproc.physicalPid = physicalPid;

    // Use a unique virtual PID to avoid table overwrites
    [self.lock lock];
    vproc.pid = self.nextVirtualPid++;
    [self.lock unlock];

    [self registerProcess:vproc];

    HIAHLogInfo(HIAHLogKernel,
                "Spawned guest process (Virtual PID: %d, Physical PID: %d)",
                vproc.pid, physicalPid);

    // CRITICAL: Enable JIT for the extension process immediately when spawned
    // Don't wait for notification - enable JIT for ALL extension processes
    // Multiple extensions may spawn, and we need JIT enabled for all of them
    if (physicalPid > 0) {
      HIAHLogEx(
          HIAH_LOG_INFO, @"Kernel",
          @"Extension process spawned (PID: %d) - enabling JIT immediately",
          physicalPid);
      [self enableJITForExtensionProcess:physicalPid];

      // CRITICAL: Also retry multiple times to ensure JIT gets enabled
      // VPN detection can be flaky, so retries are essential
      dispatch_after(
          dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
          dispatch_get_main_queue(), ^{
            HIAHLogEx(
                HIAH_LOG_INFO, @"Kernel",
                @"Retrying JIT enablement for extension (PID: %d) - attempt 2",
                physicalPid);
            [self enableJITForExtensionProcess:physicalPid];
          });

      dispatch_after(
          dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
          dispatch_get_main_queue(), ^{
            HIAHLogEx(
                HIAH_LOG_INFO, @"Kernel",
                @"Retrying JIT enablement for extension (PID: %d) - attempt 3",
                physicalPid);
            [self enableJITForExtensionProcess:physicalPid];
          });

      dispatch_after(
          dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
          dispatch_get_main_queue(), ^{
            HIAHLogEx(
                HIAH_LOG_INFO, @"Kernel",
                @"Retrying JIT enablement for extension (PID: %d) - attempt 4",
                physicalPid);
            [self enableJITForExtensionProcess:physicalPid];
          });
    } else {
      HIAHLogEx(HIAH_LOG_WARNING, @"Kernel",
                @"Extension process spawned but PID is invalid (%d) - will "
                @"retry JIT enablement",
                physicalPid);
      // Retry getting PID after a short delay
      dispatch_after(
          dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
          dispatch_get_main_queue(), ^{
            pid_t retryPid = -1;
            if ([extension
                    respondsToSelector:NSSelectorFromString(
                                           @"pidForRequestIdentifier:")]) {
              NSInvocation *pidInv = [NSInvocation
                  invocationWithMethodSignature:
                      [extension methodSignatureForSelector:
                                     NSSelectorFromString(
                                         @"pidForRequestIdentifier:")]];
              [pidInv setTarget:extension];
              [pidInv setSelector:NSSelectorFromString(
                                      @"pidForRequestIdentifier:")];
              [pidInv setArgument:&requestIdentifier atIndex:2];
              [pidInv invoke];
              [pidInv getReturnValue:&retryPid];
            }
            if (retryPid > 0) {
              HIAHLogEx(HIAH_LOG_INFO, @"Kernel",
                        @"Got extension PID on retry (PID: %d) - enabling JIT "
                        @"with retries",
                        retryPid);
              [self enableJITForExtensionProcess:retryPid];

              // Also retry multiple times for the retry PID
              dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                           (int64_t)(0.5 * NSEC_PER_SEC)),
                             dispatch_get_main_queue(), ^{
                               [self enableJITForExtensionProcess:retryPid];
                             });
              dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                           (int64_t)(1.0 * NSEC_PER_SEC)),
                             dispatch_get_main_queue(), ^{
                               [self enableJITForExtensionProcess:retryPid];
                             });
              dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                           (int64_t)(2.0 * NSEC_PER_SEC)),
                             dispatch_get_main_queue(), ^{
                               [self enableJITForExtensionProcess:retryPid];
                             });
            }
          });
    }

    if (completion)
      completion(vproc.pid, nil);
  };

  // 4. Begin Request
  SEL beginRequestSelector =
      NSSelectorFromString(@"beginExtensionRequestWithInputItems:completion:");
  NSArray *inputItems = @[ item ];

  HIAHLogDebug(HIAHLogKernel, "Sending extension request for path: %s",
               [path UTF8String]);

  // Verify the extension responds to the selector
  if (![extension respondsToSelector:beginRequestSelector]) {
    HIAHLogError(HIAHLogKernel,
                 "Extension does not respond to "
                 "beginExtensionRequestWithInputItems:completion:");
    if (completion) {
      NSError *err = [NSError
          errorWithDomain:HIAHKernelErrorDomain
                     code:HIAHKernelErrorSpawnFailed
                 userInfo:@{
                   NSLocalizedDescriptionKey :
                       @"Extension does not support "
                       @"beginExtensionRequestWithInputItems:completion:"
                 }];
      completion(-1, err);
    }
    return;
  }

  HIAHLogDebug(HIAHLogKernel, "Extension responds to selector, invoking...");

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
  @try {
    HIAHLogEx(HIAH_LOG_INFO, @"Kernel",
              @"Invoking extension request with %lu input items",
              (unsigned long)inputItems.count);
    HIAHLogEx(HIAH_LOG_INFO, @"Kernel", @"Extension object: %@", extension);
    HIAHLogEx(HIAH_LOG_INFO, @"Kernel", @"Extension class: %@",
              [extension class]);

    // Verify the extension bundle's principal class is loaded
    Class principalClass = NSClassFromString(@"HIAHExtensionHandler");
    if (principalClass) {
      HIAHLogEx(HIAH_LOG_INFO, @"Kernel",
                @"✅ Principal class HIAHExtensionHandler found");
    } else {
      HIAHLogEx(HIAH_LOG_WARNING, @"Kernel",
                @"❌ Principal class HIAHExtensionHandler NOT found - "
                @"extension may not work");
    }

    // CRITICAL: beginExtensionRequestWithInputItems might not be calling
    // beginRequestWithExtensionContext So we'll manually create the extension
    // context and call the handler directly This is the same approach
    // LiveContainer uses
    HIAHLogEx(HIAH_LOG_INFO, @"Kernel",
              @"Manually creating extension context and calling handler...");

    // Create extension context manually
    Class extensionContextClass = NSClassFromString(@"NSExtensionContext");
    if (extensionContextClass && principalClass) {
      // Try to create context using alloc/init
      id context = nil;
      @try {
        context = [[extensionContextClass alloc] init];
        // Set input items using KVC or method
        if (context && [context respondsToSelector:@selector(setInputItems:)]) {
          [context performSelector:@selector(setInputItems:)
                        withObject:inputItems];
        } else if (context) {
          // Try using _setInputItems: (private API)
          SEL privateSetSel = NSSelectorFromString(@"_setInputItems:");
          if ([context respondsToSelector:privateSetSel]) {
            [context performSelector:privateSetSel withObject:inputItems];
          }
        }

        if (context) {
          HIAHLogEx(HIAH_LOG_INFO, @"Kernel",
                    @"✅ Extension context created - calling "
                    @"beginRequestWithExtensionContext directly");
          // Create handler instance and call beginRequestWithExtensionContext
          id handler = [[principalClass alloc] init];
          if (handler && [handler respondsToSelector:@selector
                                  (beginRequestWithExtensionContext:)]) {
            [handler
                performSelector:@selector(beginRequestWithExtensionContext:)
                     withObject:context];
            HIAHLogEx(HIAH_LOG_INFO, @"Kernel",
                      @"✅ Manually called beginRequestWithExtensionContext on "
                      @"handler");

            // Also call the standard API as fallback
            [extension performSelector:beginRequestSelector
                            withObject:inputItems
                            withObject:completionBlock];
          } else {
            HIAHLogEx(
                HIAH_LOG_WARNING, @"Kernel",
                @"❌ Handler doesn't respond to "
                @"beginRequestWithExtensionContext - using standard API only");
            [extension performSelector:beginRequestSelector
                            withObject:inputItems
                            withObject:completionBlock];
          }
        } else {
          HIAHLogEx(HIAH_LOG_WARNING, @"Kernel",
                    @"❌ Failed to create extension context - using standard "
                    @"API only");
          [extension performSelector:beginRequestSelector
                          withObject:inputItems
                          withObject:completionBlock];
        }
      } @catch (NSException *ex) {
        HIAHLogEx(
            HIAH_LOG_WARNING, @"Kernel",
            @"Exception creating context manually: %@ - using standard API",
            ex.reason);
        [extension performSelector:beginRequestSelector
                        withObject:inputItems
                        withObject:completionBlock];
      }
    } else {
      HIAHLogEx(HIAH_LOG_WARNING, @"Kernel",
                @"❌ Extension context class or principal class not found - "
                @"using standard API only");
      [extension performSelector:beginRequestSelector
                      withObject:inputItems
                      withObject:completionBlock];
    }

    HIAHLogDebug(HIAHLogKernel, "Extension request invoked");
    HIAHLogEx(HIAH_LOG_INFO, @"Kernel",
              @"Extension request invocation completed - check extension logs");

    // Give the extension a moment to process the request
    // The extension will call beginRequestWithExtensionContext which should log
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
          HIAHLogEx(HIAH_LOG_INFO, @"Kernel",
                    @"Extension request should have been processed by now - "
                    @"check extension logs at: "
                    @"/var/mobile/Containers/Shared/AppGroup/"
                    @"1EBEDA36-DEEE-42F7-8B5B-C4C228DE847C/HIAHExtension.log");
        });
  } @catch (NSException *exception) {
    HIAHLogError(HIAHLogKernel, "Exception invoking extension: %s - %s",
                 exception.name ? [exception.name UTF8String] : "(null)",
                 exception.reason ? [exception.reason UTF8String] : "(null)");
    if (completion) {
      NSError *err = [NSError
          errorWithDomain:HIAHKernelErrorDomain
                     code:HIAHKernelErrorSpawnFailed
                 userInfo:@{
                   NSLocalizedDescriptionKey :
                       [NSString stringWithFormat:@"Extension exception: %@",
                                                  exception.reason]
                 }];
      completion(-1, err);
    }
  }
#pragma clang diagnostic pop
}

/// Enable JIT for an extension process by PID
- (void)enableJITForExtensionProcess:(pid_t)pid {
  HIAHLogEx(HIAH_LOG_INFO, @"Kernel",
            @"Enabling JIT for extension process (PID: %d)...", pid);

  // Use HIAHJITManager to enable JIT
  Class jitManagerClass = NSClassFromString(@"HIAHJITManager");
  if (!jitManagerClass) {
    HIAHLogEx(HIAH_LOG_WARNING, @"Kernel", @"HIAHJITManager class not found");
    return;
  }

  SEL sharedManagerSel = NSSelectorFromString(@"sharedManager");
  if (![jitManagerClass respondsToSelector:sharedManagerSel]) {
    HIAHLogEx(HIAH_LOG_WARNING, @"Kernel",
              @"HIAHJITManager.sharedManager not found");
    return;
  }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
  id jitManager = [jitManagerClass performSelector:sharedManagerSel];
#pragma clang diagnostic pop
  if (!jitManager) {
    HIAHLogEx(HIAH_LOG_WARNING, @"Kernel",
              @"Failed to get HIAHJITManager instance");
    return;
  }

  SEL enableSel = NSSelectorFromString(@"enableJITForPID:completion:");
  if (![jitManager respondsToSelector:enableSel]) {
    HIAHLogEx(HIAH_LOG_WARNING, @"Kernel",
              @"enableJITForPID:completion: not found");
    return;
  }

  // Enable JIT immediately - don't wait for the extension to start
  // The extension will wait for JIT to be enabled if needed
  // The JITManager will handle VPN checking and retries internally
  dispatch_async(dispatch_get_main_queue(), ^{
    void (^completion)(BOOL, NSError *) = ^(BOOL success, NSError *error) {
      if (success) {
        HIAHLogEx(HIAH_LOG_INFO, @"Kernel",
                  @"✅ JIT enabled successfully for extension (PID: %d)", pid);
      } else {
        HIAHLogEx(HIAH_LOG_WARNING, @"Kernel",
                  @"❌ Failed to enable JIT for extension (PID: %d): %@", pid,
                  error);
        // Retry after a delay - VPN detection might be flaky
        HIAHLogEx(
            HIAH_LOG_INFO, @"Kernel",
            @"Retrying JIT enablement for extension (PID: %d) after delay...",
            pid);
        dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{
              NSMethodSignature *retrySig =
                  [jitManager methodSignatureForSelector:enableSel];
              NSInvocation *retryInv =
                  [NSInvocation invocationWithMethodSignature:retrySig];
              [retryInv setTarget:jitManager];
              [retryInv setSelector:enableSel];
              [retryInv setArgument:&pid atIndex:2];
              void (^retryCompletion)(BOOL, NSError *) =
                  ^(BOOL retrySuccess, NSError *retryError) {
                    if (retrySuccess) {
                      HIAHLogEx(HIAH_LOG_INFO, @"Kernel",
                                @"✅ JIT enabled successfully on retry for "
                                @"extension (PID: %d)",
                                pid);
                    } else {
                      HIAHLogEx(HIAH_LOG_WARNING, @"Kernel",
                                @"❌ JIT enablement retry failed for extension "
                                @"(PID: %d): %@",
                                pid, retryError);
                    }
                  };
              [retryInv setArgument:&retryCompletion atIndex:3];
              [retryInv invoke];
            });
      }
    };

    NSMethodSignature *sig = [jitManager methodSignatureForSelector:enableSel];
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    [inv setTarget:jitManager];
    [inv setSelector:enableSel];
    [inv setArgument:&pid atIndex:2];
    [inv setArgument:&completion atIndex:3];
    [inv invoke];
  });
}

/// Enable JIT for an extension process with aggressive retries
- (void)enableJITForExtensionProcessWithRetries:(pid_t)pid {
  if (pid <= 0)
    return;

  HIAHLogEx(HIAH_LOG_INFO, @"Kernel",
            @"Enabling JIT for extension process (PID: %d) with retries...",
            pid);

  // Enable JIT immediately
  [self enableJITForExtensionProcess:pid];

  // Retry multiple times to handle flaky VPN detection
  dispatch_after(
      dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
      dispatch_get_main_queue(), ^{
        [self enableJITForExtensionProcess:pid];
      });

  dispatch_after(
      dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
      dispatch_get_main_queue(), ^{
        [self enableJITForExtensionProcess:pid];
      });

  dispatch_after(
      dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
      dispatch_get_main_queue(), ^{
        [self enableJITForExtensionProcess:pid];
      });
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

  [self.activeExtensions removeAllObjects];

  HIAHLogInfo(HIAHLogKernel, "Shutdown complete");
}

@end
