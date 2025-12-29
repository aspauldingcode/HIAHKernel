#!/bin/bash
# Build and deploy HIAH Desktop to iPhone
# Uses Nix build system (single source of truth)

set -e

cd "$(dirname "$0")/.."

echo "🔨 Building and deploying HIAH Desktop..."
echo ""
echo "📂 Source: ./src/ (single source of truth)"
echo "🔧 Build: Nix"
echo "📱 Deploy: iPhone"
echo ""

# Use Nix device deployment (it handles everything correctly!)
nix run '.#hiah-desktop-device' --impure "$@"
