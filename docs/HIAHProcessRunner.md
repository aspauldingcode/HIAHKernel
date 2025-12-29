# HIAHProcessRunner – Guest App Extension Documentation

**HIAHProcessRunner** is an iOS app extension that enables HIAH Desktop to load and execute external iOS applications (`.ipa` files) within the HIAH environment. It uses standard iOS extension APIs combined with dynamic linking techniques to run guest applications.

## Overview

When HIAH Desktop needs to run an external `.ipa` app (not bundled SwiftUI apps), it spawns the HIAHProcessRunner extension which:

1. Receives the guest app path via `NSExtensionContext` (from App Group staging area)
2. Patches the guest binary from `MH_EXECUTE` to `MH_DYLIB`
3. Loads the guest via `dlopen`
4. Hooks `UIApplicationMain` to intercept the guest's startup
5. Invokes the guest's `main()` function

## Storage & App Group

### Why App Groups?

iOS app extensions run in a **separate sandbox** from their host app. They cannot directly access the host app's Documents folder. HIAH Desktop uses **App Groups** to share files between the host and extension.

**App Group Identifier:** `group.com.aspauldingcode.HIAHDesktop`

### Staging Flow

```
Documents/Applications/         App Group/staging/           Extension Process
       (Files.app visible)           (Shared container)
             │                              │                       │
             │      ┌── On Launch ──┐       │                       │
             ▼      │   Copy App    │       ▼                       │
  ┌─────────────────┴───────────────┴─────────────────┐             │
  │  UTM SE.app  ─────────────────▶  UTM SE.app       │             │
  │  (permanent)                     (temporary copy) │             │
  └───────────────────────────────────────────────────┘             │
                                           │                        │
                                           │    Path sent via XPC   │
                                           └────────────────────────▶
                                                                    │
                                                            dlopen(staged path)
                                                                    │
                                                              Run guest app
```

### Key Points

- **Files.app visible:** Users can browse/edit apps in `Documents/Applications/`
- **Staging is automatic:** Host app copies to App Group before launching
- **Extension reads from App Group:** Bypasses sandbox restrictions
- **Changes in Files.app take effect on next launch**

## Architecture

```
HIAH Desktop                           HIAHProcessRunner Extension
┌─────────────────┐                    ┌─────────────────────────────┐
│                 │                    │                             │
│ HIAHKernel      │─── NSExtension ──▶│ NSExtensionMain            │
│                 │    request         │   │                         │
│ ┌─────────────┐ │                    │   ├── hook dlopen           │
│ │ FBScene     │ │                    │   │   (intercept UIKit)     │
│ │ (captures   │ │◀── UI Layer ──────│   │                         │
│ │  guest UI)  │ │                    │   └── call real             │
│ └─────────────┘ │                    │       NSExtensionMain       │
│                 │                    │         │                   │
└─────────────────┘                    │         ▼                   │
                                       │   UIApplicationMain (our)   │
                                       │         │                   │
                                       │         ▼                   │
                                       │   HIAHRunGuestProcess       │
                                       │         │                   │
                                       │   ┌─────┴─────┐             │
                                       │   │ CFRunLoop │ (waits)     │
                                       │   └─────┬─────┘             │
                                       │         │                   │
                                       │   beginRequestWith          │
                                       │   ExtensionContext          │
                                       │   (stores context,          │
                                       │    stops runloop)           │
                                       │         │                   │
                                       │         ▼                   │
                                       │   dlopen guest app          │
                                       │         │                   │
                                       │         ▼                   │
                                       │   call guest main()         │
                                       │                             │
                                       └─────────────────────────────┘
```

## How It Works

### 1. Extension Entry Point

Unlike regular iOS apps, app extensions use `NSExtensionMain` as their entry point. HIAHProcessRunner overrides this to set up hooks before the extension framework loads:

```objc
int NSExtensionMain(int argc, char * argv[]) {
    // Disable NSXPCDecoder validation
    // (required for passing custom objects via extension context)
    
    // Hook dlopen in dyld's vtable
    HIAHHookDyldFunction("dlopen", 2, (void**)&_originalDlopen, HIAHDlopenHook);
    
    // Call the real NSExtensionMain
    return real_NSExtensionMain(argc, argv);
}
```

### 2. dlopen Hook

When the extension framework tries to load UIKit, our hook intercepts it and returns `RTLD_MAIN_ONLY` instead. This causes the dynamic linker to look for symbols in the main binary (our extension) rather than loading UIKit:

```objc
static void *HIAHDlopenHook(void *dyldInstance, const char *path, int mode) {
    if (path && strcmp(path, "/System/Library/Frameworks/UIKit.framework/UIKit") == 0) {
        // Prevent double-loading UIKit
        return RTLD_MAIN_ONLY;
    }
    return _originalDlopen(dyldInstance, path, mode);
}
```

### 3. UIApplicationMain Override

We define our own `UIApplicationMain` with default visibility that overrides the UIKit symbol. When the extension framework calls `UIApplicationMain`, our version is called instead:

```objc
__attribute__((visibility("default")))
int UIApplicationMain(int argc, char *argv[], NSString *principalClass, 
                      NSString *delegateClass) {
    return HIAHRunGuestProcess(argc, argv);
}
```

### 4. CFRunLoop Synchronization

`HIAHRunGuestProcess` uses `CFRunLoopRun/CFRunLoopStop` to synchronize with the extension context:

```objc
static int HIAHRunGuestProcess(int argc, char *argv[]) {
    // Wait for extension context to be delivered
    CFRunLoopRun();
    
    // Context is now available
    NSDictionary *request = [HIAHExtensionHandler spawnRequest];
    
    // Load and run guest app...
}
```

When `beginRequestWithExtensionContext:` is called:

```objc
- (void)beginRequestWithExtensionContext:(NSExtensionContext *)context {
    _extensionContext = context;
    _spawnRequest = [context.inputItems.firstObject userInfo];
    
    // Resume HIAHRunGuestProcess
    CFRunLoopStop(CFRunLoopGetMain());
}
```

### 5. dyld Vtable Hooking

We can't use standard symbol rebinding (like fishhook) for dyld's internal functions because they're resolved from a vtable. HIAHProcessRunner parses ARM64 instructions to find and patch dyld's vtable:

```objc
static bool HIAHHookDyldFunction(const char *funcName, uint32_t adrpOffset, 
                                  void **outOrigFunc, void *hookFunc) {
    // 1. Find function in dyld via dlsym
    uint32_t *funcAddr = dlsym(RTLD_DEFAULT, funcName);
    
    // 2. Parse ADRP/LDR instructions to locate gDyld structure
    // (dyld functions load their implementation from a vtable)
    
    // 3. Make vtable entry writable via vm_protect
    vm_protect(mach_task_self(), vtableSlot, sizeof(void*), FALSE, 
               VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
    
    // 4. Replace function pointer
    *outOrigFunc = *(void **)vtableSlot;
    *(void **)vtableSlot = hookFunc;
    
    // 5. Restore protection
    vm_protect(mach_task_self(), vtableSlot, sizeof(void*), FALSE, VM_PROT_READ);
}
```

### 6. Mach-O Binary Patching

iOS apps are compiled as `MH_EXECUTE` type, which can't be loaded via `dlopen`. HIAH patches the binary to `MH_DYLIB`:

```objc
// In HIAHMachOUtils.m
if (header->filetype == MH_EXECUTE) {
    header->filetype = MH_DYLIB;
}
```

### 7. Entry Point Discovery

We find the guest app's entry point by:
1. First trying `dlsym(handle, "main")`
2. Falling back to parsing the `LC_MAIN` load command from the Mach-O header

```objc
static void *HIAHFindEntryPoint(void *handle, NSString *path) {
    void *entry = dlsym(handle, "main");
    if (entry) return entry;
    
    // Parse LC_MAIN from Mach-O header
    for (uint32_t i = 0; i < header->ncmds; i++) {
        if (lc->cmd == LC_MAIN) {
            struct entry_point_command *ep = (void *)lc;
            return (void *)header + ep->entryoff;
        }
    }
}
```

## Extension Configuration

### Info.plist

```xml
<key>NSExtension</key>
<dict>
    <key>NSExtensionPointIdentifier</key>
    <string>com.apple.services</string>
    <key>NSExtensionPrincipalClass</key>
    <string>HIAHExtensionHandler</string>
    <key>NSExtensionAttributes</key>
    <dict>
        <key>NSExtensionActivationRule</key>
        <dict>
            <key>NSExtensionActivationSupportsFileWithMaxCount</key>
            <integer>1</integer>
        </dict>
    </dict>
</dict>
```

### Entitlements

The extension must have the **same App Group** as the host app to access staged apps:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" 
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.aspauldingcode.HIAHDesktop</string>
    </array>
</dict>
</plist>
```

**Important:** Both the host app (`HIAHDesktop.entitlements`) and extension (`Entitlements.plist`) must have the same App Group identifier.

## Request Format

The host app sends spawn requests via `NSExtensionItem.userInfo`:

```objc
NSDictionary *appInfo = @{
    @"LSServiceMode": @"spawn",
    @"LSExecutablePath": @"/path/to/Guest.app/Guest",
    @"LSEnvironment": @{
        @"HOME": @"/path/to/container",
        @"TMPDIR": @"/path/to/tmp"
    },
    @"LSArguments": @[@"--flag", @"value"]
};

NSExtensionItem *item = [NSExtensionItem new];
item.userInfo = appInfo;

[extension beginExtensionRequestWithInputItems:@[item] completion:...];
```

## Debugging

### Console.app Logs

Extension logs are visible in Console.app with the prefix `🏠`:

```
🏠 ⚡ NSExtensionMain (PID: 12345)
🏠 ✅ XPC decoder configured
🏠 🔧 Calling system NSExtensionMain: 0x...
🏠 📩 Received spawn request from HIAHKernel
🏠 📦 Mode: spawn
🏠 📦 Path: /path/to/app
🏠 ✅ Binary loaded: 0x...
🏠 ✅ Entry point: 0x...
🏠 🚀 Launching guest with 1 args...
```

### Xcode Console

Extension logs don't appear directly in Xcode's console. To view them:

1. Open **Console.app** on your Mac
2. Select your iOS device in the sidebar
3. Filter by process name: `HIAHProcessRunner`
4. Or search for `🏠`

## Limitations

### Code Signing

- Guest apps must be signed, or the device must have CS_DEBUGGED flag (JIT enabled)
- On non-jailbroken devices, this typically requires a development certificate

### Process Isolation

- Guest apps run in the same process as the extension
- They share memory space and can potentially interfere with each other
- No true sandboxing between apps

### UIApplication

- Only one UIApplication instance can exist
- Guest apps that heavily customize UIApplicationDelegate may have issues

### System Frameworks

- Some system frameworks may not work correctly in the guest context
- Frameworks that check bundle identifiers may fail

## Technical Background

HIAHProcessRunner implements patterns common in iOS dynamic loading:

| Technique | Purpose |
|-----------|---------|
| dlopen hooking | Intercept framework loading |
| Visible symbols | Override system functions |
| Mach-O patching | Convert executables to dylibs |
| CFRunLoop sync | Coordinate async callbacks |
| dyld vtable patching | Hook internal dyld functions |

## Future Improvements

1. **JIT-less Mode** – Implement library validation bypass for non-JIT environments.

2. **Bundle Overwriting** – Override `NSBundle.mainBundle` and `CFBundleGetMainBundle` for better guest compatibility.

3. **Path Redirection** – Hook file system calls to redirect guest paths.

4. **Tweak Injection** – Support for loading `.dylib` tweaks into guest apps.

## See Also

- [HIAH Desktop Documentation](./HIAHDesktop.md) – Host application
- [HIAH Kernel Documentation](./HIAHKernel.md) – Process management
- [Virtual Filesystem Documentation](./VirtualFilesystem.md) – Storage & Files.app integration

