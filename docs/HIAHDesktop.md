# HIAHDesktop

The main HIAH application combining SideStore and LiveContainer functionality.

## Overview

HIAHDesktop is a single app that provides:
- **App sideloading** (like SideStore)
- **App execution** (like LiveContainer)
- **JIT enablement** (via minimuxer)
- **Process monitoring** (HIAHTop)

No need to install SideStore or LiveContainer separately.

## Features

### Built-in SideStore Features
- Apple ID authentication with 2FA
- Development certificate management
- 7-day certificate auto-refresh
- Anisette data generation
- App signing (ad-hoc and with certificate)

### Built-in LiveContainer Features
- Install IPAs to virtual /Applications
- Run apps in sandboxed extension
- Virtual filesystem per app
- DYLD bypass for unsigned code (when JIT enabled)

### JIT Enablement
- em_proxy for VPN loopback
- minimuxer for debugserver connection
- Works with LocalDevVPN from App Store

## How It Works

### Installing an App

```
1. User selects .ipa file
2. HIAHDesktop extracts to /Applications/<app>
3. Signs the app (ZSign ad-hoc or certificate)
4. App appears in launcher
```

### Running an App

```
1. User taps app icon
2. HIAHKernel spawns ProcessRunner extension
3. Extension patches and loads app binary
4. App runs in extension sandbox
5. Output routed back to HIAHDesktop
```

### JIT Mode (for unsigned apps)

```
1. User enables "JIT Mode"
2. em_proxy starts UDP listener
3. User connects LocalDevVPN
4. minimuxer attaches to debugserver
5. CS_DEBUGGED flag set on extension
6. DYLD bypass activates
7. Unsigned code can now load
```

## UI Structure

```
HIAHDesktop
├── Home (App Launcher)
│   ├── Installed Apps grid
│   ├── Install IPA button
│   └── App context menus
├── Process Monitor (HIAHTop)
│   ├── Running processes list
│   ├── CPU/Memory stats
│   └── Kill process
├── Settings
│   ├── Apple ID (HIAHLoginWindow)
│   ├── Certificates
│   ├── JIT Settings
│   └── About
└── Terminal (optional)
    └── HIAHTerminal integration
```

## Requirements

- iOS 14.0+
- App Groups entitlement
- For JIT: LocalDevVPN (App Store)

## Configuration

### App Group

All components share data via App Group:

```
group.com.yourteam.HIAH/
├── Applications/     # Installed apps
├── Documents/        # App data
├── tmp/              # Temporary files
└── Preferences/      # Settings
```

### Bundle IDs

| Target | Bundle ID |
|--------|-----------|
| HIAHDesktop | com.yourteam.HIAHDesktop |
| ProcessRunner | com.yourteam.HIAHDesktop.ProcessRunner |

## SideStore/LiveContainer Comparison

| Feature | SideStore | LiveContainer | HIAHDesktop |
|---------|-----------|---------------|-------------|
| Install IPAs | ✓ | ✓ | ✓ |
| Run unsigned apps | - | ✓ (JIT) | ✓ (JIT) |
| Apple ID auth | ✓ | - | ✓ |
| Certificate management | ✓ | - | ✓ |
| JIT enablement | ✓ | ✓ | ✓ |
| Single app | - | - | ✓ |

## Implementation Notes

### Why Rewrite?

1. **Single app** - No need to sideload multiple apps
2. **Unified experience** - One UI for all features
3. **Better integration** - Components communicate directly
4. **Cleaner codebase** - Purpose-built for HIAH

### Clean-Room Implementations

- **em_proxy** - UDP loopback proxy (Rust, MIT)
- **minimuxer** - Lockdown muxer (Rust, MIT)

These are not forks of SideStore code. They implement the same protocols from documentation.

### AltSign Integration

HIAHLoginWindow uses AltSign patterns for Apple auth. This makes HIAHLoginWindow AGPLv3, but the rest of HIAHDesktop remains MIT.

## Building

```bash
# Generate project
nix run .#xcgen --impure

# Build for simulator
xcodebuild -project HIAHDesktop.xcodeproj \
  -scheme HIAHDesktop \
  -sdk iphonesimulator \
  CODE_SIGNING_ALLOWED=NO

# Build for device (requires signing)
open HIAHDesktop.xcodeproj
# Configure signing in Xcode, then build
```

## License

- HIAHDesktop app: MIT
- HIAHLoginWindow component: AGPLv3
