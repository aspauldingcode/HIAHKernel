# HIAHKernel

The core virtual kernel library for iOS multi-process execution.

## Overview

HIAHKernel provides:
- Process table management
- NSExtension-based process spawning
- Unix socket IPC
- POSIX syscall interception

## Usage

```objc
#import <HIAHKernel/HIAHKernel.h>

// Get singleton
HIAHKernel *kernel = [HIAHKernel sharedKernel];

// Configure
kernel.appGroupIdentifier = @"group.com.yourapp";
kernel.extensionIdentifier = @"com.yourapp.ProcessRunner";

// Handle output
kernel.onOutput = ^(pid_t pid, NSString *output) {
    NSLog(@"[%d] %@", pid, output);
};

// Spawn process
[kernel spawnVirtualProcessWithPath:@"/path/to/binary"
                          arguments:@[@"arg1"]
                        environment:@{@"HOME": @"/var/mobile"}
                         completion:^(pid_t pid, NSError *error) {
    if (error) {
        NSLog(@"Failed: %@", error);
    }
}];
```

## API Reference

### HIAHKernel

| Property/Method | Description |
|-----------------|-------------|
| `+sharedKernel` | Singleton instance |
| `appGroupIdentifier` | App Group for IPC |
| `extensionIdentifier` | ProcessRunner bundle ID |
| `onOutput` | Output callback block |
| `-spawnVirtualProcessWithPath:...` | Spawn a process |
| `-processForPID:` | Find process by PID |
| `-allProcesses` | Get all processes |
| `-registerProcess:` | Add to process table |
| `-unregisterProcessWithPID:` | Remove from table |
| `-shutdown` | Clean up resources |

### HIAHProcess

| Property | Description |
|----------|-------------|
| `pid` | Virtual process ID |
| `physicalPid` | Actual extension PID |
| `executablePath` | Binary path |
| `arguments` | Command line args |
| `environment` | Environment variables |
| `isExited` | Has process exited |
| `exitCode` | Exit status |
| `startTime` | When spawned |

### Notifications

| Name | Description |
|------|-------------|
| `HIAHKernelProcessSpawnedNotification` | Process spawned |
| `HIAHKernelProcessExitedNotification` | Process exited |
| `HIAHKernelProcessOutputNotification` | Output received |

### Error Codes

| Code | Description |
|------|-------------|
| `HIAHKernelErrorExtensionNotFound` | Extension missing |
| `HIAHKernelErrorExtensionLoadFailed` | Extension failed |
| `HIAHKernelErrorSocketCreationFailed` | IPC failed |
| `HIAHKernelErrorSpawnFailed` | Spawn failed |
| `HIAHKernelErrorInvalidPath` | Bad path |

## Architecture

```
HIAHKernel (Host)              ProcessRunner (Extension)
      │                               │
      │ 1. spawnVirtualProcess       │
      ├──────────────────────────────►│
      │                               │ 2. patch binary
      │                               │ 3. sign if needed
      │                               │ 4. dlopen
      │                               │
      │◄──────────────────────────────┤ 5. stdout/stderr
      │    Unix Socket IPC            │
```

## Files

```
src/HIAHKernel/
├── Public/
│   ├── HIAHKernel.h      # Main API
│   ├── HIAHProcess.h     # Process model
│   └── HIAHLogging.h     # Logging utilities
└── Core/
    ├── HIAHKernel.m      # Implementation
    ├── HIAHProcess.m
    ├── Hooks/
    │   ├── HIAHGuestHooks.*   # POSIX interception
    │   ├── HIAHDyldBypass.*   # Unsigned code loading
    │   └── HIAHHook.*         # Symbol hooking
    └── Utils/
        └── HIAHMachOUtils.*   # Binary patching
```

## License

MIT License - use freely in any project.
