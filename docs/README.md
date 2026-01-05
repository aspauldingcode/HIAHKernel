# HIAHKernel Documentation

**House in a House** - A virtual kernel enabling multi-process execution on jailed iOS.

## Quick Links

| Document | Description |
|----------|-------------|
| [Getting Started](GETTING_STARTED.md) | Build, install, and run |
| [HIAHKernel](HIAHKernel.md) | Core virtual kernel library |
| [HIAHDesktop](HIAHDesktop.md) | Main app with SideStore/LiveContainer features |
| [Library Usage](LIBRARY_USAGE.md) | Using HIAHKernel in your project |
| [Architecture](ARCHITECTURE.md) | System design and components |

## Components

### Core
- **HIAHKernel** - Virtual kernel library (MIT)
- **HIAHProcessRunner** - NSExtension for guest app execution

### Applications  
- **HIAHDesktop** - Main app combining SideStore + LiveContainer functionality
- **HIAHTop** - Process monitor (like `top` for HIAH)
- **HIAHLoginWindow** - Apple ID auth and signing (AGPLv3)
- **HIAHWindowServer** - UI coordination (planned)
- **HIAHInstaller** - App installation helper

### Infrastructure
- **Virtual Filesystem** - Sandboxed file system for guests
- **DYLD Bypass** - Load unsigned code when JIT enabled
- **ZSign** - Programmatic ad-hoc signing

## License

- **HIAHKernel core**: MIT
- **HIAHLoginWindow**: AGPLv3 (due to AltSign integration)

See [LICENSE](../LICENSE) for details.
