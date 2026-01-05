# Getting Started with HIAHKernel

## Quick Build

```bash
# Build HIAHDesktop (includes HIAHKernel framework)
nix run .#build

# Build options
nix run .#build -- --release      # Release build
nix run .#build -- --clean        # Clean build
nix run .#build -- --kernel       # Build only HIAHKernel framework
nix run .#build -- --help         # Show options
```

## Build for Device

```bash
# Build for iOS device (requires code signing)
nix run .#build-device

# Options
nix run .#build-device -- --debug   # Debug build
nix run .#build-device -- --clean   # Clean build
```

**Note:** Device builds require Xcode code signing configuration.

## Project Structure

```
HIAHKernel/
├── src/
│   ├── HIAHKernel/           # Core library
│   │   ├── Public/           # Public headers
│   │   └── Core/             # Implementation
│   └── HIAHDesktop/          # Example app
├── project.yml               # XcodeGen project config
├── flake.nix                 # Nix build configuration
└── docs/                     # Documentation
```

## Using HIAHKernel as a Library

See [LIBRARY_USAGE.md](LIBRARY_USAGE.md) for integration instructions.

## Development

```bash
# Enter development shell
nix develop

# Generate Xcode project only (for IDE work)
xcodegen generate

# Open in Xcode
open HIAHDesktop.xcodeproj
```

## Testing

```bash
# Run all tests
nix run .#test-all

# Test library imports
nix run .#test-library
```

## Requirements

- macOS with Xcode 15+
- Nix package manager
- iOS 16.0+ deployment target

## License

HIAHKernel is MIT licensed. See [LICENSE](../LICENSE).
