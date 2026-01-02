# HIAH Kernel – Library Documentation

**House-in-a-House Kernel** is a virtual kernel library for iOS that enables controlled multi-process execution within sandboxed iOS applications.

## Overview

HIAH Kernel provides the core mechanisms to spawn, manage, and communicate with multiple processes inside a single iOS application sandbox. This allows developers to build applications that can:

- **Spawn Virtual Processes** – Run multiple binaries (`.dylib` and executables) under one app
- **Intercept System Calls** – Hook `posix_spawn`, `execve`, and `waitpid` for controlled execution
- **Process Isolation** – Leverage iOS App Extensions (`NSExtension`) for process separation
- **Inter-Process Communication** – Unix sockets and XPC for host-guest communication
- **Runtime Code Execution** – Sign and execute arbitrary binaries at runtime

## Installation

### Option 1: Nix Flake (Recommended for Nix Users)

```nix
# In your flake.nix
{
  inputs = {
    hiahkernel.url = "github:aspauldingcode/HIAHKernel";
  };
  
  outputs = { self, nixpkgs, hiahkernel, ... }:
    # Add hiahkernel to your buildInputs
    buildInputs = [ hiahkernel.packages.${system}.hiahkernel-library ];
}
```

### Option 2: Xcode Project (For iOS Developers)

1. Clone or download the repository
2. Open `HIAHKernel.xcodeproj` in Xcode
3. Build the `HIAHKernel` framework target for your desired platform (iOS Device/Simulator)
4. Drag the built `HIAHKernel.framework` into your project
5. Add to "Frameworks, Libraries, and Embedded Content" with "Embed & Sign"

### Option 3: Manual Integration

Copy the following files into your project:

```
src/HIAHKernel/
├── Public/
│   ├── HIAHKernel.h
│   ├── HIAHProcess.h
│   └── HIAHLogging.h
└── Core/
    ├── HIAHKernel.m
    ├── HIAHProcess.m
    ├── Hooks/
    │   ├── HIAHHook.c
    │   └── HIAHDyldBypass.m
    └── Logging/
        └── HIAHLogging.m
```

## Quick Start

### 1. Import the Library

```objc
#import <HIAHKernel/HIAHKernel.h>
#import <HIAHKernel/HIAHProcess.h>
```

### 2. Initialize the Kernel

```objc
// Get the shared kernel instance (singleton)
HIAHKernel *kernel = [HIAHKernel sharedKernel];

// Configure (optional - defaults work for most cases)
kernel.appGroupIdentifier = @"group.com.yourcompany.yourapp";
kernel.extensionIdentifier = @"com.yourcompany.yourapp.ProcessRunner";

// Set up output callback to receive process stdout/stderr
kernel.onOutput = ^(pid_t pid, NSString *output) {
    NSLog(@"[Process %d] %@", pid, output);
};
```

### 3. Spawn a Virtual Process

```objc
[kernel spawnVirtualProcessWithPath:@"/path/to/binary.dylib"
                          arguments:@[@"arg1", @"arg2"]
                        environment:@{@"HOME": @"/tmp", @"PATH": @"/usr/bin"}
                         completion:^(pid_t pid, NSError *error) {
    if (error) {
        NSLog(@"Failed to spawn: %@", error.localizedDescription);
        return;
    }
    NSLog(@"Process spawned with virtual PID: %d", pid);
}];
```

### 4. Manage Processes

```objc
// Get all running processes
NSArray<HIAHProcess *> *processes = [kernel allProcesses];

// Find a specific process
HIAHProcess *process = [kernel processForPID:virtualPID];

// Check process state
if (process.isExited) {
    NSLog(@"Process exited with code: %d", process.exitCode);
}

// Unregister a terminated process
[kernel unregisterProcessWithPID:virtualPID];
```

### 5. Clean Up

```objc
// When your app terminates or you're done with the kernel
[kernel shutdown];
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Your iOS Application                         │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                      HIAHKernel                              ││
│  │  ┌──────────────────┐  ┌────────────────────────────────┐  ││
│  │  │   Process Table  │  │    Control Socket (IPC)        │  ││
│  │  │  - Virtual PIDs  │  │    - Spawn commands            │  ││
│  │  │  - Exit codes    │  │    - Output relay              │  ││
│  │  │  - State tracking│  │    - Signal forwarding         │  ││
│  │  └──────────────────┘  └────────────────────────────────┘  ││
│  └─────────────────────────────────────────────────────────────┘│
│                              │                                   │
│                     NSExtension API                              │
│                              ▼                                   │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │             HIAHProcessRunner.appex                          ││
│  │  ┌─────────────────┐  ┌─────────────────────────────────┐  ││
│  │  │    litehook     │  │   Guest Process Execution       │  ││
│  │  │  - posix_spawn  │  │   - dlopen + entry point call   │  ││
│  │  │  - execve hook  │  │   - stdout/stderr capture       │  ││
│  │  │  - waitpid      │  │   - Signal handling             │  ││
│  │  └─────────────────┘  └─────────────────────────────────┘  ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

## API Reference

### HIAHKernel Class

#### Singleton Access

```objc
+ (instancetype)sharedKernel;
```
Returns the shared kernel instance. Thread-safe.

#### Configuration Properties

| Property | Type | Description |
|----------|------|-------------|
| `appGroupIdentifier` | `NSString *` | App group for shared storage (default: `group.com.aspauldingcode.HIAHDesktop`) |
| `extensionIdentifier` | `NSString *` | Bundle ID of the process runner extension |
| `controlSocketPath` | `NSString *` (readonly) | Auto-generated path to the control socket |

#### Process Management Methods

```objc
// Register a new process in the kernel's table
- (void)registerProcess:(HIAHProcess *)process;

// Remove a process from tracking
- (void)unregisterProcessWithPID:(pid_t)pid;

// Look up a process by virtual PID
- (nullable HIAHProcess *)processForPID:(pid_t)pid;

// Look up by NSExtension request ID
- (nullable HIAHProcess *)processForRequestIdentifier:(NSUUID *)uuid;

// Get all tracked processes
- (NSArray<HIAHProcess *> *)allProcesses;

// Handle process exit (usually called internally)
- (void)handleExitForPID:(pid_t)pid exitCode:(int)exitCode;
```

#### Process Spawning

```objc
- (void)spawnVirtualProcessWithPath:(NSString *)path
                          arguments:(nullable NSArray<NSString *> *)arguments
                        environment:(nullable NSDictionary<NSString *, NSString *> *)environment
                         completion:(void (^)(pid_t pid, NSError * _Nullable error))completion;
```

**Parameters:**
- `path`: Path to the executable or `.dylib` to run
- `arguments`: Command-line arguments (argv[1:])
- `environment`: Environment variables dictionary
- `completion`: Callback with virtual PID on success, or error on failure

#### Output Observation

```objc
@property (nonatomic, copy, nullable) void (^onOutput)(pid_t pid, NSString *output);
```
Called on a background queue when a guest process writes to stdout/stderr.

#### Lifecycle

```objc
- (void)shutdown;
```
Closes all sockets, cleans up resources, and terminates tracked processes.

### HIAHProcess Class

Represents a virtual process managed by the kernel.

#### Properties

| Property | Type | Description |
|----------|------|-------------|
| `pid` | `pid_t` | Virtual PID assigned by the kernel |
| `physicalPid` | `pid_t` | Actual iOS process ID (usually the extension) |
| `ppid` | `pid_t` | Parent process ID |
| `executablePath` | `NSString *` | Path to the running binary |
| `arguments` | `NSArray<NSString *> *` | Command-line arguments |
| `environment` | `NSDictionary<NSString *, NSString *> *` | Environment variables |
| `exitCode` | `int` | Exit code (valid when `isExited` is YES) |
| `isExited` | `BOOL` | Whether the process has terminated |
| `requestIdentifier` | `NSUUID *` | NSExtension request tracking ID |
| `startTime` | `NSDate *` | When the process was spawned |
| `workingDirectory` | `NSString *` | Process working directory |

#### Factory Method

```objc
+ (instancetype)processWithPath:(NSString *)path
                      arguments:(nullable NSArray<NSString *> *)arguments
                    environment:(nullable NSDictionary<NSString *, NSString *> *)environment;
```

### Notifications

Subscribe to these notifications for process lifecycle events:

```objc
// Posted when a process is spawned
extern NSNotificationName const HIAHKernelProcessSpawnedNotification;

// Posted when a process exits
extern NSNotificationName const HIAHKernelProcessExitedNotification;

// Posted when process output is received
extern NSNotificationName const HIAHKernelProcessOutputNotification;
```

**Notification `userInfo` keys:**
- `@"pid"`: `NSNumber` containing the virtual PID
- `@"exitCode"`: `NSNumber` containing exit code (for exit notification)
- `@"output"`: `NSString` containing output (for output notification)

### Error Handling

```objc
extern NSErrorDomain const HIAHKernelErrorDomain;

typedef NS_ENUM(NSInteger, HIAHKernelError) {
    HIAHKernelErrorExtensionNotFound = 1,    // ProcessRunner.appex not found
    HIAHKernelErrorExtensionLoadFailed = 2,  // Failed to load extension
    HIAHKernelErrorSocketCreationFailed = 3, // IPC socket creation failed
    HIAHKernelErrorSpawnFailed = 4,          // Process spawn failed
    HIAHKernelErrorInvalidPath = 5,          // Invalid executable path
    HIAHKernelErrorProcessNotFound = 6,      // PID not in process table
};
```

## Advanced Usage

### Custom Hook Installation

For processes that need system call interception:

```objc
#import <HIAHKernel/litehook.h>
#import <HIAHKernel/HIAHGuestHooks.h>

// Install hooks before loading guest code
HIAHGuestHooksInstall();

// Hooks are now active for:
// - posix_spawn → redirected through kernel
// - execve → captured and handled
// - waitpid → virtual PID resolution
```

### Including HIAHProcessRunner Extension

Your app bundle must include the `HIAHProcessRunner.appex` extension:

```
YourApp.app/
├── YourApp (executable)
├── Info.plist
├── Frameworks/
│   └── HIAHKernel.framework/
└── PlugIns/
    └── HIAHProcessRunner.appex/
        ├── HIAHProcessRunner (executable)
        └── Info.plist
```

**Extension Info.plist requirements:**

```xml
<key>NSExtension</key>
<dict>
    <key>NSExtensionPointIdentifier</key>
    <string>com.apple.intents-service</string>
    <key>NSExtensionPrincipalClass</key>
    <string>HIAHProcessRunner</string>
</dict>
```

### Entitlements

Your app requires these entitlements for full functionality:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" 
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Required: App group for shared storage with extension -->
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.aspauldingcode.HIAHDesktop</string>
    </array>
</dict>
</plist>
```

**Important:** The same App Group identifier must be used in both the host app and HIAHProcessRunner extension entitlements. This enables:
- Shared file access between host and extension
- Files.app visibility for the Documents folder
- App staging for extension loading

## Integration with HIAH Top

To include process monitoring in your app, you can integrate HIAH Top:

```objc
#import "HIAHProcessManager.h"
#import "HIAHTopViewController.h"

// Initialize process manager with kernel integration
HIAHProcessManager *manager = [[HIAHProcessManager alloc] initWithKernel:[HIAHKernel sharedKernel]];
manager.delegate = self;
[manager startSampling];

// Present the process monitor UI
HIAHTopViewController *topVC = [[HIAHTopViewController alloc] init];
[self presentViewController:topVC animated:YES completion:nil];
```

See [HIAHTop.md](./HIAHTop.md) for full process manager documentation.

## Requirements

| Requirement | Minimum Version |
|-------------|-----------------|
| iOS | 16.0+ |
| Xcode | 15.0+ |
| Swift | 5.9+ (for Swift interop) |

**Supported Platforms:**
- iOS Simulator (arm64, x86_64)
- iOS Device (arm64) – requires proper code signing
- macOS Catalyst (future)

## Thread Safety

- `[HIAHKernel sharedKernel]` is thread-safe
- `onOutput` callback is invoked on a background queue
- Process table operations are internally synchronized
- Spawn completion callbacks are invoked on the main queue

## Limitations

1. **Code Signing**: Guest binaries must be properly signed or the device must allow unsigned code
2. **Sandbox Restrictions**: Some system calls may be blocked by iOS sandbox
3. **Memory Limits**: All processes share the host app's memory allocation
4. **Extension Lifecycle**: iOS may terminate extensions under memory pressure

## Example: Complete Integration

```objc
@interface MyAppDelegate () <UIApplicationDelegate>
@property (nonatomic, strong) HIAHKernel *kernel;
@end

@implementation MyAppDelegate

- (BOOL)application:(UIApplication *)application 
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    
    // Initialize kernel
    self.kernel = [HIAHKernel sharedKernel];
    self.kernel.appGroupIdentifier = @"group.com.mycompany.myapp";
    
    // Set up output handling
    self.kernel.onOutput = ^(pid_t pid, NSString *output) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self appendToConsole:[NSString stringWithFormat:@"[%d] %@", pid, output]];
        });
    };
    
    // Listen for process events
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(processDidExit:)
                                                 name:HIAHKernelProcessExitedNotification
                                               object:nil];
    
    return YES;
}

- (void)launchMyProcess {
    NSString *binaryPath = [[NSBundle mainBundle] pathForResource:@"myhelper" 
                                                           ofType:@"dylib"];
    
    [self.kernel spawnVirtualProcessWithPath:binaryPath
                                   arguments:@[@"--verbose"]
                                 environment:@{@"DEBUG": @"1"}
                                  completion:^(pid_t pid, NSError *error) {
        if (error) {
            [self showError:error];
            return;
        }
        NSLog(@"Helper process running with PID %d", pid);
    }];
}

- (void)processDidExit:(NSNotification *)notification {
    pid_t pid = [notification.userInfo[@"pid"] intValue];
    int exitCode = [notification.userInfo[@"exitCode"] intValue];
    NSLog(@"Process %d exited with code %d", pid, exitCode);
}

- (void)applicationWillTerminate:(UIApplication *)application {
    [self.kernel shutdown];
}

@end
```

## License

MIT License – See [LICENSE](../LICENSE) for details.

## See Also

- [HIAH Top Documentation](./HIAHTop.md) – Process Manager
- [HIAH Desktop Documentation](./HIAHDesktop.md) – Desktop Environment
- [HIAHProcessRunner Documentation](./HIAHProcessRunner.md) – Guest App Extension
- [Virtual Filesystem Documentation](./VirtualFilesystem.md) – Storage & Files.app Integration
- [README](../README.md) – Project Overview

