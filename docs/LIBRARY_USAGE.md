# Using HIAHKernel as a Library

HIAHKernel is designed to be imported into your iOS projects as a framework. This guide shows how to integrate and use it.

## Quick Start

### 1. Build the Framework

```bash
# Build HIAHKernel framework
nix run .#build -- --kernel

# Or build the full demo app (includes framework)
nix run .#build
```

### 2. Add to Your Project

**Option A: Copy the built framework**

After building, copy `HIAHKernel.framework` from:
```
~/Library/Developer/Xcode/DerivedData/HIAHDesktop-*/Build/Products/Debug-iphonesimulator/
```

Add it to your Xcode project:
- **Link Binary With Libraries** in Build Phases
- **Embed & Sign** in General > Frameworks

**Option B: Add as subproject**

Add `HIAHDesktop.xcodeproj` as a subproject and link against the HIAHKernel target.

### 2. Import the Headers

```objc
#import <HIAHKernel/HIAHKernel.h>
#import <HIAHKernel/HIAHProcess.h>
```

### 3. Initialize the Kernel

```objc
// AppDelegate.m
- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    
    // Get the shared kernel instance
    HIAHKernel *kernel = [HIAHKernel sharedKernel];
    
    // Configure for your app
    kernel.appGroupIdentifier = @"group.com.yourapp";
    kernel.extensionIdentifier = @"com.yourapp.ProcessRunner";
    
    // Set up output handler
    kernel.onOutput = ^(pid_t pid, NSString *output) {
        NSLog(@"[PID %d] %@", pid, output);
    };
    
    return YES;
}
```

### 4. Spawn Processes

```objc
[kernel spawnProcessWithPath:@"/path/to/binary"
                   arguments:@[@"arg1", @"arg2"]
                 environment:nil
                  completion:^(pid_t pid, NSError *error) {
    if (error) {
        NSLog(@"Spawn failed: %@", error);
    } else {
        NSLog(@"Process started with PID: %d", pid);
    }
}];
```

## Example: HIAHDesktop

HIAHDesktop serves as the reference implementation showing how to use HIAHKernel:

```
src/HIAHDesktop/
├── main.m              # Entry point
├── AppDelegate.h/m     # Kernel initialization
├── SceneDelegate.h/m   # Window setup
└── MainViewController.h/m  # UI demonstrating kernel usage
```

Key patterns demonstrated:

1. **Kernel initialization** in `AppDelegate.m`
2. **Process table display** in `MainViewController.m`
3. **Output handling** via notification center
4. **Process lifecycle management** (spawn, kill, wait)

## API Reference

### HIAHKernel

```objc
// Singleton access
+ (instancetype)sharedKernel;

// Configuration
@property NSString *appGroupIdentifier;
@property NSString *extensionIdentifier;
@property (copy) void(^onOutput)(pid_t, NSString *);

// Process management
- (void)spawnProcessWithPath:(NSString *)path
                   arguments:(NSArray<NSString *> *)arguments
                 environment:(NSDictionary<NSString *, NSString *> *)environment
                  completion:(void(^)(pid_t pid, NSError *error))completion;

- (BOOL)killProcess:(pid_t)pid signal:(int)signal;
- (pid_t)waitForProcess:(pid_t)pid status:(int *)status options:(int)options;
- (NSArray<HIAHProcess *> *)allProcesses;
- (HIAHProcess *)processForPID:(pid_t)pid;
- (void)shutdown;
```

### HIAHProcess

```objc
@property (readonly) pid_t pid;
@property (readonly) NSString *executablePath;
@property (readonly) NSArray<NSString *> *arguments;
@property (readonly) HIAHProcessState state;
@property (readonly) BOOL isExited;
@property (readonly) int exitCode;
```

### Process States

```objc
typedef NS_ENUM(NSInteger, HIAHProcessState) {
    HIAHProcessStateCreated,    // Initialized but not yet running
    HIAHProcessStateRunning,    // Currently executing
    HIAHProcessStateStopped,    // Paused (SIGSTOP)
    HIAHProcessStateZombie,     // Exited, awaiting cleanup
    HIAHProcessStateTerminated  // Fully terminated
};
```

### Notifications

```objc
// Posted when a process is spawned
HIAHKernelProcessSpawnedNotification
// userInfo: @{@"process": HIAHProcess *}

// Posted when a process exits
HIAHKernelProcessExitedNotification
// userInfo: @{@"process": HIAHProcess *, @"exitCode": NSNumber *}
```

## Requirements

- iOS 16.0+
- Xcode 15+
- App Group entitlement (for IPC with extensions)

## Project Structure

For Xcode projects using XcodeGen:

```yaml
targets:
  YourApp:
    dependencies:
      - target: HIAHKernel
        embed: true
        link: true
    
    settings:
      HEADER_SEARCH_PATHS:
        - $(SRCROOT)/path/to/HIAHKernel/src/HIAHKernel/Public
```

## License

HIAHKernel is licensed under the MIT License.
