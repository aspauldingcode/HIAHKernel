# HIAH Desktop – Desktop Environment Documentation

**HIAH Desktop** is a fully-featured desktop environment for iOS, demonstrating the capabilities of HIAH Kernel. It provides a floating window manager, app launcher, and multi-display support – all running inside a sandboxed iOS application.

## Overview

HIAH Desktop showcases what's possible with HIAH Kernel by implementing:

- **Floating Window Manager** – Draggable, resizable windows with minimize/maximize/close
- **App Launcher Dock** – macOS-style dock for launching applications
- **Multi-Display Support** – Automatic support for external displays and CarPlay
- **Sample Applications** – 5 built-in sample apps + HIAH Top process monitor
- **Virtual Process Management** – Each window can represent a separate virtual process

## Running HIAH Desktop

### Via Nix (Recommended)

```bash
# Run on iOS Simulator
nix run .#hiah-desktop

# Build the app
nix build .#hiah-desktop
```

### Via Xcode

1. Open `HIAHKernel.xcodeproj`
2. Select the `HIAHDesktop` scheme
3. Choose your target device/simulator
4. Build and Run (⌘R)

## Features

### Window Manager

Each application runs in its own floating window with:

- **Title Bar** – App name, minimize/maximize/close buttons
- **Dragging** – Move windows by dragging the title bar
- **Resizing** – Drag window edges or corners to resize
- **Minimize** – Collapse to dock
- **Maximize** – Fill screen
- **Roll-up** – Double-click title bar to collapse to title only
- **Tiling** – Three-finger swipe left/right for half-screen tiling

**Window Colors:**
Each app has a distinct title bar color for easy identification.

### App Launcher Dock

The dock provides quick access to applications:

- **Built-in Apps** – HIAHTop, HelloWorld, Calculator, Notes, Weather, Timer, Canvas
- **Minimized Windows** – Collapsed windows appear in the dock
- **Preview Mode** – Dock expands when windows overlap it
- **Tap to Launch** – Single tap to open an app
- **Tap to Restore** – Single tap minimized window to restore

### Keyboard Shortcuts (iPad)

| Shortcut | Action |
|----------|--------|
| ⌃⌥⌘O | Toggle roll-up on frontmost window |

### Multi-Display Support

HIAH Desktop automatically extends to connected displays:

- **External Monitors** – Via USB-C/HDMI/AirPlay
- **CarPlay** – Full desktop experience on car displays
- **Window Transfer** – Drag windows near the notch to transfer between displays
- **Auto-Migration** – Windows automatically move to main display when external disconnects

### CarPlay Integration

When connected to CarPlay:

1. HIAH Desktop extends to the car display
2. Use the touchscreen to interact with windows
3. All apps are available on both displays
4. Windows can be transferred between phone and car

## Included Sample Apps

| App | Description | Features |
|-----|-------------|----------|
| **HIAH Top** | Process Monitor | Real-time process list, CPU/memory stats, process control |
| **HelloWorld** | Demo App | Simple SwiftUI greeting |
| **Calculator** | Calculator | Full calculator with operations |
| **Notes** | Note Taking | Simple note cards |
| **Weather** | Weather Display | Mock weather with SF Symbols |
| **Timer** | Stopwatch | Start/stop timer with animation |
| **Canvas** | Drawing | Color palette and drawing area |

## Architecture

```
HIAH Desktop
├── DesktopViewController
│   ├── Desktop View (gradient background)
│   ├── HIAHAppLauncher (dock)
│   └── HIAHFloatingWindow[] (window instances)
│
├── HIAHKernel
│   └── Process table for virtual PIDs
│
├── HIAHSwiftBridge
│   └── Factory for bundled SwiftUI apps
│
├── Multi-Display
│   ├── Main Screen Desktop
│   ├── External Display Desktop
│   └── CarPlay Desktop
│
├── BundledApps/
│   ├── Calculator.app
│   ├── Notes.app
│   ├── Weather.app
│   ├── Timer.app
│   ├── Canvas.app
│   ├── HIAHTop.app
│   ├── HIAHInstaller.app
│   └── HIAHTerminal.app
│
└── PlugIns/
    └── HIAHProcessRunner.appex
        ├── Loads external .ipa apps
        ├── Patches MH_EXECUTE → MH_DYLIB
        └── Executes guest main()
```

### Key Classes

#### DesktopViewController

The main view controller managing the desktop environment.

```objc
@interface DesktopViewController : UIViewController

// Desktop background view
@property (nonatomic, strong) UIView *desktop;

// App launcher dock
@property (nonatomic, strong) HIAHAppLauncher *dock;

// Kernel instance for process spawning
@property (nonatomic, strong) HIAHKernel *kernel;

// All open windows keyed by windowID
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, HIAHFloatingWindow *> *windows;

// Screen this desktop is displayed on
@property (nonatomic, strong) UIScreen *screen;

@end
```

#### HIAHFloatingWindow

A single floating window containing an app.

```objc
@interface HIAHFloatingWindow : UIView

@property (nonatomic, assign) NSInteger windowID;
@property (nonatomic, copy) NSString *windowTitle;
@property (nonatomic, strong) UIColor *titleBarColor;
@property (nonatomic, assign) BOOL isMaximized;
@property (nonatomic, assign) BOOL isRolledUp;
@property (nonatomic, weak) id<HIAHFloatingWindowDelegate> delegate;

// Set the view controller for window content
- (void)setContentViewController:(UIViewController *)viewController;

// Window actions
- (void)bringToFront;
- (void)minimize;
- (void)maximize;
- (void)restore;
- (void)toggleRollup;
- (void)tileLeft;
- (void)tileRight;

// Capture snapshot for dock preview
- (UIImage *)captureSnapshot;

@end
```

#### HIAHAppLauncher

The dock component for launching apps.

```objc
@interface HIAHAppLauncher : UIView

@property (nonatomic, weak) id<HIAHAppLauncherDelegate> delegate;
@property (nonatomic, readonly) BOOL isInPreviewMode;

// Add minimized window to dock
- (void)addMinimizedWindow:(NSInteger)windowID 
                     title:(NSString *)title 
                  snapshot:(UIImage *)snapshot;

// Remove window from dock
- (void)removeMinimizedWindow:(NSInteger)windowID;

// Check if dock should expand (windows overlapping)
- (BOOL)shouldShowPreviewForWindows:(NSArray<UIView *> *)windows;

// Dock state transitions
- (void)slideUpToPreview;
- (void)slideDownFromPreview;

@end
```

### HIAHFloatingWindowDelegate

```objc
@protocol HIAHFloatingWindowDelegate <NSObject>

// Window lifecycle
- (void)floatingWindowDidClose:(HIAHFloatingWindow *)window;
- (void)floatingWindowDidMinimize:(HIAHFloatingWindow *)window;
- (void)floatingWindowDidBecomeActive:(HIAHFloatingWindow *)window;

// Frame changes
- (void)floatingWindowDidChangeFrame:(HIAHFloatingWindow *)window;
- (void)floatingWindowDidUpdateFrameDuringDrag:(HIAHFloatingWindow *)window;
- (void)floatingWindowDidEndDrag:(HIAHFloatingWindow *)window;

// Multi-display transfer
- (void)floatingWindow:(HIAHFloatingWindow *)window isDraggingNearNotch:(BOOL)nearNotch;

@end
```

### HIAHAppLauncherDelegate

```objc
@protocol HIAHAppLauncherDelegate <NSObject>

// App selection
- (void)appLauncher:(HIAHAppLauncher *)launcher 
       didSelectApp:(NSString *)appName 
           bundleID:(NSString *)bundleID;

// Restore minimized window
- (void)appLauncher:(HIAHAppLauncher *)launcher 
didRequestRestoreWindow:(NSInteger)windowID;

@end
```

## Creating Custom Apps

### Adding an App to HIAH Desktop

1. Create your app's view controller:

```objc
@interface MyCustomAppViewController : UIViewController
@end

@implementation MyCustomAppViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    // Add your UI here
    UILabel *label = [[UILabel alloc] init];
    label.text = @"My Custom App";
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:label];
    
    [NSLayoutConstraint activateConstraints:@[
        [label.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [label.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor]
    ]];
}

@end
```

2. Register in the app launcher:

```objc
// In HIAHAppLauncher's initialization
self.availableApps = @[
    @{@"name": @"MyApp", @"bundleID": @"com.example.myapp", @"icon": @"star.fill"},
    // ... existing apps
];
```

3. Handle app creation in DesktopViewController:

```objc
- (UIViewController *)createAppContentViewController:(NSString *)appName 
                                            bundleID:(NSString *)bundleID {
    if ([appName isEqualToString:@"MyApp"]) {
        return [[MyCustomAppViewController alloc] init];
    }
    // ... existing cases
}
```

### SwiftUI Apps

For SwiftUI apps, wrap in a UIHostingController:

```swift
// MySwiftUIApp.swift
import SwiftUI

struct MyAppView: View {
    var body: some View {
        VStack {
            Text("Hello from SwiftUI!")
                .font(.largeTitle)
        }
    }
}
```

```objc
// In DesktopViewController
#import <SwiftUI/SwiftUI.h>
#import "HIAHDesktop-Swift.h"

- (UIViewController *)createAppContentViewController:(NSString *)appName 
                                            bundleID:(NSString *)bundleID {
    if ([appName isEqualToString:@"SwiftUIApp"]) {
        MyAppView *swiftView = [[MyAppView alloc] init];
        return [[UIHostingController alloc] initWithRootView:swiftView];
    }
}
```

## Multi-Display Architecture

### Screen Management

```objc
@interface AppDelegate : UIResponder <UIApplicationDelegate>

// Windows by screen
@property (strong) NSMutableDictionary<NSValue *, UIWindow *> *windowsByScreen;

// Desktops by screen  
@property (strong) NSMutableDictionary<NSValue *, DesktopViewController *> *desktopsByScreen;

// Track managed screens
@property (strong) NSMutableSet<NSValue *> *managedScreens;

@end
```

### Screen Connection/Disconnection

```objc
// Automatically called when external display connects
- (void)screenDidConnect:(NSNotification *)notification {
    UIScreen *newScreen = notification.object;
    [self setupScreen:newScreen];
}

// Automatically called when external display disconnects
- (void)screenDidDisconnect:(NSNotification *)notification {
    UIScreen *disconnectedScreen = notification.object;
    // Transfer windows to main screen
    // Clean up resources
}
```

### Window Transfer Animation

Windows transfer between displays with a "suck into notch" animation:

1. Window shrinks and moves toward notch
2. Disappears from source display
3. Appears on target display
4. Expands from notch position

## CarPlay Support

### Configuration (Info.plist)

```xml
<key>UIApplicationSceneManifest</key>
<dict>
    <key>UISceneConfigurations</key>
    <dict>
        <key>CPTemplateApplicationSceneSessionRoleApplication</key>
        <array>
            <dict>
                <key>UISceneClassName</key>
                <string>CPTemplateApplicationScene</string>
                <key>UISceneDelegateClassName</key>
                <string>HIAHCarPlaySceneDelegate</string>
            </dict>
        </array>
    </dict>
</dict>

<key>UIApplicationSupportsMultipleScenes</key>
<true/>
```

### Entitlements

```xml
<key>com.apple.developer.carplay-audio</key>
<true/>
<key>com.apple.developer.playable-content</key>
<true/>
```

### CarPlay Controller

```objc
@interface HIAHCarPlayController : NSObject

@property (nonatomic, strong) CPInterfaceController *interfaceController;
@property (nonatomic, strong) CPWindow *carWindow;
@property (nonatomic, weak) DesktopViewController *mainDesktop;

+ (instancetype)sharedController;
- (void)setupCarPlayInterface;

@end
```

## Performance Considerations

### Memory Management

- Windows are view-based, not true processes
- Content views are lazily loaded
- Minimized windows store snapshots, not live views

### Battery Optimization

- Sampling pauses when app backgrounds
- External display rendering stops when disconnected
- CarPlay uses optimized rendering path

### Recommended Limits

| Resource | Recommended Max |
|----------|-----------------|
| Open windows | 10-15 |
| Background processes | 5 |
| External displays | 2 (phone + one external) |

## Customization

### Desktop Background

```objc
- (void)setupDesktop {
    // Custom gradient
    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.colors = @[
        (id)[UIColor colorWithRed:0.2 green:0.1 blue:0.3 alpha:1.0].CGColor,
        (id)[UIColor colorWithRed:0.1 green:0.1 blue:0.2 alpha:1.0].CGColor
    ];
    // ...
}
```

### Window Appearance

```objc
// Custom title bar colors per app
- (UIColor *)titleBarColorForApp:(NSString *)appName {
    NSDictionary *colors = @{
        @"MyApp": [UIColor colorWithRed:0.8 green:0.2 blue:0.4 alpha:0.98],
        // ...
    };
    return colors[appName] ?: [UIColor colorWithWhite:0.15 alpha:0.98];
}
```

### Dock Position

```objc
- (void)setupDock {
    CGFloat dockWidth = MIN(self.view.bounds.size.width - 32, 500);
    CGFloat dockHeight = 320;
    CGFloat dockY = self.view.bounds.size.height - 80 - 20;
    // ...
}
```

## Requirements

- iOS 16.0+
- Xcode 15.0+
- HIAH Kernel library
- CarPlay capability (for car displays)

## Known Limitations

1. **True Process Isolation**: Apps share the host process memory space
2. **Code Signing**: Apps must be signed with the host app's provisioning
3. **System Integration**: No access to iOS home screen or Control Center
4. **App Store**: CarPlay apps require Apple approval

## External App Loading

HIAH Desktop can run external `.ipa` apps (not just bundled SwiftUI apps) via the **HIAHProcessRunner** extension.

### Storage & Files.app Integration

All apps are stored in the **Documents folder**, which is **visible in iOS Files.app**:

```
On My iPhone → HIAH Desktop → Applications/
├── UTM SE.app
├── MyApp.app
└── ...
```

**Benefits:**
- Browse and manage apps from Files.app
- Add apps by copying `.app` bundles directly
- Remove apps by deleting from Files.app
- Sync via iCloud, Finder, or third-party tools

### Installation Flow

When you install an `.ipa` via HIAH Installer:

1. **Extract** – The `.ipa` (ZIP file) is extracted natively
2. **Install** – The `.app` bundle is copied to `Documents/Applications/`
3. **Available** – App appears in HIAH Desktop's dock

### Launch Flow

When you launch an installed app:

1. **Stage** – App is copied to App Group container (for extension access)
2. **Patch** – Binary is patched from `MH_EXECUTE` to `MH_DYLIB`
3. **Load** – HIAHProcessRunner extension loads the guest via `dlopen`
4. **Execute** – Guest app's `main()` is called
5. **Display** – Guest app's UI appears in a floating window

See [HIAHProcessRunner Documentation](./HIAHProcessRunner.md) for technical details.
See [Virtual Filesystem Documentation](./VirtualFilesystem.md) for storage architecture.

### Supported External Apps

- Apps signed with your development certificate
- Apps on devices with JIT enabled (CS_DEBUGGED flag)
- Most UIKit and SwiftUI apps

### Known Issues with External Apps

- Some apps may crash if they heavily customize UIApplicationDelegate
- Apps checking bundle identifiers may fail
- System frameworks that require specific entitlements won't work

## See Also

- [HIAH Kernel Documentation](./HIAHKernel.md) – Core Library
- [HIAH Top Documentation](./HIAHTop.md) – Process Manager
- [HIAHProcessRunner Documentation](./HIAHProcessRunner.md) – Guest App Extension
- [Virtual Filesystem Documentation](./VirtualFilesystem.md) – Storage & Files.app Integration
- [Sample Apps](../src/SampleApps/) – Source code for included apps

