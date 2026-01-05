#!/usr/bin/env bash
# ============================================================================
# run-device-tests.sh - Manual Device Test Runner for HIAH Kernel
# ============================================================================
#
# This script guides you through testing device-only features that cannot
# be automated in CI:
#   - em_proxy <-> LocalDevVPN communication
#   - minimuxer JIT enablement
#   - dyld bypass for unsigned binary loading
#
# PREREQUISITES:
#   1. Mac with Xcode 15+ installed
#   2. Physical iOS device (iPhone/iPad) connected via USB
#   3. LocalDevVPN installed from App Store on the device
#   4. Apple Developer account (free or paid)
#   5. Device paired with this Mac (trust established)
#
# USAGE:
#   ./scripts/device/run-device-tests.sh
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
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; }
warning() { echo -e "${YELLOW}[⚠]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; }
prompt() { echo -e "${CYAN}[?]${NC} $1"; }

# Test results tracking
declare -A TEST_RESULTS
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

record_result() {
    local test_name="$1"
    local result="$2"
    TEST_RESULTS["$test_name"]="$result"
    
    case "$result" in
        "PASS") ((TESTS_PASSED++)) ;;
        "FAIL") ((TESTS_FAILED++)) ;;
        "SKIP") ((TESTS_SKIPPED++)) ;;
    esac
}

# ============================================================================
# Header
# ============================================================================
echo ""
echo -e "${BOLD}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║       HIAH Kernel - Manual Device Test Runner                  ║${NC}"
echo -e "${BOLD}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "This script will guide you through testing device-only features."
echo "Some steps require manual interaction."
echo ""

# ============================================================================
# Step 0: Prerequisites Check
# ============================================================================
echo -e "${BOLD}Step 0: Prerequisites Check${NC}"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

# Check Xcode
if ! command -v xcodebuild &> /dev/null; then
    error "Xcode not found. Please install Xcode 15+."
    exit 1
fi
XCODE_VERSION=$(xcodebuild -version | head -1)
success "Xcode: $XCODE_VERSION"

# Check for connected device
DEVICE_ID=""
if command -v idevice_id &> /dev/null; then
    DEVICE_ID=$(idevice_id -l 2>/dev/null | head -1 || echo "")
elif command -v xcrun &> /dev/null; then
    DEVICE_ID=$(xcrun devicectl list devices 2>/dev/null | grep -oE "[A-F0-9-]{36}" | head -1 || echo "")
fi

if [ -z "$DEVICE_ID" ]; then
    warning "No iOS device detected!"
    echo ""
    echo "Please:"
    echo "  1. Connect your iPhone/iPad via USB"
    echo "  2. Unlock the device"
    echo "  3. Trust this computer if prompted"
    echo ""
    prompt "Press Enter when device is connected, or 's' to skip device tests..."
    read -r response
    if [ "$response" = "s" ]; then
        warning "Skipping device tests"
        record_result "Device Connection" "SKIP"
    else
        DEVICE_ID=$(idevice_id -l 2>/dev/null | head -1 || xcrun devicectl list devices 2>/dev/null | grep -oE "[A-F0-9-]{36}" | head -1 || echo "")
        if [ -z "$DEVICE_ID" ]; then
            error "Still no device detected. Please check connection."
            record_result "Device Connection" "FAIL"
        else
            success "Device connected: $DEVICE_ID"
            record_result "Device Connection" "PASS"
        fi
    fi
else
    success "Device connected: $DEVICE_ID"
    record_result "Device Connection" "PASS"
fi

# Check for LocalDevVPN
echo ""
log "Checking for LocalDevVPN..."
echo ""
echo "LocalDevVPN must be installed from the App Store on your device."
echo "It provides the VPN tunnel that em_proxy uses for communication."
echo ""
prompt "Is LocalDevVPN installed on your device? (y/n/s to skip)"
read -r ldv_response

case "$ldv_response" in
    y|Y)
        success "LocalDevVPN confirmed installed"
        record_result "LocalDevVPN Installed" "PASS"
        ;;
    s|S)
        warning "Skipping LocalDevVPN check"
        record_result "LocalDevVPN Installed" "SKIP"
        ;;
    *)
        warning "LocalDevVPN not installed"
        echo ""
        echo "Please install LocalDevVPN from the App Store:"
        echo "  https://apps.apple.com/app/localdevvpn/id1610890207"
        echo ""
        record_result "LocalDevVPN Installed" "FAIL"
        ;;
esac

echo ""

# ============================================================================
# Step 1: Build HIAH Desktop for Device
# ============================================================================
echo -e "${BOLD}Step 1: Build HIAH Desktop for Device${NC}"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

log "Building HIAH Desktop for device..."

# Generate project if needed
if [ ! -f "HIAHDesktop.xcodeproj/project.pbxproj" ]; then
    log "Generating Xcode project..."
    if command -v nix &> /dev/null; then
        nix run .#xcgen --impure 2>&1 || {
            warning "Nix xcgen failed, trying xcodegen directly"
            xcodegen generate --spec project.yml
        }
    else
        xcodegen generate --spec project.yml
    fi
fi

# Build for device
log "Building for device (this may take a few minutes)..."
echo ""

BUILD_RESULT=0
xcodebuild build \
    -project HIAHDesktop.xcodeproj \
    -scheme HIAHDesktop \
    -destination "generic/platform=iOS" \
    -derivedDataPath build/DerivedData \
    CODE_SIGNING_ALLOWED=NO \
    2>&1 | grep -E "(Build |Compiling|Linking|error:|warning:)" || BUILD_RESULT=$?

if [ $BUILD_RESULT -eq 0 ]; then
    success "Build succeeded"
    record_result "Device Build" "PASS"
else
    error "Build failed"
    record_result "Device Build" "FAIL"
    echo ""
    warning "Cannot continue with device tests without a successful build."
    prompt "Press Enter to continue with manual checks, or Ctrl+C to exit..."
    read -r
fi

echo ""

# ============================================================================
# Step 2: Install on Device
# ============================================================================
echo -e "${BOLD}Step 2: Install on Device${NC}"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

if [ -z "$DEVICE_ID" ]; then
    warning "No device connected - skipping installation"
    record_result "Device Installation" "SKIP"
else
    APP_PATH=$(find build/DerivedData -name "HIAHDesktop.app" -type d 2>/dev/null | head -1)
    
    if [ -n "$APP_PATH" ]; then
        log "Installing HIAH Desktop on device..."
        echo "App path: $APP_PATH"
        echo ""
        
        # Try devicectl first (modern), then fall back to manual
        if xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH" 2>&1; then
            success "Installation succeeded via devicectl"
            record_result "Device Installation" "PASS"
        else
            warning "Automatic installation failed"
            echo ""
            echo "Please install manually:"
            echo "  1. Open Xcode"
            echo "  2. Window → Devices and Simulators"
            echo "  3. Select your device"
            echo "  4. Drag the .app bundle to 'Installed Apps'"
            echo ""
            echo "App location: $APP_PATH"
            echo ""
            prompt "Press Enter when installed, or 's' to skip..."
            read -r install_response
            if [ "$install_response" = "s" ]; then
                record_result "Device Installation" "SKIP"
            else
                record_result "Device Installation" "PASS"
            fi
        fi
    else
        error "App bundle not found"
        record_result "Device Installation" "FAIL"
    fi
fi

echo ""

# ============================================================================
# Step 3: Test em_proxy + LocalDevVPN
# ============================================================================
echo -e "${BOLD}Step 3: Test em_proxy + LocalDevVPN Communication${NC}"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

echo "This test verifies em_proxy can communicate with LocalDevVPN."
echo ""
echo "Manual steps:"
echo "  1. Open HIAH Desktop on your device"
echo "  2. Go to Settings → VPN"
echo "  3. Tap 'Start VPN'"
echo "  4. Open LocalDevVPN and enable the VPN tunnel"
echo "  5. Look for connection status in HIAH Desktop"
echo ""
echo "Expected result:"
echo "  - em_proxy shows 'Started on 127.0.0.1:65399'"
echo "  - LocalDevVPN shows 'Connected'"
echo "  - HIAH Desktop shows VPN status as active"
echo ""
prompt "Did em_proxy + LocalDevVPN connect successfully? (y/n/s to skip)"
read -r vpn_response

case "$vpn_response" in
    y|Y) 
        success "em_proxy + LocalDevVPN test passed"
        record_result "em_proxy + LocalDevVPN" "PASS"
        ;;
    s|S)
        warning "Skipping VPN test"
        record_result "em_proxy + LocalDevVPN" "SKIP"
        ;;
    *)
        error "em_proxy + LocalDevVPN test failed"
        record_result "em_proxy + LocalDevVPN" "FAIL"
        echo ""
        echo "Troubleshooting:"
        echo "  - Ensure LocalDevVPN is running"
        echo "  - Check device logs for em_proxy errors"
        echo "  - Verify network permissions"
        ;;
esac

echo ""

# ============================================================================
# Step 4: Test JIT Enablement via minimuxer
# ============================================================================
echo -e "${BOLD}Step 4: Test JIT Enablement via minimuxer${NC}"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

echo "This test verifies minimuxer can enable JIT by setting CS_DEBUGGED."
echo ""
echo "Prerequisites:"
echo "  - VPN must be active (Step 3)"
echo "  - Pairing file must be available (from previous sync)"
echo ""
echo "Manual steps:"
echo "  1. In HIAH Desktop, go to Settings → JIT"
echo "  2. Tap 'Enable JIT for HIAH Desktop'"
echo "  3. Watch for status update"
echo ""
echo "Expected result:"
echo "  - minimuxer shows 'Ready'"
echo "  - JIT enablement shows 'Success'"
echo "  - App now has CS_DEBUGGED flag set"
echo ""
prompt "Did JIT enablement succeed? (y/n/s to skip)"
read -r jit_response

case "$jit_response" in
    y|Y)
        success "JIT enablement test passed"
        record_result "JIT Enablement" "PASS"
        ;;
    s|S)
        warning "Skipping JIT test"
        record_result "JIT Enablement" "SKIP"
        ;;
    *)
        error "JIT enablement test failed"
        record_result "JIT Enablement" "FAIL"
        echo ""
        echo "Troubleshooting:"
        echo "  - Ensure VPN is active"
        echo "  - Check pairing file exists"
        echo "  - Review minimuxer logs for errors"
        echo "  - Try restarting both VPN and minimuxer"
        ;;
esac

echo ""

# ============================================================================
# Step 5: Test dyld Bypass
# ============================================================================
echo -e "${BOLD}Step 5: Test dyld Bypass (Unsigned Binary Loading)${NC}"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

echo "This test verifies dyld bypass allows loading unsigned binaries."
echo ""
echo "Prerequisites:"
echo "  - JIT must be enabled (Step 4)"
echo "  - CS_DEBUGGED flag must be set"
echo ""
echo "Manual steps:"
echo "  1. Install a test app (unsigned) to HIAH Desktop's Applications folder"
echo "  2. Launch it via the terminal: spawn /Applications/TestApp.app"
echo "  3. Watch for dlopen success/failure"
echo ""
echo "Expected result:"
echo "  - HIAHInitDyldBypass() called successfully"
echo "  - dlopen() succeeds for unsigned binary"
echo "  - App launches and runs"
echo ""
prompt "Did unsigned app load successfully? (y/n/s to skip)"
read -r bypass_response

case "$bypass_response" in
    y|Y)
        success "dyld bypass test passed"
        record_result "dyld Bypass" "PASS"
        ;;
    s|S)
        warning "Skipping dyld bypass test"
        record_result "dyld Bypass" "SKIP"
        ;;
    *)
        error "dyld bypass test failed"
        record_result "dyld Bypass" "FAIL"
        echo ""
        echo "Troubleshooting:"
        echo "  - Verify JIT is enabled (CS_DEBUGGED set)"
        echo "  - Check if binary was patched (MH_EXECUTE → MH_BUNDLE)"
        echo "  - Review ProcessRunner logs"
        echo "  - Try signing the app as fallback"
        ;;
esac

echo ""

# ============================================================================
# Results Summary
# ============================================================================
echo -e "${BOLD}═══════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}                      TEST RESULTS SUMMARY${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════════════${NC}"
echo ""

printf "%-30s %s\n" "Test" "Result"
printf "%-30s %s\n" "────────────────────────────" "────────"
for test in "${!TEST_RESULTS[@]}"; do
    result="${TEST_RESULTS[$test]}"
    case "$result" in
        "PASS") printf "%-30s ${GREEN}%s${NC}\n" "$test" "✓ PASS" ;;
        "FAIL") printf "%-30s ${RED}%s${NC}\n" "$test" "✗ FAIL" ;;
        "SKIP") printf "%-30s ${YELLOW}%s${NC}\n" "$test" "○ SKIP" ;;
    esac
done

echo ""
echo "────────────────────────────────────────"
printf "Passed: ${GREEN}%d${NC}  Failed: ${RED}%d${NC}  Skipped: ${YELLOW}%d${NC}\n" \
    "$TESTS_PASSED" "$TESTS_FAILED" "$TESTS_SKIPPED"
echo ""

# Save results to file
RESULTS_FILE="build/device-test-results-$(date +%Y%m%d-%H%M%S).txt"
mkdir -p build
{
    echo "HIAH Kernel Device Test Results"
    echo "Date: $(date)"
    echo "Device: ${DEVICE_ID:-N/A}"
    echo ""
    for test in "${!TEST_RESULTS[@]}"; do
        echo "$test: ${TEST_RESULTS[$test]}"
    done
    echo ""
    echo "Passed: $TESTS_PASSED  Failed: $TESTS_FAILED  Skipped: $TESTS_SKIPPED"
} > "$RESULTS_FILE"

log "Results saved to: $RESULTS_FILE"

if [ $TESTS_FAILED -gt 0 ]; then
    echo ""
    warning "Some tests failed. See docs/DEVICE_TESTING.md for troubleshooting."
    exit 1
fi

echo ""
success "Device testing complete!"

