# HIAHKernel

**iOS Virtual Kernel for multi-process execution on jailed devices.**

HIAHKernel enables iOS apps to spawn and manage multiple processes within their sandbox, combining SideStore and LiveContainer functionality into a single solution.

## Quick Start

```bash
# Enter Nix environment
nix develop

# Generate Xcode project
nix run .#xcgen --impure

# Open in Xcode
open HIAHDesktop.xcodeproj

# Or build from command line
xcodebuild build -scheme HIAHDesktop -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO
```

## Features

- **Virtual Kernel** – Process table, memory management, signal handling
- **NSExtension Isolation** – Guest apps run in separate extension
- **SideStore Features** – Apple ID auth, certificate management, JIT enablement
- **LiveContainer Features** – Run apps in virtual filesystem, DYLD bypass
- **Library API** – Import HIAHKernel into your own projects

## Documentation

| Doc | Description |
|-----|-------------|
| [Getting Started](docs/GETTING_STARTED.md) | Build and run instructions |
| [Architecture](docs/ARCHITECTURE.md) | System design overview |
| [HIAHKernel](docs/HIAHKernel.md) | Core kernel API |
| [HIAHDesktop](docs/HIAHDesktop.md) | Main app features |
| [Library Usage](docs/LIBRARY_USAGE.md) | Using as a library |

## Structure

```
src/                    # Source code
├── HIAHKernel/         # Core library (MIT)
├── HIAHDesktop/        # Main application
├── HIAHLoginWindow/    # Auth/signing (AGPLv3)
├── HIAHTop/            # Process monitor
└── extension/          # ProcessRunner NSExtension
docs/                   # Documentation
nix/                    # Nix derivations
```

## Requirements

- iOS 16.0+
- macOS 14+, Xcode 15+
- Nix package manager

## License

- **HIAHKernel core**: MIT
- **HIAHLoginWindow**: AGPLv3 (AltSign integration)

MIT License – Copyright (c) 2025 Alex Spaulding
