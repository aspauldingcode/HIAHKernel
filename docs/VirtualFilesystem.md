# HIAH Desktop - Virtual Unix Filesystem

## Overview

HIAH Desktop creates a complete Unix filesystem inside the iOS sandbox, enabling execution of Unix tools, shell scripts, and applications in a familiar environment.

## Files.app Integration

**All HIAH Desktop files are visible in the iOS Files app** under:

```
On My iPhone / On My iPad
└── HIAH Desktop/
    ├── Applications/     ← Your installed .ipa apps
    ├── bin/              ← Unix binaries
    ├── usr/              ← User tools
    └── ...
```

This means:
- ✅ **Browse** your installed apps in Files.app
- ✅ **Add/Remove** apps directly from Files.app
- ✅ **Edit** configuration files from Files.app
- ✅ **Sync** via iCloud, Finder, or third-party file managers
- ✅ **Changes are immediately reflected** in HIAH Desktop

## Filesystem Structure

All files are stored in the app's Documents directory:

```
HIAH Desktop/
├── Applications/     # iOS apps (.app bundles from .ipa)
├── bin/             # System binaries (bash, sh, ls, cp, mv, rm, etc.)
├── sbin/            # System admin binaries
├── usr/
│   ├── bin/         # User binaries (unzip, tar, gzip, etc.)
│   ├── lib/         # Shared libraries
│   ├── share/       # Shared data
│   └── local/       # User-installed software
├── lib/             # System libraries
├── etc/             # Configuration files
├── tmp/             # Temporary files
├── var/
│   ├── tmp/         # Variable temp files
│   └── log/         # Log files
├── home/            # User home directory
├── dev/             # Device files (virtual)
└── proc/            # Process info (virtual)
```

## Storage Architecture

HIAH Desktop uses a **hybrid storage model**:

| Location | Purpose | Files.app Visible |
|----------|---------|-------------------|
| `Documents/` | Primary storage for all files | ✅ Yes |
| `App Group/staging/` | Temporary staging for extension | ❌ No (internal) |

### Why Two Locations?

iOS app extensions (like HIAHProcessRunner) run in a **separate sandbox** from the host app. They cannot directly access the host app's Documents folder.

**Solution:** When launching a `.ipa` app:

1. **Install** → App saved to `Documents/Applications/` (visible in Files.app)
2. **Launch** → App copied to `App Group/staging/` (shared container)
3. **Extension loads** → Reads from App Group staging area
4. **User edits in Files.app** → Next launch uses updated files

```
                    ┌──────────────────────┐
                    │      Files.app       │
                    │  (User can browse)   │
                    └──────────┬───────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────┐
│                   Documents Folder                       │
│  ┌─────────────────────────────────────────────────┐    │
│  │  Applications/                                   │    │
│  │  ├── UTM SE.app                                 │    │
│  │  ├── MyApp.app                                  │    │
│  │  └── ...                                        │    │
│  └─────────────────────────────────────────────────┘    │
└─────────────────────┬───────────────────────────────────┘
                      │
                      │ (On Launch: Copy)
                      ▼
┌─────────────────────────────────────────────────────────┐
│            App Group Container (Shared)                  │
│  ┌─────────────────────────────────────────────────┐    │
│  │  staging/                                        │    │
│  │  └── UTM SE.app  (temporary copy)               │    │
│  └─────────────────────────────────────────────────┘    │
└─────────────────────┬───────────────────────────────────┘
                      │
                      │ (Extension reads from here)
                      ▼
┌─────────────────────────────────────────────────────────┐
│              HIAHProcessRunner Extension                 │
│           (Loads and runs the guest app)                │
└─────────────────────────────────────────────────────────┘
```

## Path Resolution

HIAH Kernel and HIAH Desktop automatically resolve virtual Unix paths:

- `/bin/bash` → `<Documents>/bin/bash`
- `/usr/bin/unzip` → `<Documents>/usr/bin/unzip`
- `/etc/config` → `<Documents>/etc/config`
- `/Applications/MyApp.app` → `<Documents>/Applications/MyApp.app`

## App Installation

### Via HIAH Installer (Built-in)

1. Open HIAH Installer from the dock
2. Tap "Browse for .ipa"
3. Select your `.ipa` file
4. App is extracted and installed to `Applications/`

### Via Files.app (Manual)

1. Extract the `.ipa` file (it's a ZIP)
2. Find the `.app` bundle in `Payload/`
3. Copy the `.app` to `HIAH Desktop/Applications/` in Files.app
4. The app will appear in HIAH Desktop's dock

### Via AirDrop / File Sharing

1. Transfer your `.app` bundle to your device
2. Use Files.app to move it to `HIAH Desktop/Applications/`

## Bundled GNU Tools

HIAH Desktop ships with essential GNU utilities (cross-compiled for iOS):

**Core Utilities (coreutils):**
- ls, cp, mv, rm, mkdir, rmdir
- cat, chmod, chown, ln
- pwd, echo, and more

**Shell:**
- bash, sh

**Archiving:**
- unzip

## Building Additional Tools

To add more tools, update `dependencies/gnu-tools-ios.nix` and rebuild:

```nix
# Add new tool
mytool-ios = pkgs.stdenv.mkDerivation {
  name = "mytool-ios";
  # ... build configuration
};
```

## Usage

### For App Developers

Apps installed to HIAH Desktop automatically run in this virtual environment:
- Can execute shell scripts
- Can call Unix utilities
- Can access the virtual filesystem

### For Shell Scripts

```bash
#!/bin/sh
# This script runs in the virtual filesystem
ls /Applications
cd /home
echo "Hello from HIAH Desktop!"
```

### For .ipa Extraction

HIAH Installer uses native ZIP extraction to process `.ipa` files:
1. Picks `.ipa` from Files app
2. Extracts ZIP contents natively
3. Finds `.app` in `Payload/` folder
4. Installs to `/Applications`

## Implementation Details

- **HIAHFilesystem class** – Manages virtual paths and App Group staging
- **Path interception** – HIAH Kernel resolves paths automatically
- **Sandboxed** – All operations stay within app container
- **Files.app integration** – Full filesystem browseable via `UIFileSharingEnabled`
- **App Group** – Shared container (`group.com.aspauldingcode.HIAHDesktop`) for extension access
- **HIAH Kernel** – Manages all process execution

## Troubleshooting

### App not appearing in Files.app

Make sure HIAH Desktop has been launched at least once. The filesystem is initialized on first launch.

### Extension can't load app

Check that App Groups are properly configured in both:
- `HIAHDesktop.entitlements`
- `HIAHProcessRunner.appex` entitlements

Both must have `group.com.aspauldingcode.HIAHDesktop`.

### Changes in Files.app not reflected

Changes take effect on the next app launch. If the app is already running, close and reopen it.

## Roadmap

- [ ] Bundle GNU coreutils binaries
- [ ] Bundle bash/sh
- [ ] Bundle unzip
- [ ] Implement full path redirection in HIAH Kernel
- [ ] Add more utilities (tar, gzip, sed, awk, etc.)
- [ ] Support Wayland apps
- [ ] Support X11 apps
