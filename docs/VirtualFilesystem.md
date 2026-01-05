# Virtual Filesystem

Sandboxed filesystem for guest applications.

## Overview

HIAH provides a virtual filesystem that:
- Isolates guest apps from host
- Persists across launches
- Lives in App Group container
- Mimics iOS directory structure

## Structure

```
App Group Container/
└── HIAH/
    ├── Applications/           # Installed guest apps
    │   ├── MyApp.app/
    │   └── AnotherApp.app/
    ├── var/
    │   └── mobile/
    │       ├── Documents/      # User documents
    │       ├── Library/        # App data
    │       └── Containers/     # Per-app containers
    └── tmp/                    # Temporary files
```

## Path Mapping

Guest processes see virtual paths mapped to real locations:

| Virtual Path | Real Path |
|--------------|-----------|
| `/Applications` | `<AppGroup>/HIAH/Applications` |
| `/var/mobile` | `<AppGroup>/HIAH/var/mobile` |
| `/tmp` | `<AppGroup>/HIAH/tmp` |
| `/private/var` | `<AppGroup>/HIAH/var` |

## Implementation

### Path Translation

```objc
// In HIAHKernel
NSString *realPath = [HIAHFilesystem realPathForVirtualPath:@"/Applications/MyApp.app"];
// Returns: /path/to/AppGroup/HIAH/Applications/MyApp.app
```

### File Operations

Hooked syscalls translate paths automatically:
- `open()`, `stat()`, `access()`
- `mkdir()`, `rmdir()`, `unlink()`
- `readdir()`, `opendir()`

### Sandbox Enforcement

Guest apps cannot access:
- Host app's container
- Other App Group data
- System directories outside virtual fs

## Per-App Containers

Each guest app gets its own container:

```
var/mobile/Containers/Data/Application/<UUID>/
├── Documents/
├── Library/
│   ├── Caches/
│   └── Preferences/
└── tmp/
```

UUID generated on first launch, persisted in preferences.

## Usage

### Installing Apps

```objc
// Copy app to virtual /Applications
NSString *destPath = [HIAHFilesystem applicationPathForBundle:@"MyApp.app"];
[fileManager copyItemAtPath:ipaContents toPath:destPath error:nil];
```

### Reading App Data

```objc
// Get app's Documents directory
NSString *docsPath = [HIAHFilesystem documentsPathForApp:@"com.example.myapp"];
```

### Cleaning Up

```objc
// Remove app and its data
[HIAHFilesystem removeApp:@"com.example.myapp"];
```

## Files

```
src/HIAHKernel/Core/
├── HIAHFilesystem.h
├── HIAHFilesystem.m
└── Hooks/
    └── HIAHFileHooks.m    # Path translation hooks
```

## Limitations

- No symlinks outside virtual fs
- File permissions simplified (no real UID/GID)
- Some system paths return static data
- No /dev device access
