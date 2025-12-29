#!/bin/bash
# Bundle sample apps and terminal into HIAHDesktop.app/BundledApps

set -e

echo "🚀 Bundle Apps Script Started!"
echo "   PWD: $(pwd)"

# Get the build products directory from Xcode
BUILT_PRODUCTS_DIR="${BUILT_PRODUCTS_DIR:-${CONFIGURATION_BUILD_DIR}}"
SRCROOT="${SRCROOT:-$(dirname "$0")/..}"

echo "   BUILT_PRODUCTS_DIR: ${BUILT_PRODUCTS_DIR}"
echo "   SRCROOT: ${SRCROOT}"

APP_BUNDLE="${BUILT_PRODUCTS_DIR}/HIAHDesktop.app"
BUNDLED_APPS_DIR="${APP_BUNDLE}/BundledApps"

echo ""
echo "📦 Bundling apps into: ${BUNDLED_APPS_DIR}"

# Ensure app bundle exists
if [ ! -d "${APP_BUNDLE}" ]; then
    echo "⚠️  App bundle not found at ${APP_BUNDLE}"
    echo "    This script should run AFTER compilation"
    exit 1
fi

# Create BundledApps directory
mkdir -p "${BUNDLED_APPS_DIR}"
echo "✅ Created BundledApps directory"
echo ""

# Bundle HIAHTop
if [ -d "${SRCROOT}/src/HIAHTop" ]; then
    mkdir -p "${BUNDLED_APPS_DIR}/HIAHTop.app"
    cp "${SRCROOT}/src/HIAHTop/"*.m "${SRCROOT}/src/HIAHTop/"*.h "${BUNDLED_APPS_DIR}/HIAHTop.app/" 2>/dev/null || true
    cp "${SRCROOT}/src/HIAHTop/Info.plist" "${BUNDLED_APPS_DIR}/HIAHTop.app/" 2>/dev/null || true
    echo "✓ Bundled HIAHTop.app"
fi

# Bundle HIAHInstaller
if [ -d "${SRCROOT}/src/HIAHInstaller" ]; then
    mkdir -p "${BUNDLED_APPS_DIR}/HIAHInstaller.app"
    cp "${SRCROOT}/src/HIAHInstaller/"*.m "${SRCROOT}/src/HIAHInstaller/"*.h "${BUNDLED_APPS_DIR}/HIAHInstaller.app/" 2>/dev/null || true
    cp "${SRCROOT}/src/HIAHInstaller/Info.plist" "${BUNDLED_APPS_DIR}/HIAHInstaller.app/" 2>/dev/null || true
    echo "✓ Bundled HIAHInstaller.app"
fi

# Bundle Sample Apps
for app in Calculator Notes Weather Timer Canvas; do
    if [ -d "${SRCROOT}/src/SampleApps/${app}" ]; then
        mkdir -p "${BUNDLED_APPS_DIR}/${app}.app"
        cp "${SRCROOT}/src/SampleApps/${app}/"*.swift "${BUNDLED_APPS_DIR}/${app}.app/" 2>/dev/null || true
        cp "${SRCROOT}/src/SampleApps/${app}/Info.plist" "${BUNDLED_APPS_DIR}/${app}.app/" 2>/dev/null || true
        echo "✓ Bundled ${app}.app"
    fi
done

# Bundle HIAHTerminal
if [ -d "${SRCROOT}/src/HIAHTerminal" ]; then
    mkdir -p "${BUNDLED_APPS_DIR}/HIAHTerminal.app"
    cp "${SRCROOT}/src/HIAHTerminal/"*.swift "${SRCROOT}/src/HIAHTerminal/"*.m "${SRCROOT}/src/HIAHTerminal/"*.h "${BUNDLED_APPS_DIR}/HIAHTerminal.app/" 2>/dev/null || true
    cp "${SRCROOT}/src/HIAHTerminal/Info.plist" "${BUNDLED_APPS_DIR}/HIAHTerminal.app/" 2>/dev/null || true
    echo "✓ Bundled HIAHTerminal.app"
fi

echo ""
echo "✅ Finished bundling apps successfully!"
echo ""

