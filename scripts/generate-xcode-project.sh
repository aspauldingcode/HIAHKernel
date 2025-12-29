#!/bin/bash
# Generate Xcode project from project.yml using XcodeGen
# XcodeGen is provided by Nix flake

set -e

cd "$(dirname "$0")/.."

echo "🔨 Generating Xcode project..."
echo ""

# XcodeGen is provided by Nix environment
xcodegen generate

echo ""
echo "✅ HIAHDesktop.xcodeproj generated!"
echo ""
echo "📂 Project references ../src/ directly (no copies)"
echo "🎯 Single source of truth!"
echo ""
echo "Open: open HIAHDesktop.xcodeproj"
