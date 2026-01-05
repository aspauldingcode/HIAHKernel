#!/usr/bin/env bash
# ============================================================================
# slim-build.sh - HIAH Kernel Slimming and Optimization Script
# ============================================================================
# This script helps reduce repository and build size by:
#   1. Identifying and removing unnecessary files
#   2. Building minimal vs full variants
#   3. Reporting size comparisons
#   4. Validating that external sources should be Nix-staged
#
# Usage:
#   ./scripts/ci/slim-build.sh analyze     # Analyze what can be removed
#   ./scripts/ci/slim-build.sh clean       # Remove unnecessary files
#   ./scripts/ci/slim-build.sh build       # Build both variants and compare
#   ./scripts/ci/slim-build.sh report      # Generate size report
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

log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ============================================================================
# Analyze Command
# ============================================================================
analyze() {
    log "Analyzing repository for optimization opportunities..."
    echo ""
    
    echo "=============================================="
    echo "1. External Dependency Source Code (should be Nix-staged)"
    echo "=============================================="
    
    # Check for external source trees that should be removed
    EXTERNAL_DIRS=(
        "dependencies/libimobiledevice"
        "dependencies/libimobiledevice-glue"
        "dependencies/libplist"
        "dependencies/libusbmuxd"
        "source2/SideStore"
    )
    
    for dir in "${EXTERNAL_DIRS[@]}"; do
        if [[ -d "$ROOT_DIR/$dir" ]]; then
            SIZE=$(du -sh "$ROOT_DIR/$dir" 2>/dev/null | cut -f1)
            warning "External source found: $dir ($SIZE)"
            echo "       → Should be fetched via Nix, not committed"
        fi
    done
    
    echo ""
    echo "=============================================="
    echo "2. Large Files (>1MB)"
    echo "=============================================="
    
    find "$ROOT_DIR" -type f -size +1M \
        -not -path "*/\.git/*" \
        -not -path "*/.build/*" \
        -not -path "*/build/*" \
        -not -path "*/DerivedData/*" \
        2>/dev/null | while read -r file; do
        SIZE=$(ls -lh "$file" | awk '{print $5}')
        echo "  $SIZE  ${file#$ROOT_DIR/}"
    done
    
    echo ""
    echo "=============================================="
    echo "3. Generated/Cache Files (safe to remove)"
    echo "=============================================="
    
    CACHE_DIRS=(
        ".build"
        "build"
        "DerivedData"
        "*.xcodeproj"
        "Pods"
        "Carthage"
    )
    
    for pattern in "${CACHE_DIRS[@]}"; do
        find "$ROOT_DIR" -name "$pattern" -type d \
            -not -path "*/\.git/*" 2>/dev/null | while read -r dir; do
            SIZE=$(du -sh "$dir" 2>/dev/null | cut -f1)
            echo "  $SIZE  ${dir#$ROOT_DIR/}"
        done
    done
    
    echo ""
    echo "=============================================="
    echo "4. Sample Apps (can be excluded from minimal build)"
    echo "=============================================="
    
    if [[ -d "$ROOT_DIR/src/SampleApps" ]]; then
        SIZE=$(du -sh "$ROOT_DIR/src/SampleApps" | cut -f1)
        echo "  SampleApps: $SIZE"
        ls -la "$ROOT_DIR/src/SampleApps" | grep "^d" | awk '{print "    - "$NF}'
    fi
    
    echo ""
    echo "=============================================="
    echo "5. Repository Size Summary"
    echo "=============================================="
    
    TOTAL_SIZE=$(du -sh "$ROOT_DIR" 2>/dev/null | cut -f1)
    GIT_SIZE=$(du -sh "$ROOT_DIR/.git" 2>/dev/null | cut -f1)
    SRC_SIZE=$(du -sh "$ROOT_DIR/src" 2>/dev/null | cut -f1)
    DEPS_SIZE=$(du -sh "$ROOT_DIR/dependencies" 2>/dev/null | cut -f1)
    
    echo "  Total repository: $TOTAL_SIZE"
    echo "  .git directory:   $GIT_SIZE"
    echo "  src directory:    $SRC_SIZE"
    echo "  dependencies:     $DEPS_SIZE"
    
    echo ""
    success "Analysis complete"
}

# ============================================================================
# Clean Command
# ============================================================================
clean() {
    log "Cleaning unnecessary files..."
    
    # Remove build artifacts
    rm -rf "$ROOT_DIR/build"
    rm -rf "$ROOT_DIR/DerivedData"
    rm -rf "$ROOT_DIR/.build"
    
    # Remove Xcode generated project (can be regenerated)
    rm -rf "$ROOT_DIR/HIAHDesktop.xcodeproj"
    rm -rf "$ROOT_DIR/HIAHDesktop.xcworkspace"
    
    # Remove temporary files
    find "$ROOT_DIR" -name "*.orig" -delete 2>/dev/null || true
    find "$ROOT_DIR" -name ".DS_Store" -delete 2>/dev/null || true
    find "$ROOT_DIR" -name "*.pyc" -delete 2>/dev/null || true
    find "$ROOT_DIR" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
    
    success "Clean complete"
    
    # Show new size
    NEW_SIZE=$(du -sh "$ROOT_DIR" 2>/dev/null | cut -f1)
    echo "Repository size after clean: $NEW_SIZE"
}

# ============================================================================
# Build Command
# ============================================================================
build_variants() {
    log "Building both MINIMAL and FULL variants..."
    
    mkdir -p "$ROOT_DIR/build/variants"
    
    # Check if xcodegen is available
    if ! command -v xcodegen &> /dev/null; then
        error "xcodegen not found. Please install: brew install xcodegen"
        exit 1
    fi
    
    # Generate project
    xcodegen generate --spec project.yml
    
    # Build FULL variant (default)
    log "Building FULL variant..."
    xcodebuild build \
        -project HIAHDesktop.xcodeproj \
        -scheme HIAHDesktop \
        -configuration Release \
        -destination "generic/platform=iOS Simulator" \
        -derivedDataPath build/variants/full/DerivedData \
        CODE_SIGNING_ALLOWED=NO \
        STRIP_INSTALLED_PRODUCT=YES \
        DEPLOYMENT_POSTPROCESSING=YES \
        2>&1 | grep -E "(Build |error:|warning:)" || true
    
    # Copy full build
    FULL_APP=$(find build/variants/full/DerivedData -name "HIAHDesktop.app" -type d | head -1)
    if [[ -n "$FULL_APP" ]]; then
        cp -R "$FULL_APP" "build/variants/HIAHDesktop-full.app"
        success "Full variant built: build/variants/HIAHDesktop-full.app"
    fi
    
    # Build MINIMAL variant (if we had a minimal scheme)
    # For now, we'll simulate this by measuring the core framework
    log "Building MINIMAL variant (HIAHKernel framework only)..."
    xcodebuild build \
        -project HIAHDesktop.xcodeproj \
        -scheme HIAHKernel \
        -configuration Release \
        -destination "generic/platform=iOS Simulator" \
        -derivedDataPath build/variants/minimal/DerivedData \
        CODE_SIGNING_ALLOWED=NO \
        STRIP_INSTALLED_PRODUCT=YES \
        2>&1 | grep -E "(Build |error:|warning:)" || true
    
    MINIMAL_FW=$(find build/variants/minimal/DerivedData -name "HIAHKernel.framework" -type d | head -1)
    if [[ -n "$MINIMAL_FW" ]]; then
        cp -R "$MINIMAL_FW" "build/variants/HIAHKernel-minimal.framework"
        success "Minimal variant built: build/variants/HIAHKernel-minimal.framework"
    fi
    
    success "Build variants complete"
}

# ============================================================================
# Report Command
# ============================================================================
generate_report() {
    log "Generating size report..."
    
    REPORT_FILE="$ROOT_DIR/build/size-report.md"
    mkdir -p "$ROOT_DIR/build"
    
    {
        echo "# HIAHKernel Size Report"
        echo ""
        echo "Generated: $(date)"
        echo ""
        echo "## Build Variants"
        echo ""
        echo "| Variant | Component | Size |"
        echo "|---------|-----------|------|"
        
        # Full variant
        if [[ -d "build/variants/HIAHDesktop-full.app" ]]; then
            FULL_SIZE=$(du -sh "build/variants/HIAHDesktop-full.app" | cut -f1)
            FULL_BINARY=$(ls -lh "build/variants/HIAHDesktop-full.app/HIAHDesktop" 2>/dev/null | awk '{print $5}')
            echo "| Full | App Bundle | $FULL_SIZE |"
            echo "| Full | Main Binary | $FULL_BINARY |"
        fi
        
        # Minimal variant (framework only)
        if [[ -d "build/variants/HIAHKernel-minimal.framework" ]]; then
            MIN_SIZE=$(du -sh "build/variants/HIAHKernel-minimal.framework" | cut -f1)
            echo "| Minimal | Framework | $MIN_SIZE |"
        fi
        
        echo ""
        echo "## Source Code Size"
        echo ""
        echo "| Directory | Size | Description |"
        echo "|-----------|------|-------------|"
        
        # Core components
        [[ -d "src/HIAHKernel" ]] && echo "| src/HIAHKernel | $(du -sh src/HIAHKernel | cut -f1) | Core kernel (MIT) |"
        [[ -d "src/HIAHLoginWindow" ]] && echo "| src/HIAHLoginWindow | $(du -sh src/HIAHLoginWindow | cut -f1) | Login/Auth (AGPL) |"
        [[ -d "src/HIAHDesktop" ]] && echo "| src/HIAHDesktop | $(du -sh src/HIAHDesktop | cut -f1) | Desktop app |"
        [[ -d "src/extension" ]] && echo "| src/extension | $(du -sh src/extension | cut -f1) | ProcessRunner extension |"
        [[ -d "src/SampleApps" ]] && echo "| src/SampleApps | $(du -sh src/SampleApps | cut -f1) | Sample apps (optional) |"
        [[ -d "src/Vendored" ]] && echo "| src/Vendored | $(du -sh src/Vendored | cut -f1) | Vendored deps |"
        
        echo ""
        echo "## Recommendations"
        echo ""
        echo "### For Minimal Builds"
        echo ""
        echo "1. **Exclude SampleApps**: Remove \`src/SampleApps\` from build"
        echo "2. **Exclude HIAHLoginWindow**: If AGPL compliance is a concern"
        echo "3. **Use HIAHKernel framework only**: Link just the core framework"
        echo ""
        echo "### For Repository Size"
        echo ""
        echo "1. **Stage dependencies via Nix**: Don't commit external source code"
        echo "2. **Use Git LFS for binaries**: If prebuilt libs are needed"
        echo "3. **Clean build artifacts**: Run \`./scripts/ci/slim-build.sh clean\`"
        
    } > "$REPORT_FILE"
    
    success "Report generated: $REPORT_FILE"
    cat "$REPORT_FILE"
}

# ============================================================================
# Main
# ============================================================================
case "${1:-help}" in
    analyze)
        analyze
        ;;
    clean)
        clean
        ;;
    build)
        build_variants
        ;;
    report)
        generate_report
        ;;
    all)
        analyze
        echo ""
        clean
        echo ""
        build_variants
        echo ""
        generate_report
        ;;
    help|--help|-h)
        echo "Usage: $0 <command>"
        echo ""
        echo "Commands:"
        echo "  analyze   Analyze repository for optimization opportunities"
        echo "  clean     Remove unnecessary files and build artifacts"
        echo "  build     Build both minimal and full variants"
        echo "  report    Generate size comparison report"
        echo "  all       Run all commands in sequence"
        echo ""
        ;;
    *)
        error "Unknown command: $1"
        echo "Run '$0 help' for usage information"
        exit 1
        ;;
esac
