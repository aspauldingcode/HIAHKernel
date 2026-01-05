#!/usr/bin/env bash
# ============================================================================
# test-all.sh - HIAH Kernel Test Runner (Nix-Powered)
# ============================================================================
#
# This script is a thin wrapper around Nix commands.
# All testing is done via Nix for reproducibility.
#
# Usage:
#   ./scripts/ci/test-all.sh              # Run all tests via Nix
#   ./scripts/ci/test-all.sh --check      # Run nix flake check
#   ./scripts/ci/test-all.sh --rust       # Run Rust tests only
#   ./scripts/ci/test-all.sh --xcode      # Run Xcode tests only
#
# Copyright (c) 2025 Alex Spaulding
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/../.."
cd "$ROOT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
BOLD='\033[1m'

# Check for Nix
if ! command -v nix &> /dev/null; then
    echo -e "${RED}Error: Nix is not installed${NC}"
    echo ""
    echo "Install Nix:"
    echo "  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install"
    echo ""
    echo "Or:"
    echo "  sh <(curl -L https://nixos.org/nix/install)"
    exit 1
fi

echo ""
echo -e "${BOLD}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║        HIAH Kernel - Test Runner (Nix-Powered)                 ║${NC}"
echo -e "${BOLD}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

case "${1:-all}" in
    --check)
        echo -e "${BLUE}Running:${NC} nix flake check"
        echo "════════════════════════════════════════════════════════════════"
        nix flake check --print-build-logs
        ;;
    
    --rust)
        echo -e "${BLUE}Running:${NC} nix run .#test-rust"
        echo "════════════════════════════════════════════════════════════════"
        nix run .#test-rust
        ;;
    
    --xcode)
        echo -e "${BLUE}Running:${NC} nix run .#test-xcode"
        echo "════════════════════════════════════════════════════════════════"
        nix run .#test-xcode --impure
        ;;
    
    --build)
        echo -e "${BLUE}Running:${NC} Build all packages"
        echo "════════════════════════════════════════════════════════════════"
        echo ""
        echo "Building em_proxy..."
        nix build .#hiah-em-proxy-ios --print-build-logs
        echo ""
        echo "Building minimuxer..."
        nix build .#hiah-minimuxer-ios --print-build-logs
        echo ""
        echo -e "${GREEN}✅ All builds complete${NC}"
        ;;
    
    all|--all)
        echo -e "${BLUE}Running:${NC} nix run .#test-all"
        echo "════════════════════════════════════════════════════════════════"
        nix run .#test-all
        ;;
    
    --help|-h)
        echo "Usage: $0 [option]"
        echo ""
        echo "Options:"
        echo "  (default)  Run all automated tests"
        echo "  --check    Run nix flake check"
        echo "  --rust     Run Rust tests only"
        echo "  --xcode    Run Xcode tests only"
        echo "  --build    Build all packages"
        echo "  --help     Show this help"
        echo ""
        echo "All testing is done via Nix for reproducibility."
        echo ""
        echo "For device tests, run:"
        echo "  ./scripts/device/run-device-tests.sh"
        ;;
    
    *)
        echo -e "${RED}Unknown option: $1${NC}"
        echo "Run '$0 --help' for usage"
        exit 1
        ;;
esac

echo ""
