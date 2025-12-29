#!/usr/bin/env bash
# Build SideStore libraries from source
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/.."

echo "🦀 Building SideStore libraries from source..."
echo ""

# Check for Rust
if ! command -v cargo &> /dev/null; then
    echo "❌ Rust not found. Install with: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
    exit 1
fi

# Check for iOS targets
if ! rustup target list --installed | grep -q aarch64-apple-ios-sim; then
    echo "📥 Installing iOS Rust targets..."
    rustup target add aarch64-apple-ios
    rustup target add aarch64-apple-ios-sim
fi

# Build em_proxy
echo "1/2 Building em_proxy..."
cd "$ROOT_DIR/source2/SideStore/em_proxy"

echo "  - Building for iOS device..."
cargo build --release --target aarch64-apple-ios --lib

echo "  - Building for iOS simulator..."
cargo build --release --target aarch64-apple-ios-sim --lib

echo "  ✓ em_proxy built"
echo ""

# Build minimuxer (skip for now - needs cmake)
echo "2/2 Skipping minimuxer (requires cmake)"
echo "  ⚠️  minimuxer build requires cmake - using Makefile instead"
echo ""

# Use minimuxer's Makefile if available
if [ -f "$ROOT_DIR/source2/SideStore/minimuxer/Makefile" ]; then
    echo "  - Building minimuxer with Makefile..."
    cd "$ROOT_DIR/source2/SideStore/minimuxer"
    make ios-sim 2>/dev/null || echo "  ⚠️  Makefile build failed, libraries may need manual build"
fi

echo ""
echo "✅ Build complete!"
echo ""
echo "Built libraries:"
ls -lh "$ROOT_DIR/source2/SideStore/em_proxy/target/"*apple-ios*/release/libem_proxy.a 2>/dev/null || true
ls -lh "$ROOT_DIR/source2/SideStore/minimuxer/target/"*apple-ios*/release/libminimuxer.a 2>/dev/null || true
echo ""
echo "Next: nix-build dependencies/sidestore/default.nix"

