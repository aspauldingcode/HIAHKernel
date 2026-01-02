# HIAH Kernel Integration Guide

This guide details how to integrate the **HIAHKernel** library into your own iOS application (e.g., Wawona).

## Prerequisites

- **Host App**: An iOS application project (Xcode or Nix-based).
- **App Group**: You must have a valid App Group entitlement (e.g., `group.com.yourname.yourapp`) provisioned in your Apple Developer account.
- **SideStore/AltStore**: Required for JIT enablement on non-jailbroken devices.

---

## Step 1: Add the Dependency

### Option A: Nix Flake (Recommended)

Add `HIAHKernel` to your `flake.nix`:

```nix
{
  inputs.hiahkernel.url = "github:aspauldingcode/HIAHKernel";
  
  outputs = { self, nixpkgs, hiahkernel, ... }: {
    # In your build configuration:
    buildInputs = [ 
      hiahkernel.packages.${system}.hiahkernel-library 
    ];
  };
}
```

### Option B: Git Submodule

```bash
git submodule add https://github.com/aspauldingcode/HIAHKernel.git dependencies/HIAHKernel
```

Then drag `dependencies/HIAHKernel/HIAHKernel.xcodeproj` into your main Xcode project and add `HIAHKernel.framework` to your app's **Frameworks, Libraries, and Embedded Content**.

---

## Step 2: Create the Process Runner Extension

The kernel relies on a helper App Extension (`.appex`) to execute processes in a separate address space. **You must build this extension as part of your app.**

1.  **New Target**: In Xcode, goes to File > New > Target...
2.  **Template**: Choose **Intents Extension** (or any simple extension type, we will override it).
3.  **Product Name**: `HIAHProcessRunner`.
4.  **Language**: Objective-C.

### Configure the Extension

1.  **Delete Default Files**: Remove `IntentHandler.m/h` and `Info.plist` (we'll replace it).
2.  **Add Source**: Add `HIAHKernel/src/extension/HIAHProcessRunner.m` to the extension target.
    *   *Note: You may need to add `src/HIAHKernel/Core/Hooks/` files if they are not included in the library binary relative paths.*
3.  **Link Frameworks**:
    *   `HIAHKernel.framework`
    *   `Foundation.framework`
    *   `UIKit.framework`

### Update Info.plist

Replace the extension's `Info.plist` content with:

```xml
<key>NSExtension</key>
<dict>
    <key>NSExtensionPointIdentifier</key>
    <string>com.apple.intents-service</string>
    <key>NSExtensionPrincipalClass</key>
    <string>HIAHProcessRunner</string>
</dict>
```

---

## Step 3: Configure Entitlements (Critical)

Both your **Host App** and the **Process Runner Extension** must share the **same App Group**.

1.  Create/Edit `.entitlements` for **Host App**:
    ```xml
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.yourcompany.yourapp</string>
    </array>
    ```

2.  Create/Edit `.entitlements` for **Extension**:
    ```xml
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.yourcompany.yourapp</string>
    </array>
    ```

---

## Step 4: Initialize the Kernel

In your Host App's `AppDelegate` or main view controller:

```objc
#import <HIAHKernel/HIAHKernel.h>

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    
    // 1. Configure
    HIAHKernel *kernel = [HIAHKernel sharedKernel];
    kernel.appGroupIdentifier = @"group.com.yourcompany.yourapp"; // MUST match Entitlements
    kernel.extensionIdentifier = @"com.yourcompany.yourapp.HIAHProcessRunner"; // Bundle ID of extension
    
    // 2. Setup Output Handling
    kernel.onOutput = ^(pid_t pid, NSString *output) {
        NSLog(@"[Guest %d] %@", pid, output);
    };
    
    return YES;
}
```

## Step 5: Spawn a Process

To run a binary (e.g., `python.dylib` or a standalone executable):

```objc
[kernel spawnVirtualProcessWithPath:@"/path/to/binary"
                          arguments:@[@"arg1"]
                        environment:@{@"TERM": @"xterm"}
                         completion:^(pid_t pid, NSError *error) {
    if (error) {
        NSLog(@"Error: %@", error);
    } else {
        NSLog(@"Spawned PID: %d", pid);
    }
}];
```

