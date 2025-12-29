{ lib, pkgs }:

let
  # Script to find Xcode
  findXcodeScript = pkgs.writeShellScriptBin "find-xcode" ''
    #!/usr/bin/env bash
    set -euo pipefail

    # Method 1: Use xcode-select to find the active developer directory
    if command -v xcode-select >/dev/null 2>&1; then
        XCODE_DEVELOPER_DIR=$(xcode-select -p 2>/dev/null || true)
        if [ -n "$XCODE_DEVELOPER_DIR" ]; then
            # Extract Xcode.app path from developer directory
            # /Applications/Xcode.app/Contents/Developer -> /Applications/Xcode.app
            XCODE_APP="''${XCODE_DEVELOPER_DIR%/Contents/Developer}"
            if [ -d "$XCODE_APP" ] && [[ "$XCODE_APP" == *.app ]]; then
                echo "$XCODE_APP"
                exit 0
            fi
        fi
    fi

    # Method 2: Check common locations
    for XCODE_APP in /Applications/Xcode.app /Applications/Xcode-beta.app; do
        if [ -d "$XCODE_APP" ]; then
            echo "$XCODE_APP"
            exit 0
        fi
    done

    # Method 3: Search /Applications for Xcode*.app
    if [ -d /Applications ]; then
        XCODE_APP=$(find /Applications -maxdepth 1 -name "Xcode*.app" -type d 2>/dev/null | head -1)
        if [ -n "$XCODE_APP" ]; then
            echo "$XCODE_APP"
            exit 0
        fi
    fi

    # Not found
    echo "ERROR: Xcode not found. Please install Xcode from the App Store or set XCODE_APP environment variable." >&2
    exit 1
  '';

  # Get Xcode path (evaluated at build time)
  getXcodePath = pkgs.writeShellScriptBin "get-xcode-path" ''
    if [ -n "''${XCODE_APP:-}" ]; then
        echo "$XCODE_APP"
    else
        ${findXcodeScript}/bin/find-xcode
    fi
  '';
in
{
  inherit findXcodeScript getXcodePath;

  # Wrapper that sets up Xcode environment for iOS Simulator
  xcodeSimulatorWrapper = pkgs.writeShellScriptBin "xcode-simulator-wrapper" ''
    #!/usr/bin/env bash
    set -euo pipefail

    XCODE_APP=$(${findXcodeScript}/bin/find-xcode)
    export XCODE_APP

    # Set developer directory
    export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"

    # Add Xcode tools to PATH
    export PATH="$DEVELOPER_DIR/usr/bin:$PATH"

    # Set SDK paths for iOS Simulator
    export SDKROOT="$DEVELOPER_DIR/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk"

    # Execute the command passed as arguments
    exec "$@"
  '';

  # Wrapper that sets up Xcode environment for iOS Device
  xcodeDeviceWrapper = pkgs.writeShellScriptBin "xcode-device-wrapper" ''
    #!/usr/bin/env bash
    set -euo pipefail

    XCODE_APP=$(${findXcodeScript}/bin/find-xcode)
    export XCODE_APP

    # Set developer directory
    export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"

    # Add Xcode tools to PATH
    export PATH="$DEVELOPER_DIR/usr/bin:$PATH"

    # Set SDK paths for iOS Device
    export SDKROOT="$DEVELOPER_DIR/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"

    # Execute the command passed as arguments
    exec "$@"
  '';
}

