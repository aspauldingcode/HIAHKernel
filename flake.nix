{
  description = "HIAH - House in a House (Virtual Kernel, Process Manager, Desktop Environment for iOS)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay.url = "github:oxalica/rust-overlay";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, flake-utils, rust-overlay }:
    flake-utils.lib.eachSystem [ "aarch64-darwin" ] (system:
      let
        overlays = [ rust-overlay.overlays.default ];
        pkgs = import nixpkgs {
          inherit system overlays;
          config.allowUnfree = true;  # Allow Xcode (unfree)
        };
        
        # Use Xcode 26.1 Apple Silicon (required!)
        xcode = pkgs.darwin.xcode_26_1_Apple_silicon;
        
        # Enable pkgsCross.iphone64 with Xcode 26.1
        pkgsCross = import nixpkgs {
          inherit system;
          crossSystem = {
            config = "aarch64-apple-ios";
            useiOSPrebuilt = true;
          };
          overlays = [(self: super: {
            inherit xcode;
          })];
        };
        
        xcodeUtils = import ./dependencies/utils/xcode-wrapper.nix { lib = pkgs.lib; inherit pkgs; };
        
        sidestore = import ./dependencies/sidestore { 
          inherit pkgs xcode pkgsCross; 
          lib = pkgs.lib; 
          inherit rustToolchain; 
        };
        
        # OpenSSL must be defined before zsign (zsign depends on it)
        openssl = import ./dependencies/openssl.nix {
          inherit pkgs;
          lib = pkgs.lib;
          buildPackages = pkgs.buildPackages;
          inherit xcode;
        };
        
        zsign = import ./dependencies/zsign.nix {
          inherit pkgs;
          lib = pkgs.lib;
          inherit xcode;
          fetchFromGitHub = pkgs.fetchFromGitHub;
          sidestore = sidestore;
          openssl = openssl;
        };
        
        libplist = import ./dependencies/libplist.nix {
          inherit pkgs;
          lib = pkgs.lib;
          buildPackages = pkgs.buildPackages;
          inherit xcode;
          fetchFromGitHub = pkgs.fetchFromGitHub;
        };
        
        libimobiledevice-glue = import ./dependencies/libimobiledevice-glue.nix {
          inherit pkgs;
          lib = pkgs.lib;
          buildPackages = pkgs.buildPackages;
          inherit xcode;
          fetchFromGitHub = pkgs.fetchFromGitHub;
          libplist = libplist;
        };
        
        libusbmuxd = import ./dependencies/libusbmuxd.nix {
          inherit pkgs;
          lib = pkgs.lib;
          buildPackages = pkgs.buildPackages;
          inherit xcode;
          fetchFromGitHub = pkgs.fetchFromGitHub;
          libplist = libplist;
          libimobiledevice-glue = libimobiledevice-glue;
        };
        
        libimobiledevice-standalone = import ./dependencies/libimobiledevice.nix {
          inherit pkgs;
          lib = pkgs.lib;
          buildPackages = pkgs.buildPackages;
          inherit xcode;
          fetchFromGitHub = pkgs.fetchFromGitHub;
          libplist = libplist;
          libimobiledevice-glue = libimobiledevice-glue;
          libusbmuxd = libusbmuxd;
        };
        
        rustToolchain = pkgs.rust-bin.stable.latest.default.override {
          targets = [ "aarch64-apple-ios" "aarch64-apple-ios-sim" "x86_64-apple-ios" ];
        };
        
        buildModule = import ./dependencies/build.nix {
          lib = pkgs.lib;
          inherit pkgs;
          stdenv = pkgs.stdenv;
          buildPackages = pkgs.buildPackages;
        };
        hiahkernelSrc = pkgs.lib.cleanSourceWith {
          src = ./.;
          filter = path: type:
            let base = builtins.baseNameOf path;
            in !(base == ".git" || base == "build" || base == "result" || base == ".direnv" || pkgs.lib.hasPrefix "result" base);
        };
        hiahkernelBuildModule = import ./dependencies/hiahkernel.nix {
          lib = pkgs.lib;
          inherit pkgs buildModule hiahkernelSrc xcode pkgsCross sidestore;
        };

        # Wrapper: hiah-kernel (library test)
        hiahKernelWrapper = pkgs.writeShellScriptBin "hiah-kernel" ''
          set -euo pipefail
          XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode || true)
          [ -z "$XCODE_APP" ] && echo "Error: Xcode not found" && exit 1
          DEVICE_ID=$(xcrun simctl list devices available | grep -i "iphone" | head -1 | grep -oE '[A-F0-9-]{36}' | head -1 || true)
          [ -z "$DEVICE_ID" ] && echo "Error: No iOS simulator" && exit 1
          [ ! -f "${hiahkernelBuildModule.ios}/lib/libHIAHKernel.dylib" ] && echo "Error: Library not found" && exit 1
          echo "hiah-kernel library OK"
          echo "  ${hiahkernelBuildModule.ios}/lib/libHIAHKernel.a"
          echo "  ${hiahkernelBuildModule.ios}/lib/libHIAHKernel.dylib"
          echo "  ${hiahkernelBuildModule.ios}/include/HIAHKernel/"
        '';

        # Wrapper: hiah-top (process manager)
        hiahTopWrapper = pkgs.writeShellScriptBin "hiah-top" ''
          set -euo pipefail
          APP="${hiahkernelBuildModule.iosTopApp}/Applications/HIAHTop.app"
          DEVICE_ID=$(xcrun simctl list devices available | grep -i "iphone" | head -1 | grep -oE '[A-F0-9-]{36}' | head -1)
          [ -z "$DEVICE_ID" ] && echo "Error: No iOS simulator" && exit 1
          TEMP="/tmp/HIAHTop.app"
          rm -rf "$TEMP" && cp -r "$APP" "$TEMP" && chmod -R +w "$TEMP"
          xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true
          open -a Simulator
          xcrun simctl install "$DEVICE_ID" "$TEMP"
          echo "Running hiah-top..."
          xcrun simctl launch --console-pty "$DEVICE_ID" com.aspauldingcode.HIAHTop "$@"
          rm -rf "$TEMP"
        '';

        # Wrapper: hiah-desktop (desktop environment)
        hiahDesktopWrapper = pkgs.writeShellScriptBin "hiah-desktop" ''
          set -euo pipefail
          APP="${hiahkernelBuildModule.iosDesktopApp}/Applications/HIAHDesktop.app"
          HIAHTOP="${hiahkernelBuildModule.iosTopApp}/Applications/HIAHTop.app"
          INSTALLER="${hiahkernelBuildModule.iosInstallerApp}/HIAHInstaller.app"
          DEVICE_ID=$(xcrun simctl list devices available | grep -i "iphone" | head -1 | grep -oE '[A-F0-9-]{36}' | head -1)
          [ -z "$DEVICE_ID" ] && echo "Error: No iOS simulator" && exit 1
          
          # Install HIAH Desktop
          TEMP="/tmp/HIAHDesktop.app"
          rm -rf "$TEMP" && cp -r "$APP" "$TEMP" && chmod -R +w "$TEMP"
          xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true
          open -a Simulator
          xcrun simctl install "$DEVICE_ID" "$TEMP"
          rm -rf "$TEMP"
          
          # Get container path and install apps
          CONTAINER=$(xcrun simctl get_app_container "$DEVICE_ID" com.aspauldingcode.HIAH-Desktop data 2>/dev/null)
          if [ -n "$CONTAINER" ]; then
            APPS_DIR="$CONTAINER/Documents/Applications"
            mkdir -p "$APPS_DIR"
            
            # Force remove existing apps
            chmod -R +w "$APPS_DIR/HIAHTop.app" 2>/dev/null || true
            rm -rf "$APPS_DIR/HIAHTop.app" 2>/dev/null || true
            chmod -R +w "$APPS_DIR/HIAHInstaller.app" 2>/dev/null || true
            rm -rf "$APPS_DIR/HIAHInstaller.app" 2>/dev/null || true
            
            # Install HIAHTop
            echo "Installing HIAHTop..."
            cp -R "$HIAHTOP" "$APPS_DIR/"
            chmod -R +w "$APPS_DIR/HIAHTop.app"
            chmod +x "$APPS_DIR/HIAHTop.app/HIAHTop"
            
            # Install HIAH Installer
            echo "Installing HIAH Installer..."
            cp -R "$INSTALLER" "$APPS_DIR/"
            chmod -R +w "$APPS_DIR/HIAHInstaller.app"
            chmod +x "$APPS_DIR/HIAHInstaller.app/HIAHInstaller"
            
            echo "✓ HIAHTop and HIAH Installer installed"
          fi
          
          echo "Running hiah-desktop..."
          xcrun simctl launch --console-pty "$DEVICE_ID" com.aspauldingcode.HIAH-Desktop "$@"
        '';
        
        # Wrapper: hiah-desktop-device (FULLY AUTOMATED iPhone deployment)
        hiahDesktopDeviceWrapper = pkgs.writeShellScriptBin "hiah-desktop-device" ''
          set -euo pipefail
          
          echo "🍎 HIAH Desktop → iPhone (AUTOMATED)"
          echo "====================================="
          echo ""
          
          # Use Nix Xcode 26.1
          XCODE_APP="${xcode}"
          DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
          CURRENT_XCODE=$(xcode-select -p 2>/dev/null || echo "")
          
          if [ "$CURRENT_XCODE" != "$DEVELOPER_DIR" ]; then
            echo "❌ xcode-select not set to Nix Xcode"
            echo ""
            echo "Run this once:"
            echo "  sudo xcode-select --switch $DEVELOPER_DIR"
            echo ""
            echo "Then retry: nix run .#hiah-desktop-device --impure"
            exit 1
          fi
          
          echo "✓ Using Nix Xcode 26.1"
          export DEVELOPER_DIR
          export PATH="$DEVELOPER_DIR/usr/bin:$PATH"
          echo ""
          
          # Check for iPhone
          DEVICE_ID=$(${pkgs.libimobiledevice}/bin/idevice_id -l 2>&1 | head -1 || echo "")
          
          if [ -z "$DEVICE_ID" ]; then
            echo "❌ No iPhone detected!"
            echo "   • Connect via USB"
            echo "   • Unlock device"
            echo "   • Trust this computer"
            exit 1
          fi
          
          echo "✓ iPhone: $DEVICE_ID"
          echo ""
          
          # Auto-generate provisioning profile using Nix Xcode
          PROFILE=$(ls -t ~/Library/MobileDevice/Provisioning\ Profiles/*.mobileprovision 2>/dev/null | head -1 || echo "")
          
          if [ -z "$PROFILE" ]; then
            echo "🔧 Generating profile with Xcode 26.1..."
            
            # Use Xcode's provisioning tools
            $DEVELOPER_DIR/usr/bin/xcodebuild \
              -downloadPlatform iOS \
              -allowProvisioningUpdates 2>&1 > /dev/null || {
              echo ""
              echo "Sign in to Xcode (open now): ⌘, → Accounts → + → [Your Apple ID]"
              echo "Then retry!"
              exit 1
            }
            
            PROFILE=$(ls -t ~/Library/MobileDevice/Provisioning\ Profiles/*.mobileprovision 2>/dev/null | head -1 || echo "")
            [ -n "$PROFILE" ] && echo "✅ Profile generated!" || exit 1
          else
            echo "✓ Profile: $(basename "$PROFILE")"
          fi
          echo ""
          
          # Prepare app bundle
          APP="${hiahkernelBuildModule.iosDesktopDevice}/Applications/HIAHDesktop.app"
          TEMP_DIR=$(mktemp -d)
          TEMP_APP="$TEMP_DIR/HIAHDesktop.app"
          cp -r "$APP" "$TEMP_APP"
          chmod -R +w "$TEMP_APP"
          
          # Embed profile and use source entitlements
          if [ -n "$PROFILE" ]; then
            cp "$PROFILE" "$TEMP_APP/embedded.mobileprovision"
            
            # Use entitlements from source (simpler and more reliable)
            ENTITLEMENTS_PLIST="$TEMP_DIR/entitlements.plist"
            cp "${hiahkernelBuildModule.iosDesktopDevice}/Applications/HIAHDesktop.app/HIAHDesktop.entitlements" "$ENTITLEMENTS_PLIST" 2>/dev/null || {
              # Minimal fallback
              cat > "$ENTITLEMENTS_PLIST" << 'ENTEOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>get-task-allow</key>
	<true/>
	<key>com.apple.security.application-groups</key>
	<array>
		<string>group.com.aspauldingcode.HIAH</string>
	</array>
</dict>
</plist>
ENTEOF
            }
          fi
          
          echo "🔐 Signing with Xcode 26.1 tools..."
          
          # Auto-detect signing identity from keychain
          SIGN_ID=$(security find-identity -v -p codesigning | grep "Apple Development" | head -1 | grep -oE '[A-F0-9]{40}')
          if [ -z "$SIGN_ID" ]; then
            echo "❌ No Apple Development certificate found"
            echo "   Sign in to Xcode: Preferences → Accounts"
            exit 1
          fi
          echo "📝 Using signing identity: $SIGN_ID"
          
          # Use system codesign
          CODESIGN="codesign"
          
          # Sign frameworks first (bottom-up)
          if [ -d "$TEMP_APP/Frameworks" ]; then
            for framework in "$TEMP_APP/Frameworks"/*.dylib; do
              [ -f "$framework" ] && $CODESIGN --force --sign "$SIGN_ID" --timestamp=none "$framework"
            done
          fi
          
          # Sign app extension
          if [ -d "$TEMP_APP/PlugIns/HIAHProcessRunner.appex" ]; then
            $CODESIGN --force --sign "$SIGN_ID" \
              --entitlements "$ENTITLEMENTS_PLIST" \
              --timestamp=none \
              "$TEMP_APP/PlugIns/HIAHProcessRunner.appex"
          fi
          
          # Sign main executable and app bundle
          $CODESIGN --force --sign "$SIGN_ID" \
            --entitlements "$ENTITLEMENTS_PLIST" \
            --timestamp=none \
            "$TEMP_APP/HIAHDesktop"
          
          $CODESIGN --force --sign "$SIGN_ID" \
            --entitlements "$ENTITLEMENTS_PLIST" \
            --timestamp=none \
            "$TEMP_APP"
          
          echo "🚀 Installing on iPhone..."
          echo ""
          
          # Use Xcode's devicectl (modern replacement for ios-deploy)
          # xcrun is a system tool, but respects DEVELOPER_DIR
          if /usr/bin/xcrun devicectl device install app --device "$DEVICE_ID" "$TEMP_APP" 2>&1; then
            rm -rf "$TEMP_DIR"
            echo ""
            echo "✅ HIAH Desktop installed on iPhone!"
            echo ""
            echo "📱 Launch from home screen to test .ipa extraction!"
          else
            echo ""
            echo "⚠️  Installation via devicectl failed, trying legacy method..."
            echo ""
            
            # Fallback: Try using simpler install method
            echo "Attempting alternative installation method..."
            
            # Try using Xcode's command line tools directly
            if /usr/bin/instruments -w "$DEVICE_ID" 2>&1 | grep -q "known to Xcode"; then
              # Device is known to Xcode, but devicectl failed
              # This usually means permission issues or the app bundle has issues
              echo ""
              echo "Device is paired but installation failed."
              echo "This may be due to:"
              echo "  - App bundle structure issues"
              echo "  - Code signing problems"
              echo "  - Device storage full"
              INSTALL_RESULT=1
            else
              echo "Device not paired with Xcode. Pair it first:"
              echo "  1. Open Xcode → Window → Devices and Simulators"
              echo "  2. Select your iPhone and click 'Trust'"
              INSTALL_RESULT=1
            fi
            
            rm -rf "$TEMP_DIR"
            
            if [ $INSTALL_RESULT -ne 0 ]; then
              echo ""
              if [ -z "$PROFILE" ]; then
                echo "❌ Failed - No provisioning profile"
                echo ""
                echo "Create one ONCE in Xcode:"
                echo "  1. New iOS App → Bundle ID: com.aspauldingcode.HIAHDesktop"
                echo "  2. Run on your iPhone once (generates profile)"
                echo "  3. Retry: nix run .#hiah-desktop-device"
              else
                echo "❌ Deployment failed"
                echo ""  
                echo "Manual install: Drag app to device in Xcode Devices window"
                echo "App location: $APP"
              fi
              exit 1
            fi
          fi
        '';

      in {
        packages = {
          default = hiahkernelBuildModule.ios;
          hiah-kernel = hiahkernelBuildModule.ios;
          hiah-top = hiahkernelBuildModule.iosTopApp;
          hiah-desktop = hiahkernelBuildModule.iosDesktopApp;
          hiah-installer = hiahkernelBuildModule.iosInstallerApp;
          hiah-desktop-device = hiahkernelBuildModule.iosDesktopDevice;
          
          # SideStore components
          em-proxy = sidestore.em-proxy;
          minimuxer = sidestore.minimuxer;  # macOS (for testing)
          minimuxer-ios = sidestore.minimuxer-ios;  # iOS Device
          minimuxer-ios-sim = sidestore.minimuxer-ios-sim;  # iOS Simulator
          roxas = sidestore.roxas;
          altsign = sidestore.altsign;
          sidestore-all = sidestore.all;
          
          # libimobiledevice for iOS (built from SideStore forks)
          libimobiledevice-ios-sim = sidestore.libimobiledevice.ios-sim;
          libimobiledevice-ios = sidestore.libimobiledevice.ios;
          
          # Individual libimobiledevice stack packages (fetched from GitHub)
          libplist-ios-sim = libplist.ios-sim;
          libplist-ios = libplist.ios;
          libimobiledevice-glue-ios-sim = libimobiledevice-glue.ios-sim;
          libimobiledevice-glue-ios = libimobiledevice-glue.ios;
          libusbmuxd-ios-sim = libusbmuxd.ios-sim;
          libusbmuxd-ios = libusbmuxd.ios;
          libimobiledevice-standalone-ios-sim = libimobiledevice-standalone.ios-sim;
          libimobiledevice-standalone-ios = libimobiledevice-standalone.ios;
          
          # OpenSSL and zsign packages
          openssl-ios-sim = openssl.ios-sim;
          openssl-ios = openssl.ios;
          zsign-ios-sim = zsign.ios-sim;
          zsign-ios = zsign.ios;
        };

        apps = {
          default = { type = "app"; program = "${hiahDesktopWrapper}/bin/hiah-desktop"; };
          hiah-kernel = { type = "app"; program = "${hiahKernelWrapper}/bin/hiah-kernel"; };
          hiah-top = { type = "app"; program = "${hiahTopWrapper}/bin/hiah-top"; };
          hiah-desktop = { type = "app"; program = "${hiahDesktopWrapper}/bin/hiah-desktop"; };
          hiah-desktop-device = { type = "app"; program = "${hiahDesktopDeviceWrapper}/bin/hiah-desktop-device"; };
          
          # XcodeGen wrapper - regenerate Xcode project at root
          # Make zsign and openssl build dependencies so they're built before the script runs
          xcgenScript = pkgs.writeShellScript "xcgen" ''
            set -eu pipefail
            
            # Get libimobiledevice stack packages (now using standalone packages)
            LIBPLIST_IOS_SIM="${libplist.ios-sim}"
            LIBPLIST_IOS="${libplist.ios}"
            LIBIMOBILEDEVICE_GLUE_IOS_SIM="${libimobiledevice-glue.ios-sim}"
            LIBIMOBILEDEVICE_GLUE_IOS="${libimobiledevice-glue.ios}"
            LIBUSBMUXD_IOS_SIM="${libusbmuxd.ios-sim}"
            LIBUSBMUXD_IOS="${libusbmuxd.ios}"
            LIBIMOBILEDEVICE_IOS_SIM="${libimobiledevice-standalone.ios-sim}"
            LIBIMOBILEDEVICE_IOS="${libimobiledevice-standalone.ios}"
            
            # Get zsign and openssl packages (built as dependencies)
            ZSIGN_IOS_SIM="${toString zsign.ios-sim}"
            ZSIGN_IOS="${toString zsign.ios}"
            OPENSSL_IOS_SIM="${toString openssl.ios-sim}"
            OPENSSL_IOS="${toString openssl.ios}"
              
              # Create directories for staged build artifacts (not source code)
              mkdir -p dependencies/sidestore/lib dependencies/sidestore/include
              
              # Copy Swift bridge files from Nix-built packages
              # These are build artifacts, not source code - they come from Nix builds
              if [ -d "${sidestore.all}/include" ]; then
                echo "  → Copying Swift bridge files from Nix-built sidestore.all..."
                cp ${sidestore.all}/include/*.swift dependencies/sidestore/include/ 2>/dev/null || true
                cp ${sidestore.all}/include/*.h dependencies/sidestore/include/ 2>/dev/null || true
              else
                echo "  ⚠️  sidestore.all/include not found - bridge files may be missing"
                echo "     Run 'nix build .#sidestore-all' to build SideStore components"
              fi
              
              # Note: em_proxy and minimuxer libraries should be prebuilt and in dependencies/sidestore/lib/
              # They were built with SideStore's build system and copied manually.
              # The Nix builds for these are complex due to iOS cross-compilation requirements.
              
              echo "📦 Staging Swift packages (AltSign, Roxas) from Nix..."
              
              # Stage Swift packages to dependencies/swift-packages/ for XcodeGen
              echo "📦 Staging Swift packages (AltSign, Roxas)..."
              mkdir -p dependencies/swift-packages
              
              # Remove existing symlinks/directories if they exist (make writable first if from Nix store)
              chmod -R +w dependencies/swift-packages/AltSign 2>/dev/null || true
              rm -rf dependencies/swift-packages/AltSign 2>/dev/null || true
              chmod -R +w dependencies/swift-packages/Roxas 2>/dev/null || true
              rm -rf dependencies/swift-packages/Roxas 2>/dev/null || true
              
              # Stage AltSign package
              if [ -d "${sidestore.altsign}/AltSign" ]; then
                echo "  → AltSign: ${sidestore.altsign}/AltSign"
                cp -r ${sidestore.altsign}/AltSign dependencies/swift-packages/AltSign
              else
                echo "  ⚠️  AltSign not found at ${sidestore.altsign}/AltSign"
                echo "     Checking alternative location..."
                if [ -d "${sidestore.altsign}" ]; then
                  cp -r ${sidestore.altsign} dependencies/swift-packages/AltSign
                else
                  echo "  ❌ AltSign package not found!"
                  exit 1
                fi
              fi
              
              # Make copied files writable FIRST (they come from read-only Nix store)
              echo "  🔓 Making AltSign package writable..."
              chmod -R u+w dependencies/swift-packages/AltSign 2>/dev/null || true
              
              # Remove .xcodeproj files and .swiftpm directories that confuse Xcode (they're not needed for SPM)
              echo "  🧹 Cleaning up AltSign package..."
              rm -rf dependencies/swift-packages/AltSign/Dependencies/OpenSSL/OpenSSL.xcodeproj 2>/dev/null || true
              rm -rf dependencies/swift-packages/AltSign/Dependencies/OpenSSL/Integration-Examples 2>/dev/null || true
              # Remove any .xcodeproj files in the package root
              find dependencies/swift-packages/AltSign -name "*.xcodeproj" -type d -exec rm -rf {} + 2>/dev/null || true
              # Remove .swiftpm directories (Xcode will regenerate these)
              rm -rf dependencies/swift-packages/AltSign/.swiftpm 2>/dev/null || true
              # Remove any workspace files
              find dependencies/swift-packages/AltSign -name "*.xcworkspace" -type d -exec rm -rf {} + 2>/dev/null || true
              
              # Fix OpenSSL header search path in AltSign's Package.swift (uncomment and fix paths)
              echo "  🔧 Fixing OpenSSL header paths in AltSign Package.swift..."
              python3 << 'PYEOF'
import re

try:
    with open('dependencies/swift-packages/AltSign/Package.swift', 'r') as f:
        content = f.read()

    # Fix all commented OpenSSL paths
    content = content.replace(
        '//                .headerSearchPath("../OpenSSL/ios/include"),',
        '                .headerSearchPath("../OpenSSL/iphonesimulator/include"),'
    )
    content = content.replace(
        '//                .headerSearchPath("../../Dependencies/OpenSSL/ios/include"),',
        '                .headerSearchPath("../../Dependencies/OpenSSL/iphonesimulator/include"),'
    )
    content = content.replace(
        '//                .headerSearchPath("Dependencies/OpenSSL/ios/include"),',
        '                .headerSearchPath("Dependencies/OpenSSL/iphonesimulator/include"),'
    )

    with open('dependencies/swift-packages/AltSign/Package.swift', 'w') as f:
        f.write(content)
    print("  ✅ Fixed OpenSSL paths")
except Exception as e:
    print(f"  ⚠️  Error: {e}")
PYEOF
              
              # Also need to handle the case where code includes <openssl/err.h> but headers are in OpenSSL/ (capital)
              # Create symlink from openssl -> OpenSSL for case-insensitive access
              if [ -d "dependencies/swift-packages/AltSign/Dependencies/OpenSSL/iphonesimulator/include/OpenSSL" ] && [ ! -e "dependencies/swift-packages/AltSign/Dependencies/OpenSSL/iphonesimulator/include/openssl" ]; then
                (cd dependencies/swift-packages/AltSign/Dependencies/OpenSSL/iphonesimulator/include && ln -s OpenSSL openssl) 2>/dev/null || true
              fi
              
              # Stage Roxas package
              if [ -d "${sidestore.roxas}/Roxas" ]; then
                echo "  → Roxas: ${sidestore.roxas}/Roxas"
                cp -r ${sidestore.roxas}/Roxas dependencies/swift-packages/Roxas
              else
                echo "  ⚠️  Roxas not found at ${sidestore.roxas}/Roxas"
                echo "     Checking alternative location..."
                if [ -d "${sidestore.roxas}" ]; then
                  cp -r ${sidestore.roxas} dependencies/swift-packages/Roxas
                else
                  echo "  ❌ Roxas package not found!"
                  exit 1
                fi
              fi
              
              # Make copied directories writable FIRST (they come from read-only Nix store)
              echo "  🔓 Making packages writable..."
              chmod -R u+w dependencies/swift-packages/AltSign dependencies/swift-packages/Roxas 2>/dev/null || true
              
              # Remove .xcodeproj, .xcworkspace, and .swiftpm files that confuse Xcode (they're not needed for SPM)
              echo "  🧹 Cleaning up package directories..."
              find dependencies/swift-packages/AltSign -name "*.xcodeproj" -type d -exec rm -rf {} + 2>/dev/null || true
              find dependencies/swift-packages/AltSign -name "*.xcworkspace" -type d -exec rm -rf {} + 2>/dev/null || true
              find dependencies/swift-packages/Roxas -name "*.xcodeproj" -type d -exec rm -rf {} + 2>/dev/null || true
              find dependencies/swift-packages/Roxas -name "*.xcworkspace" -type d -exec rm -rf {} + 2>/dev/null || true
              # Remove .swiftpm directories (Xcode will regenerate these correctly when resolving packages)
              rm -rf dependencies/swift-packages/AltSign/.swiftpm 2>/dev/null || true
              rm -rf dependencies/swift-packages/Roxas/.swiftpm 2>/dev/null || true
              # Remove DerivedData and .build artifacts
              find dependencies/swift-packages -name "DerivedData" -type d -exec rm -rf {} + 2>/dev/null || true
              find dependencies/swift-packages -name ".build" -type d -exec rm -rf {} + 2>/dev/null || true
              rm -rf dependencies/swift-packages/AltSign/Dependencies/OpenSSL/Integration-Examples 2>/dev/null || true
              
              # Remove code signature from OpenSSL.xcframework (it's not valid)
              echo "  🔓 Removing invalid code signature from OpenSSL.xcframework..."
              rm -rf dependencies/swift-packages/AltSign/Dependencies/OpenSSL/Frameworks/OpenSSL.xcframework/_CodeSignature 2>/dev/null || true
              
              # Create .xcodeignore files to prevent Xcode from trying to load these as projects
              echo "  📝 Creating .xcodeignore files..."
              cat > dependencies/swift-packages/AltSign/.xcodeignore << 'IGNEOF'
*.xcodeproj
*.xcworkspace
Tests/
.github/
.gitmodules
IGNEOF
              cat > dependencies/swift-packages/Roxas/.xcodeignore << 'IGNEOF'
*.xcodeproj
*.xcworkspace
Tests/
.github/
IGNEOF
              
              # Create symlink so #import <AltSign/AltSign.h> resolves correctly
              # The bridging header uses <AltSign/AltSign.h> but AltSign.h is at include/AltSign.h
              # We need include/AltSign/AltSign.h -> ../AltSign.h
              echo "  🔗 Creating AltSign header symlink for bridging header..."
              if [ -d "dependencies/swift-packages/AltSign/AltSign/include/AltSign" ] && [ ! -e "dependencies/swift-packages/AltSign/AltSign/include/AltSign/AltSign.h" ]; then
                ln -sf "../AltSign.h" "dependencies/swift-packages/AltSign/AltSign/include/AltSign/AltSign.h"
                echo "  ✅ Created AltSign.h symlink"
              fi
              
              # Fix OpenSSL header search path in AltSign's Package.swift (uncomment and fix paths)
              # Also add OpenSSL to AltSign-Static targets so it links properly
              echo "  🔧 Fixing OpenSSL header paths in AltSign Package.swift..."
              python3 << 'PYEOF'
import re

try:
    with open('dependencies/swift-packages/AltSign/Package.swift', 'r') as f:
        content = f.read()

    # Fix all commented OpenSSL paths
    content = content.replace(
        '//                .headerSearchPath("../OpenSSL/ios/include"),',
        '                .headerSearchPath("../OpenSSL/iphonesimulator/include"),'
    )
    content = content.replace(
        '//                .headerSearchPath("../../Dependencies/OpenSSL/ios/include"),',
        '                .headerSearchPath("../../Dependencies/OpenSSL/iphonesimulator/include"),'
    )
    content = content.replace(
        '//                .headerSearchPath("Dependencies/OpenSSL/ios/include"),',
        '                .headerSearchPath("Dependencies/OpenSSL/iphonesimulator/include"),'
    )
    
    # Add OpenSSL to AltSign-Static targets list so it links properly
    content = content.replace(
        'targets: ["AltSign", "CAltSign", "CoreCrypto", "CCoreCrypto", "ldid", "ldid-core"]',
        'targets: ["AltSign", "CAltSign", "CoreCrypto", "CCoreCrypto", "ldid", "ldid-core", "OpenSSL"]'
    )

    with open('dependencies/swift-packages/AltSign/Package.swift', 'w') as f:
        f.write(content)
    print("  ✅ Fixed OpenSSL paths and added OpenSSL to AltSign-Static")
except Exception as e:
    print(f"  ⚠️  Error fixing OpenSSL paths: {e}")
PYEOF
              
              # Also need to handle the case where code includes <openssl/err.h> but headers are in OpenSSL/ (capital)
              # Create symlink from openssl -> OpenSSL for case-insensitive access
              if [ -d "dependencies/swift-packages/AltSign/Dependencies/OpenSSL/iphonesimulator/include/OpenSSL" ] && [ ! -e "dependencies/swift-packages/AltSign/Dependencies/OpenSSL/iphonesimulator/include/openssl" ]; then
                (cd dependencies/swift-packages/AltSign/Dependencies/OpenSSL/iphonesimulator/include && ln -s OpenSSL openssl) 2>/dev/null || true
              fi
              
              # Restructure Roxas to SPM layout
              # Put ALL headers in include/Roxas/ subdirectory (not at root of include/)
              # This is the correct SPM layout for <Roxas/Header.h> style imports
              echo "  📦 Restructuring Roxas to SPM layout..."
              mkdir -p dependencies/swift-packages/Roxas/Sources/Roxas/include/Roxas
              # Move headers to include/Roxas/ and implementation files to Sources/Roxas/
              find dependencies/swift-packages/Roxas -maxdepth 1 -type f -name "*.h" -exec mv {} dependencies/swift-packages/Roxas/Sources/Roxas/include/Roxas/ \;
              find dependencies/swift-packages/Roxas -maxdepth 1 -type f \( -name "*.m" -o -name "*.xib" -o -name "*.pch" \) -exec mv {} dependencies/swift-packages/Roxas/Sources/Roxas/ \;
              
              # CRITICAL: Convert umbrella header imports from <Roxas/Header.h> to "Header.h"
              # During module compilation, the umbrella header can't use module-style imports
              # because the module doesn't exist yet. External consumers use @import Roxas.
              echo "  🔧 Fixing Roxas.h umbrella header imports..."
              if [ -f "dependencies/swift-packages/Roxas/Sources/Roxas/include/Roxas/Roxas.h" ]; then
                python3 << 'PYEOF'
import re
with open('dependencies/swift-packages/Roxas/Sources/Roxas/include/Roxas/Roxas.h', 'r') as f:
    content = f.read()
# Convert <Roxas/Header.h> to "Header.h" (all headers are in same directory)
content = re.sub(r'#import <Roxas/([^>]+)>', r'#import "\1"', content)
with open('dependencies/swift-packages/Roxas/Sources/Roxas/include/Roxas/Roxas.h', 'w') as f:
    f.write(content)
print("  ✅ Converted umbrella header to quote imports")
PYEOF
              fi
              
              # Fix missing RSTDefines.h includes in files that use ELog
              echo "  🔧 Fixing missing RSTDefines.h includes..."
              # Add RSTDefines.h to files that use ELog but don't include it
              python3 << 'PYEOF'
import re
import os

files_to_fix = [
    ('dependencies/swift-packages/Roxas/Sources/Roxas/NSFileManager+URLs.m', 'NSFileManager+URLs.h', 'RSTDefines.h'),
    ('dependencies/swift-packages/Roxas/Sources/Roxas/RSTFetchedResultsDataSource.m', 'RSTCellContentDataSource_Subclasses.h', 'RSTDefines.h'),
    ('dependencies/swift-packages/Roxas/Sources/Roxas/RSTPersistentContainer.m', 'RSTError.h', 'RSTDefines.h'),
]

for filepath, after_import, add_import in files_to_fix:
    if not os.path.exists(filepath):
        continue
    try:
        with open(filepath, 'r') as f:
            content = f.read()
        
        if add_import in content:
            continue
        
        # Find the line with the import to add after
        lines = content.split('\n')
        new_lines = []
        added = False
        for i, line in enumerate(lines):
            new_lines.append(line)
            if not added and after_import in line and '#import' in line:
                # Add the import on the next line
                new_lines.append(f'#import "{add_import}"')
                added = True
        
        if added:
            with open(filepath, 'w') as f:
                f.write('\n'.join(new_lines))
            print(f"  ✅ Fixed {os.path.basename(filepath)}")
    except Exception as e:
        print(f"  ⚠️  Error fixing {filepath}: {e}")
PYEOF
              
              # Fix <Roxas/HeaderName.h> includes in public headers (change to "HeaderName.h" for same-directory includes)
              echo "  🔧 Fixing module-style includes in public headers..."
              # RSTPlaceholderView.h uses <Roxas/RSTNibView.h> but they're in the same directory
              python3 << 'PYEOF'
import re
import os
import glob

# Fix all headers that use <Roxas/...> imports - they should use "" since they're in same directory
for header_file in glob.glob('dependencies/swift-packages/Roxas/Sources/Roxas/include/Roxas/*.h'):
    try:
        with open(header_file, 'r') as f:
            content = f.read()
        # Convert <Roxas/Header.h> to "Header.h"
        new_content = re.sub(r'#import <Roxas/([^>]+)>', r'#import "\1"', content)
        if new_content != content:
            with open(header_file, 'w') as f:
                f.write(new_content)
    except Exception as e:
        pass
print("  ✅ Fixed module-style includes in headers")
PYEOF
              
              # Fix headers that use RST_EXTERN but don't include RSTDefines.h
              echo "  🔧 Fixing missing RSTDefines.h in headers using RST_EXTERN..."
              python3 << 'PYEOF'
import re
import os

headers_to_fix = [
    'dependencies/swift-packages/Roxas/Sources/Roxas/include/Roxas/RSTCellContentDataSource.h',
    'dependencies/swift-packages/Roxas/Sources/Roxas/include/Roxas/RSTHelperFile.h',
    'dependencies/swift-packages/Roxas/Sources/Roxas/include/Roxas/RSTNavigationController.h',
    'dependencies/swift-packages/Roxas/Sources/Roxas/include/Roxas/RSTToastView.h',
    'dependencies/swift-packages/Roxas/Sources/Roxas/include/Roxas/UIImage+Manipulation.h',
    'dependencies/swift-packages/Roxas/Sources/Roxas/include/Roxas/UISpringTimingParameters+Conveniences.h',
]

for header_path in headers_to_fix:
    if not os.path.exists(header_path):
        continue
    try:
        with open(header_path, 'r') as f:
            content = f.read()
        
        if 'RSTDefines.h' in content:
            continue
        
        if 'RST_EXTERN' not in content:
            continue
        
        # Find the first @import or #import line and add RSTDefines.h after it
        lines = content.split('\n')
        new_lines = []
        added = False
        for i, line in enumerate(lines):
            new_lines.append(line)
            if not added and ('@import' in line or '#import' in line) and 'RSTDefines' not in line:
                # Add RSTDefines.h import after the first import
                new_lines.append('#import "RSTDefines.h"')
                added = True
        
        if added:
            with open(header_path, 'w') as f:
                f.write('\n'.join(new_lines))
    except Exception as e:
        pass
PYEOF
              
              # Create Package.swift for Roxas (Roxas is CocoaPods, converting to SPM)
              echo "  📝 Creating Package.swift for Roxas..."
              cat > dependencies/swift-packages/Roxas/Package.swift << 'PKGEOF'
// swift-tools-version:5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import Foundation
import PackageDescription

let package = Package(
    name: "Roxas",
    platforms: [
        .iOS(.v14),
        .macOS(.v11),
    ],
    products: [
        .library(
            name: "Roxas",
            targets: ["Roxas"]
        ),
    ],
    targets: [
        .target(
            name: "Roxas",
            path: "Sources/Roxas",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("."),
                .headerSearchPath("include"),
                .headerSearchPath("include/Roxas"),
            ],
            linkerSettings: [
                .linkedFramework("UIKit", .when(platforms: [.iOS])),
                .linkedFramework("Foundation"),
                .linkedFramework("CoreData"),
            ]
        ),
    ]
)
PKGEOF
              echo "  ✅ Created Package.swift for Roxas with SPM layout"
              
              echo "✅ Swift packages staged to dependencies/swift-packages/"
              echo ""
              
              # Stage OpenSSL from Nix (for zsign)
              echo "📦 Staging OpenSSL from Nix..."
              mkdir -p dependencies/openssl/{lib,lib-ios,include}
              
              # Use OPENSSL_IOS_SIM and OPENSSL_IOS from script environment
              if [ -n "$OPENSSL_IOS_SIM" ] && [ -d "$OPENSSL_IOS_SIM/lib" ]; then
                echo "  → OpenSSL iOS Simulator: $OPENSSL_IOS_SIM"
                cp "$OPENSSL_IOS_SIM/lib"/*.a dependencies/openssl/lib/ 2>/dev/null || true
                cp -r "$OPENSSL_IOS_SIM/include"/* dependencies/openssl/include/ 2>/dev/null || true
              fi
              
              if [ -n "$OPENSSL_IOS" ] && [ -d "$OPENSSL_IOS/lib" ]; then
                echo "  → OpenSSL iOS Device: $OPENSSL_IOS"
                cp "$OPENSSL_IOS/lib"/*.a dependencies/openssl/lib-ios/ 2>/dev/null || true
                # Headers are the same for both
              fi
              
              # Make files writable
              chmod -R u+w dependencies/openssl 2>/dev/null || true
              
              echo "✅ OpenSSL staged to dependencies/openssl/ (headers + libraries only, no source)"
              
              echo "📦 Staging zsign library from Nix..."
              mkdir -p dependencies/zsign/{lib,include/zsign/common}
              
              # Use zsign package paths from script environment (set at top of script)
              # Debug: Check if zsign packages exist
              echo "  Checking zsign.ios-sim: $ZSIGN_IOS_SIM"
              echo "  Checking zsign.ios: $ZSIGN_IOS"
              
              # Stage zsign for iOS Simulator (used by Xcode)
              # Only stage build artifacts: library and headers (no source code)
              if [ -n "$ZSIGN_IOS_SIM" ] && [ -d "$ZSIGN_IOS_SIM/lib" ]; then
                echo "  → zsign iOS Simulator: $ZSIGN_IOS_SIM"
                if [ -f "$ZSIGN_IOS_SIM/lib/libzsign.a" ]; then
                  cp "$ZSIGN_IOS_SIM/lib/libzsign.a" dependencies/zsign/lib/libzsign-sim.a
                  echo "    ✅ Copied libzsign-sim.a"
                else
                  echo "    ⚠️  libzsign.a not found in $ZSIGN_IOS_SIM/lib"
                  ls -la "$ZSIGN_IOS_SIM/lib/" 2>/dev/null || echo "    Directory doesn't exist"
                fi
                if [ -d "$ZSIGN_IOS_SIM/include/zsign" ]; then
                  cp -r "$ZSIGN_IOS_SIM/include/zsign"/* dependencies/zsign/include/zsign/ 2>/dev/null || true
                  echo "    ✅ Copied headers"
                fi
              else
                echo "  ⚠️  zsign.ios-sim not available, trying to build..."
                if nix build '.#zsign-ios-sim' --print-out-paths 2>&1 | grep -q "^/nix/store"; then
                  ZSIGN_IOS_SIM=$(nix build '.#zsign-ios-sim' --print-out-paths 2>&1 | grep "^/nix/store" | head -1)
                  if [ -f "$ZSIGN_IOS_SIM/lib/libzsign.a" ]; then
                    cp "$ZSIGN_IOS_SIM/lib/libzsign.a" dependencies/zsign/lib/libzsign-sim.a
                    echo "    ✅ Built and copied libzsign-sim.a"
                  fi
                else
                  echo "    ⚠️  Failed to build zsign.ios-sim"
                fi
              fi
              
              # Stage zsign for iOS Device
              if [ -n "$ZSIGN_IOS" ] && [ -d "$ZSIGN_IOS/lib" ]; then
                echo "  → zsign iOS Device: $ZSIGN_IOS"
                if [ -f "$ZSIGN_IOS/lib/libzsign.a" ]; then
                  cp "$ZSIGN_IOS/lib/libzsign.a" dependencies/zsign/lib/libzsign-ios.a
                  echo "    ✅ Copied libzsign-ios.a"
                else
                  echo "    ⚠️  libzsign.a not found in $ZSIGN_IOS/lib"
                  ls -la "$ZSIGN_IOS/lib/" 2>/dev/null || echo "    Directory doesn't exist"
                fi
                # Headers are the same, only need to copy once
              else
                echo "  ⚠️  zsign.ios not available, trying to build..."
                if nix build '.#zsign-ios' --print-out-paths 2>&1 | grep -q "^/nix/store"; then
                  ZSIGN_IOS=$(nix build '.#zsign-ios' --print-out-paths 2>&1 | grep "^/nix/store" | head -1)
                  if [ -f "$ZSIGN_IOS/lib/libzsign.a" ]; then
                    cp "$ZSIGN_IOS/lib/libzsign.a" dependencies/zsign/lib/libzsign-ios.a
                    echo "    ✅ Built and copied libzsign-ios.a"
                  fi
                else
                  echo "    ⚠️  Failed to build zsign.ios"
                fi
              fi
              
              # Make files writable
              chmod -R u+w dependencies/zsign 2>/dev/null || true
              
              # Verify libraries were staged
              if [ -f "dependencies/zsign/lib/libzsign-sim.a" ] && [ -f "dependencies/zsign/lib/libzsign-ios.a" ]; then
                echo "✅ zsign library staged to dependencies/zsign/ (headers + library only, no source)"
              else
                echo "⚠️  zsign libraries not fully staged:"
                ls -la dependencies/zsign/lib/ 2>/dev/null || echo "  lib/ directory doesn't exist"
              fi
              
              echo "📦 Staging libimobiledevice stack from Nix..."
              mkdir -p dependencies/libimobiledevice/{lib,include,lib-ios}
              
              # Stage all libraries from the stack for iOS Simulator (used by Xcode)
              # Only stage build artifacts: libraries and headers (no source code)
              echo "  → Staging iOS Simulator libraries and headers..."
              
              # libplist
              if [ -d "$LIBPLIST_IOS_SIM/lib" ]; then
                cp $LIBPLIST_IOS_SIM/lib/*.a dependencies/libimobiledevice/lib/ 2>/dev/null || true
                cp -r $LIBPLIST_IOS_SIM/include/* dependencies/libimobiledevice/include/ 2>/dev/null || true
              fi
              
              # libimobiledevice-glue
              if [ -d "$LIBIMOBILEDEVICE_GLUE_IOS_SIM/lib" ]; then
                cp $LIBIMOBILEDEVICE_GLUE_IOS_SIM/lib/*.a dependencies/libimobiledevice/lib/ 2>/dev/null || true
                cp -r $LIBIMOBILEDEVICE_GLUE_IOS_SIM/include/* dependencies/libimobiledevice/include/ 2>/dev/null || true
              fi
              
              # libusbmuxd
              if [ -d "$LIBUSBMUXD_IOS_SIM/lib" ]; then
                cp $LIBUSBMUXD_IOS_SIM/lib/*.a dependencies/libimobiledevice/lib/ 2>/dev/null || true
                cp -r $LIBUSBMUXD_IOS_SIM/include/* dependencies/libimobiledevice/include/ 2>/dev/null || true
              fi
              
              # libimobiledevice
              if [ -d "$LIBIMOBILEDEVICE_IOS_SIM/lib" ]; then
                cp $LIBIMOBILEDEVICE_IOS_SIM/lib/*.a dependencies/libimobiledevice/lib/ 2>/dev/null || true
                cp -r $LIBIMOBILEDEVICE_IOS_SIM/include/* dependencies/libimobiledevice/include/ 2>/dev/null || true
              fi
              
              # Stage iOS Device libraries (headers are the same)
              echo "  → Staging iOS Device libraries..."
              
              if [ -d "$LIBPLIST_IOS/lib" ]; then
                cp $LIBPLIST_IOS/lib/*.a dependencies/libimobiledevice/lib-ios/ 2>/dev/null || true
              fi
              
              if [ -d "$LIBIMOBILEDEVICE_GLUE_IOS/lib" ]; then
                cp $LIBIMOBILEDEVICE_GLUE_IOS/lib/*.a dependencies/libimobiledevice/lib-ios/ 2>/dev/null || true
              fi
              
              if [ -d "$LIBUSBMUXD_IOS/lib" ]; then
                cp $LIBUSBMUXD_IOS/lib/*.a dependencies/libimobiledevice/lib-ios/ 2>/dev/null || true
              fi
              
              if [ -d "$LIBIMOBILEDEVICE_IOS/lib" ]; then
                cp $LIBIMOBILEDEVICE_IOS/lib/*.a dependencies/libimobiledevice/lib-ios/ 2>/dev/null || true
              fi
              
              # Make files writable
              chmod -R u+w dependencies/libimobiledevice 2>/dev/null || true
              
              echo "✅ libimobiledevice stack staged to dependencies/libimobiledevice/ (headers + libraries only, no source)"
              echo ""
              
              echo "🔨 Generating Xcode project with XcodeGen..."
              echo ""
              
              # Must run in actual working directory (not Nix store)
              # XcodeGen needs to read project.yml from current directory
              ${pkgs.xcodegen}/bin/xcodegen generate
              
              # Fix missing package references in XCSwiftPackageProductDependency entries
              # XcodeGen sometimes doesn't generate the 'package' field linking to XCLocalSwiftPackageReference
              echo "  🔧 Fixing package references in generated project..."
              python3 << 'PYEOF'
import re
import sys

project_file = 'HIAHDesktop.xcodeproj/project.pbxproj'

try:
    with open(project_file, 'r') as f:
        content = f.read()
    
    # Find package reference IDs - look for the pattern more flexibly
    alt_sign_ref_match = re.search(r'(\w+)\s*/\*\s*XCLocalSwiftPackageReference\s+"dependencies/swift-packages/AltSign"\s*\*/\s*=\s*\{[^}]*isa\s*=\s*XCLocalSwiftPackageReference[^}]*relativePath\s*=\s*dependencies/swift-packages/AltSign[^}]*\}', content)
    roxas_ref_match = re.search(r'(\w+)\s*/\*\s*XCLocalSwiftPackageReference\s+"dependencies/swift-packages/Roxas"\s*\*/\s*=\s*\{[^}]*isa\s*=\s*XCLocalSwiftPackageReference[^}]*relativePath\s*=\s*dependencies/swift-packages/Roxas[^}]*\}', content)
    
    # Alternative pattern if the above doesn't match
    if not alt_sign_ref_match:
        alt_sign_ref_match = re.search(r'(\w+)\s*=\s*\{[^}]*isa\s*=\s*XCLocalSwiftPackageReference[^}]*dependencies/swift-packages/AltSign[^}]*\}', content, re.DOTALL)
    if not roxas_ref_match:
        roxas_ref_match = re.search(r'(\w+)\s*=\s*\{[^}]*isa\s*=\s*XCLocalSwiftPackageReference[^}]*dependencies/swift-packages/Roxas[^}]*\}', content, re.DOTALL)
    
    if not alt_sign_ref_match or not roxas_ref_match:
        print("  ⚠️  Could not find package references, trying alternative search...")
        # Try to find by searching for the reference in packageReferences section
        package_refs_match = re.search(r'packageReferences\s*=\s*\(([^)]+)\)', content, re.DOTALL)
        if package_refs_match:
            refs_section = package_refs_match.group(1)
            alt_match = re.search(r'(\w+)\s*/\*\s*XCLocalSwiftPackageReference[^"]*"dependencies/swift-packages/AltSign"', refs_section)
            roxas_match = re.search(r'(\w+)\s*/\*\s*XCLocalSwiftPackageReference[^"]*"dependencies/swift-packages/Roxas"', refs_section)
            if alt_match:
                alt_sign_ref_id = alt_match.group(1)
            if roxas_match:
                roxas_ref_id = roxas_match.group(1)
        else:
            print("  ⚠️  Could not find package references")
            sys.exit(0)
    else:
        alt_sign_ref_id = alt_sign_ref_match.group(1)
        roxas_ref_id = roxas_ref_match.group(1)
    
    # Fix AltSign-Static product dependency - use more flexible pattern
    alt_sign_product_pattern = r'(\w+\s*/\*\s*AltSign-Static\s*\*/\s*=\s*\{[^}]*isa\s*=\s*XCSwiftPackageProductDependency[^}]*productName\s*=\s*"AltSign-Static"[^}]*\})'
    alt_sign_product_match = re.search(alt_sign_product_pattern, content, re.DOTALL)
    if alt_sign_product_match:
        old_entry = alt_sign_product_match.group(1)
        if 'package =' not in old_entry:
            # Extract the ID from the match
            id_match = re.search(r'(\w+)\s*/\*', old_entry)
            if id_match:
                product_id = id_match.group(1)
                new_entry = old_entry.replace(
                    'productName = "AltSign-Static";',
                    f'package = {alt_sign_ref_id} /* XCLocalSwiftPackageReference "dependencies/swift-packages/AltSign" */;\n\t\t\tproductName = "AltSign-Static";'
                )
                content = content.replace(old_entry, new_entry)
                print(f"  ✅ Fixed AltSign-Static package reference")
    
    # Fix OpenSSL product dependency
    openssl_product_pattern = r'(\w+\s*/\*\s*OpenSSL\s*\*/\s*=\s*\{[^}]*isa\s*=\s*XCSwiftPackageProductDependency[^}]*productName\s*=\s*OpenSSL[^}]*\})'
    openssl_product_match = re.search(openssl_product_pattern, content, re.DOTALL)
    if openssl_product_match:
        old_entry = openssl_product_match.group(1)
        if 'package =' not in old_entry:
            id_match = re.search(r'(\w+)\s*/\*', old_entry)
            if id_match:
                new_entry = old_entry.replace(
                    'productName = OpenSSL;',
                    f'package = {alt_sign_ref_id} /* XCLocalSwiftPackageReference "dependencies/swift-packages/AltSign" */;\n\t\t\tproductName = OpenSSL;'
                )
                content = content.replace(old_entry, new_entry)
                print(f"  ✅ Fixed OpenSSL package reference")
    
    # Fix Roxas product dependency
    roxas_product_pattern = r'(\w+\s*/\*\s*Roxas\s*\*/\s*=\s*\{[^}]*isa\s*=\s*XCSwiftPackageProductDependency[^}]*productName\s*=\s*Roxas[^}]*\})'
    roxas_product_match = re.search(roxas_product_pattern, content, re.DOTALL)
    if roxas_product_match:
        old_entry = roxas_product_match.group(1)
        if 'package =' not in old_entry:
            new_entry = old_entry.replace(
                'productName = Roxas;',
                f'package = {roxas_ref_id} /* XCLocalSwiftPackageReference "dependencies/swift-packages/Roxas" */;\n\t\t\tproductName = Roxas;'
            )
            content = content.replace(old_entry, new_entry)
            print(f"  ✅ Fixed Roxas package reference")
    
    with open(project_file, 'w') as f:
        f.write(content)
    
except Exception as e:
    import traceback
    print(f"  ⚠️  Error fixing package references: {e}")
    traceback.print_exc()
PYEOF
              
              # Force Xcode to resolve packages immediately after generation
              echo "  🔄 Resolving packages..."
              xcodebuild -resolvePackageDependencies -project HIAHDesktop.xcodeproj -scheme HIAHDesktop >/dev/null 2>&1 || true
              
              # Clean up any .swiftpm directories that Xcode created with invalid project references
              # These can cause "Couldn't load project" errors in Xcode
              echo "  🧹 Cleaning up Xcode-generated .swiftpm artifacts..."
              find dependencies/swift-packages -name ".swiftpm" -type d -exec rm -rf {} + 2>/dev/null || true
              
              echo ""
              echo "✅ HIAHDesktop.xcodeproj generated!"
              echo "   Open: open HIAHDesktop.xcodeproj"
              echo ""
              echo "📦 Packages resolved: AltSign-Static (includes OpenSSL), Roxas"
              echo "📂 Project references ./src/ directly"
              echo "🎯 Single source of truth!"
              echo ""
              echo "💡 If Xcode shows package errors, try:"
              echo "   1. File → Packages → Reset Package Caches"
              echo "   2. File → Packages → Resolve Package Versions"
              echo "   3. Close and reopen the project"
            '';
          
          xcgen = {
            type = "app";
            program = toString (pkgs.writeShellScript "xcgen" ''
              set -eux pipefail
              
              echo "🚀 Starting xcgen - Xcode project generator"
              echo "=========================================="
              echo ""
              
              # Get libimobiledevice stack packages (now using standalone packages)
              LIBPLIST_IOS_SIM="${libplist.ios-sim}"
              LIBPLIST_IOS="${libplist.ios}"
              LIBIMOBILEDEVICE_GLUE_IOS_SIM="${libimobiledevice-glue.ios-sim}"
              LIBIMOBILEDEVICE_GLUE_IOS="${libimobiledevice-glue.ios}"
              LIBUSBMUXD_IOS_SIM="${libusbmuxd.ios-sim}"
              LIBUSBMUXD_IOS="${libusbmuxd.ios}"
              LIBIMOBILEDEVICE_IOS_SIM="${libimobiledevice-standalone.ios-sim}"
              LIBIMOBILEDEVICE_IOS="${libimobiledevice-standalone.ios}"
              
              # Get zsign and openssl packages (built as dependencies)
              # These will be built automatically when the script runs
              echo "📦 Preparing dependencies (will build if needed)..."
              ZSIGN_IOS_SIM="${toString zsign.ios-sim}"
              ZSIGN_IOS="${toString zsign.ios}"
              OPENSSL_IOS_SIM="${toString openssl.ios-sim}"
              OPENSSL_IOS="${toString openssl.ios}"
              echo "  ✅ Package paths resolved"
              echo ""
              
              echo "🔨 Staging SideStore components..."
              
              # Create directories for staged build artifacts (not source code)
              mkdir -p dependencies/sidestore/lib dependencies/sidestore/include
              
              # Copy Swift bridge files from Nix-built packages
              # These are build artifacts, not source code - they come from Nix builds
              if [ -d "${sidestore.all}/include" ]; then
                echo "  → Copying Swift bridge files from Nix-built sidestore.all..."
                cp ${sidestore.all}/include/*.swift dependencies/sidestore/include/ 2>/dev/null || true
                cp ${sidestore.all}/include/*.h dependencies/sidestore/include/ 2>/dev/null || true
              else
                echo "  ⚠️  sidestore.all/include not found - bridge files may be missing"
                echo "     Run 'nix build .#sidestore-all' to build SideStore components"
              fi
              
              # Note: em_proxy and minimuxer libraries should be prebuilt and in dependencies/sidestore/lib/
              # They were built with SideStore's build system and copied manually.
              # The Nix builds for these are complex due to iOS cross-compilation requirements.
              
              echo "📦 Staging Swift packages (AltSign, Roxas) from Nix..."
              
              # Stage Swift packages to dependencies/swift-packages/ for XcodeGen
              echo "📦 Staging Swift packages (AltSign, Roxas)..."
              mkdir -p dependencies/swift-packages
              
              # Remove existing symlinks/directories if they exist (make writable first if from Nix store)
              chmod -R +w dependencies/swift-packages/AltSign 2>/dev/null || true
              rm -rf dependencies/swift-packages/AltSign 2>/dev/null || true
              chmod -R +w dependencies/swift-packages/Roxas 2>/dev/null || true
              rm -rf dependencies/swift-packages/Roxas 2>/dev/null || true
              
              # Stage AltSign package
              if [ -d "${sidestore.altsign}/AltSign" ]; then
                echo "  → AltSign: ${sidestore.altsign}/AltSign"
                cp -r ${sidestore.altsign}/AltSign dependencies/swift-packages/AltSign
              else
                echo "  ⚠️  AltSign not found at ${sidestore.altsign}/AltSign"
                echo "     Checking alternative location..."
                if [ -d "${sidestore.altsign}" ]; then
                  cp -r ${sidestore.altsign} dependencies/swift-packages/AltSign
                else
                  echo "  ❌ AltSign package not found!"
                  exit 1
                fi
              fi
              
              # Make copied files writable FIRST (they come from read-only Nix store)
              echo "  🔓 Making AltSign package writable..."
              chmod -R u+w dependencies/swift-packages/AltSign 2>/dev/null || true
              
              # Remove .xcodeproj files and .swiftpm directories that confuse Xcode (they're not needed for SPM)
              echo "  🧹 Cleaning up AltSign package..."
              rm -rf dependencies/swift-packages/AltSign/Dependencies/OpenSSL/OpenSSL.xcodeproj 2>/dev/null || true
              rm -rf dependencies/swift-packages/AltSign/Dependencies/OpenSSL/Integration-Examples 2>/dev/null || true
              # Remove any .xcodeproj files in the package root
              find dependencies/swift-packages/AltSign -name "*.xcodeproj" -type d -exec rm -rf {} + 2>/dev/null || true
              # Remove .swiftpm directories (Xcode will regenerate these)
              rm -rf dependencies/swift-packages/AltSign/.swiftpm 2>/dev/null || true
              # Remove any workspace files
              find dependencies/swift-packages/AltSign -name "*.xcworkspace" -type d -exec rm -rf {} + 2>/dev/null || true
              
              # Fix OpenSSL header search path in AltSign's Package.swift (uncomment and fix paths)
              echo "  🔧 Fixing OpenSSL header paths in AltSign Package.swift..."
              python3 << 'PYEOF'
import re

try:
    with open('dependencies/swift-packages/AltSign/Package.swift', 'r') as f:
        content = f.read()

    # Fix all commented OpenSSL paths
    content = content.replace(
        '//                .headerSearchPath("../OpenSSL/ios/include"),',
        '                .headerSearchPath("../OpenSSL/iphonesimulator/include"),'
    )
    content = content.replace(
        '//                .headerSearchPath("../../Dependencies/OpenSSL/ios/include"),',
        '                .headerSearchPath("../../Dependencies/OpenSSL/iphonesimulator/include"),'
    )
    content = content.replace(
        '//                .headerSearchPath("Dependencies/OpenSSL/ios/include"),',
        '                .headerSearchPath("Dependencies/OpenSSL/iphonesimulator/include"),'
    )

    with open('dependencies/swift-packages/AltSign/Package.swift', 'w') as f:
        f.write(content)
    print("  ✅ Fixed OpenSSL paths")
except Exception as e:
    print(f"  ⚠️  Error: {e}")
PYEOF
              
              # Also need to handle the case where code includes <openssl/err.h> but headers are in OpenSSL/ (capital)
              # Create symlink from openssl -> OpenSSL for case-insensitive access
              if [ -d "dependencies/swift-packages/AltSign/Dependencies/OpenSSL/iphonesimulator/include/OpenSSL" ] && [ ! -e "dependencies/swift-packages/AltSign/Dependencies/OpenSSL/iphonesimulator/include/openssl" ]; then
                (cd dependencies/swift-packages/AltSign/Dependencies/OpenSSL/iphonesimulator/include && ln -s OpenSSL openssl) 2>/dev/null || true
              fi
              
              # Stage Roxas package
              if [ -d "${sidestore.roxas}/Roxas" ]; then
                echo "  → Roxas: ${sidestore.roxas}/Roxas"
                cp -r ${sidestore.roxas}/Roxas dependencies/swift-packages/Roxas
              else
                echo "  ⚠️  Roxas not found at ${sidestore.roxas}/Roxas"
                echo "     Checking alternative location..."
                if [ -d "${sidestore.roxas}" ]; then
                  cp -r ${sidestore.roxas} dependencies/swift-packages/Roxas
                else
                  echo "  ❌ Roxas package not found!"
                  exit 1
                fi
              fi
              
              # Make copied directories writable FIRST (they come from read-only Nix store)
              echo "  🔓 Making packages writable..."
              chmod -R u+w dependencies/swift-packages/AltSign dependencies/swift-packages/Roxas 2>/dev/null || true
              
              # Remove .xcodeproj, .xcworkspace, and .swiftpm files that confuse Xcode (they're not needed for SPM)
              echo "  🧹 Cleaning up package directories..."
              find dependencies/swift-packages/AltSign -name "*.xcodeproj" -type d -exec rm -rf {} + 2>/dev/null || true
              find dependencies/swift-packages/AltSign -name "*.xcworkspace" -type d -exec rm -rf {} + 2>/dev/null || true
              find dependencies/swift-packages/Roxas -name "*.xcodeproj" -type d -exec rm -rf {} + 2>/dev/null || true
              find dependencies/swift-packages/Roxas -name "*.xcworkspace" -type d -exec rm -rf {} + 2>/dev/null || true
              # Remove .swiftpm directories (Xcode will regenerate these correctly when resolving packages)
              rm -rf dependencies/swift-packages/AltSign/.swiftpm 2>/dev/null || true
              rm -rf dependencies/swift-packages/Roxas/.swiftpm 2>/dev/null || true
              # Remove DerivedData and .build artifacts
              find dependencies/swift-packages -name "DerivedData" -type d -exec rm -rf {} + 2>/dev/null || true
              find dependencies/swift-packages -name ".build" -type d -exec rm -rf {} + 2>/dev/null || true
              rm -rf dependencies/swift-packages/AltSign/Dependencies/OpenSSL/Integration-Examples 2>/dev/null || true
              
              # Remove code signature from OpenSSL.xcframework (it's not valid)
              echo "  🔓 Removing invalid code signature from OpenSSL.xcframework..."
              rm -rf dependencies/swift-packages/AltSign/Dependencies/OpenSSL/Frameworks/OpenSSL.xcframework/_CodeSignature 2>/dev/null || true
              
              # Create .xcodeignore files to prevent Xcode from trying to load these as projects
              echo "  📝 Creating .xcodeignore files..."
              cat > dependencies/swift-packages/AltSign/.xcodeignore << 'IGNEOF'
*.xcodeproj
*.xcworkspace
Tests/
.github/
.gitmodules
IGNEOF
              cat > dependencies/swift-packages/Roxas/.xcodeignore << 'IGNEOF'
*.xcodeproj
*.xcworkspace
Tests/
.github/
IGNEOF
              
              # Create symlink so #import <AltSign/AltSign.h> resolves correctly
              # The bridging header uses <AltSign/AltSign.h> but AltSign.h is at include/AltSign.h
              # We need include/AltSign/AltSign.h -> ../AltSign.h
              echo "  🔗 Creating AltSign header symlink for bridging header..."
              if [ -d "dependencies/swift-packages/AltSign/AltSign/include/AltSign" ] && [ ! -e "dependencies/swift-packages/AltSign/AltSign/include/AltSign/AltSign.h" ]; then
                ln -sf "../AltSign.h" "dependencies/swift-packages/AltSign/AltSign/include/AltSign/AltSign.h"
                echo "  ✅ Created AltSign.h symlink"
              fi
              
              # Fix OpenSSL header search path in AltSign's Package.swift (uncomment and fix paths)
              # Also add OpenSSL to AltSign-Static targets so it links properly
              echo "  🔧 Fixing OpenSSL header paths in AltSign Package.swift..."
              python3 << 'PYEOF'
import re

try:
    with open('dependencies/swift-packages/AltSign/Package.swift', 'r') as f:
        content = f.read()

    # Fix all commented OpenSSL paths
    content = content.replace(
        '//                .headerSearchPath("../OpenSSL/ios/include"),',
        '                .headerSearchPath("../OpenSSL/iphonesimulator/include"),'
    )
    content = content.replace(
        '//                .headerSearchPath("../../Dependencies/OpenSSL/ios/include"),',
        '                .headerSearchPath("../../Dependencies/OpenSSL/iphonesimulator/include"),'
    )
    content = content.replace(
        '//                .headerSearchPath("Dependencies/OpenSSL/ios/include"),',
        '                .headerSearchPath("Dependencies/OpenSSL/iphonesimulator/include"),'
    )
    
    # Add OpenSSL to AltSign-Static targets list so it links properly
    content = content.replace(
        'targets: ["AltSign", "CAltSign", "CoreCrypto", "CCoreCrypto", "ldid", "ldid-core"]',
        'targets: ["AltSign", "CAltSign", "CoreCrypto", "CCoreCrypto", "ldid", "ldid-core", "OpenSSL"]'
    )

    with open('dependencies/swift-packages/AltSign/Package.swift', 'w') as f:
        f.write(content)
    print("  ✅ Fixed OpenSSL paths and added OpenSSL to AltSign-Static")
except Exception as e:
    print(f"  ⚠️  Error fixing OpenSSL paths: {e}")
PYEOF
              
              # Also need to handle the case where code includes <openssl/err.h> but headers are in OpenSSL/ (capital)
              # Create symlink from openssl -> OpenSSL for case-insensitive access
              if [ -d "dependencies/swift-packages/AltSign/Dependencies/OpenSSL/iphonesimulator/include/OpenSSL" ] && [ ! -e "dependencies/swift-packages/AltSign/Dependencies/OpenSSL/iphonesimulator/include/openssl" ]; then
                (cd dependencies/swift-packages/AltSign/Dependencies/OpenSSL/iphonesimulator/include && ln -s OpenSSL openssl) 2>/dev/null || true
              fi
              
              # Restructure Roxas to SPM layout
              # Put ALL headers in include/Roxas/ subdirectory (not at root of include/)
              # This is the correct SPM layout for <Roxas/Header.h> style imports
              echo "  📦 Restructuring Roxas to SPM layout..."
              mkdir -p dependencies/swift-packages/Roxas/Sources/Roxas/include/Roxas
              # Move headers to include/Roxas/ and implementation files to Sources/Roxas/
              find dependencies/swift-packages/Roxas -maxdepth 1 -type f -name "*.h" -exec mv {} dependencies/swift-packages/Roxas/Sources/Roxas/include/Roxas/ \;
              find dependencies/swift-packages/Roxas -maxdepth 1 -type f \( -name "*.m" -o -name "*.xib" -o -name "*.pch" \) -exec mv {} dependencies/swift-packages/Roxas/Sources/Roxas/ \;
              
              # CRITICAL: Convert umbrella header imports from <Roxas/Header.h> to "Header.h"
              # During module compilation, the umbrella header can't use module-style imports
              # because the module doesn't exist yet. External consumers use @import Roxas.
              echo "  🔧 Fixing Roxas.h umbrella header imports..."
              if [ -f "dependencies/swift-packages/Roxas/Sources/Roxas/include/Roxas/Roxas.h" ]; then
                python3 << 'PYEOF'
import re
with open('dependencies/swift-packages/Roxas/Sources/Roxas/include/Roxas/Roxas.h', 'r') as f:
    content = f.read()
# Convert <Roxas/Header.h> to "Header.h" (all headers are in same directory)
content = re.sub(r'#import <Roxas/([^>]+)>', r'#import "\1"', content)
with open('dependencies/swift-packages/Roxas/Sources/Roxas/include/Roxas/Roxas.h', 'w') as f:
    f.write(content)
print("  ✅ Converted umbrella header to quote imports")
PYEOF
              fi
              
              # Fix missing RSTDefines.h includes in files that use ELog
              echo "  🔧 Fixing missing RSTDefines.h includes..."
              # Add RSTDefines.h to files that use ELog but don't include it
              python3 << 'PYEOF'
import re
import os

files_to_fix = [
    ('dependencies/swift-packages/Roxas/Sources/Roxas/NSFileManager+URLs.m', 'NSFileManager+URLs.h', 'RSTDefines.h'),
    ('dependencies/swift-packages/Roxas/Sources/Roxas/RSTFetchedResultsDataSource.m', 'RSTCellContentDataSource_Subclasses.h', 'RSTDefines.h'),
    ('dependencies/swift-packages/Roxas/Sources/Roxas/RSTPersistentContainer.m', 'RSTError.h', 'RSTDefines.h'),
]

for filepath, after_import, add_import in files_to_fix:
    if not os.path.exists(filepath):
        continue
    try:
        with open(filepath, 'r') as f:
            content = f.read()
        
        if add_import in content:
            continue
        
        # Find the line with the import to add after
        lines = content.split('\n')
        new_lines = []
        added = False
        for i, line in enumerate(lines):
            new_lines.append(line)
            if not added and after_import in line and '#import' in line:
                # Add the import on the next line
                new_lines.append(f'#import "{add_import}"')
                added = True
        
        if added:
            with open(filepath, 'w') as f:
                f.write('\n'.join(new_lines))
            print(f"  ✅ Fixed {os.path.basename(filepath)}")
    except Exception as e:
        print(f"  ⚠️  Error fixing {filepath}: {e}")
PYEOF
              
              # Fix <Roxas/HeaderName.h> includes in public headers (change to "HeaderName.h" for same-directory includes)
              echo "  🔧 Fixing module-style includes in public headers..."
              # RSTPlaceholderView.h uses <Roxas/RSTNibView.h> but they're in the same directory
              python3 << 'PYEOF'
import re
import os
import glob

# Fix all headers that use <Roxas/...> imports - they should use "" since they're in same directory
for header_file in glob.glob('dependencies/swift-packages/Roxas/Sources/Roxas/include/Roxas/*.h'):
    try:
        with open(header_file, 'r') as f:
            content = f.read()
        # Convert <Roxas/Header.h> to "Header.h"
        new_content = re.sub(r'#import <Roxas/([^>]+)>', r'#import "\1"', content)
        if new_content != content:
            with open(header_file, 'w') as f:
                f.write(new_content)
    except Exception as e:
        pass
print("  ✅ Fixed module-style includes in headers")
PYEOF
              
              # Fix headers that use RST_EXTERN but don't include RSTDefines.h
              echo "  🔧 Fixing missing RSTDefines.h in headers using RST_EXTERN..."
              python3 << 'PYEOF'
import re
import os

headers_to_fix = [
    'dependencies/swift-packages/Roxas/Sources/Roxas/include/Roxas/RSTCellContentDataSource.h',
    'dependencies/swift-packages/Roxas/Sources/Roxas/include/Roxas/RSTHelperFile.h',
    'dependencies/swift-packages/Roxas/Sources/Roxas/include/Roxas/RSTNavigationController.h',
    'dependencies/swift-packages/Roxas/Sources/Roxas/include/Roxas/RSTToastView.h',
    'dependencies/swift-packages/Roxas/Sources/Roxas/include/Roxas/UIImage+Manipulation.h',
    'dependencies/swift-packages/Roxas/Sources/Roxas/include/Roxas/UISpringTimingParameters+Conveniences.h',
]

for header_path in headers_to_fix:
    if not os.path.exists(header_path):
        continue
    try:
        with open(header_path, 'r') as f:
            content = f.read()
        
        if 'RSTDefines.h' in content:
            continue
        
        if 'RST_EXTERN' not in content:
            continue
        
        # Find the first @import or #import line and add RSTDefines.h after it
        lines = content.split('\n')
        new_lines = []
        added = False
        for i, line in enumerate(lines):
            new_lines.append(line)
            if not added and ('@import' in line or '#import' in line) and 'RSTDefines' not in line:
                # Add RSTDefines.h import after the first import
                new_lines.append('#import "RSTDefines.h"')
                added = True
        
        if added:
            with open(header_path, 'w') as f:
                f.write('\n'.join(new_lines))
    except Exception as e:
        pass
PYEOF
              
              # Create Package.swift for Roxas (Roxas is CocoaPods, converting to SPM)
              echo "  📝 Creating Package.swift for Roxas..."
              cat > dependencies/swift-packages/Roxas/Package.swift << 'PKGEOF'
// swift-tools-version:5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import Foundation
import PackageDescription

let package = Package(
    name: "Roxas",
    platforms: [
        .iOS(.v14),
        .macOS(.v11),
    ],
    products: [
        .library(
            name: "Roxas",
            targets: ["Roxas"]
        ),
    ],
    targets: [
        .target(
            name: "Roxas",
            path: "Sources/Roxas",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("."),
                .headerSearchPath("include"),
                .headerSearchPath("include/Roxas"),
            ],
            linkerSettings: [
                .linkedFramework("UIKit", .when(platforms: [.iOS])),
                .linkedFramework("Foundation"),
                .linkedFramework("CoreData"),
            ]
        ),
    ]
)
PKGEOF
              echo "  ✅ Created Package.swift for Roxas with SPM layout"
              
              echo "✅ Swift packages staged to dependencies/swift-packages/"
              echo ""
              
              # Stage OpenSSL from Nix (for zsign)
              echo "📦 Staging OpenSSL from Nix..."
              mkdir -p dependencies/openssl/{lib,lib-ios,include}
              
              # Use OPENSSL_IOS_SIM and OPENSSL_IOS from script environment
              if [ -n "$OPENSSL_IOS_SIM" ] && [ -d "$OPENSSL_IOS_SIM/lib" ]; then
                echo "  → OpenSSL iOS Simulator: $OPENSSL_IOS_SIM"
                cp "$OPENSSL_IOS_SIM/lib"/*.a dependencies/openssl/lib/ 2>/dev/null || true
                cp -r "$OPENSSL_IOS_SIM/include"/* dependencies/openssl/include/ 2>/dev/null || true
              fi
              
              if [ -n "$OPENSSL_IOS" ] && [ -d "$OPENSSL_IOS/lib" ]; then
                echo "  → OpenSSL iOS Device: $OPENSSL_IOS"
                cp "$OPENSSL_IOS/lib"/*.a dependencies/openssl/lib-ios/ 2>/dev/null || true
                # Headers are the same for both
              fi
              
              # Make files writable
              chmod -R u+w dependencies/openssl 2>/dev/null || true
              
              echo "✅ OpenSSL staged to dependencies/openssl/ (headers + libraries only, no source)"
              
              echo "📦 Staging zsign library from Nix..."
              mkdir -p dependencies/zsign/{lib,include/zsign/common}
              
              # Use zsign package paths from script environment (set at top of script)
              # Debug: Check if zsign packages exist
              echo "  Checking zsign.ios-sim: $ZSIGN_IOS_SIM"
              echo "  Checking zsign.ios: $ZSIGN_IOS"
              
              # Stage zsign for iOS Simulator (used by Xcode)
              # Only stage build artifacts: library and headers (no source code)
              if [ -n "$ZSIGN_IOS_SIM" ] && [ -d "$ZSIGN_IOS_SIM/lib" ]; then
                echo "  → zsign iOS Simulator: $ZSIGN_IOS_SIM"
                if [ -f "$ZSIGN_IOS_SIM/lib/libzsign.a" ]; then
                  cp "$ZSIGN_IOS_SIM/lib/libzsign.a" dependencies/zsign/lib/libzsign-sim.a
                  echo "    ✅ Copied libzsign-sim.a"
                else
                  echo "    ⚠️  libzsign.a not found in $ZSIGN_IOS_SIM/lib"
                  ls -la "$ZSIGN_IOS_SIM/lib/" 2>/dev/null || echo "    Directory doesn't exist"
                fi
                if [ -d "$ZSIGN_IOS_SIM/include/zsign" ]; then
                  cp -r "$ZSIGN_IOS_SIM/include/zsign"/* dependencies/zsign/include/zsign/ 2>/dev/null || true
                  echo "    ✅ Copied headers"
                fi
              else
                echo "  ⚠️  zsign.ios-sim not available, trying to build..."
                if nix build '.#zsign-ios-sim' --print-out-paths 2>&1 | grep -q "^/nix/store"; then
                  ZSIGN_IOS_SIM=$(nix build '.#zsign-ios-sim' --print-out-paths 2>&1 | grep "^/nix/store" | head -1)
                  if [ -f "$ZSIGN_IOS_SIM/lib/libzsign.a" ]; then
                    cp "$ZSIGN_IOS_SIM/lib/libzsign.a" dependencies/zsign/lib/libzsign-sim.a
                    echo "    ✅ Built and copied libzsign-sim.a"
                  fi
                else
                  echo "    ⚠️  Failed to build zsign.ios-sim"
                fi
              fi
              
              # Stage zsign for iOS Device
              if [ -n "$ZSIGN_IOS" ] && [ -d "$ZSIGN_IOS/lib" ]; then
                echo "  → zsign iOS Device: $ZSIGN_IOS"
                if [ -f "$ZSIGN_IOS/lib/libzsign.a" ]; then
                  cp "$ZSIGN_IOS/lib/libzsign.a" dependencies/zsign/lib/libzsign-ios.a
                  echo "    ✅ Copied libzsign-ios.a"
                else
                  echo "    ⚠️  libzsign.a not found in $ZSIGN_IOS/lib"
                  ls -la "$ZSIGN_IOS/lib/" 2>/dev/null || echo "    Directory doesn't exist"
                fi
                # Headers are the same, only need to copy once
              else
                echo "  ⚠️  zsign.ios not available, trying to build..."
                if nix build '.#zsign-ios' --print-out-paths 2>&1 | grep -q "^/nix/store"; then
                  ZSIGN_IOS=$(nix build '.#zsign-ios' --print-out-paths 2>&1 | grep "^/nix/store" | head -1)
                  if [ -f "$ZSIGN_IOS/lib/libzsign.a" ]; then
                    cp "$ZSIGN_IOS/lib/libzsign.a" dependencies/zsign/lib/libzsign-ios.a
                    echo "    ✅ Built and copied libzsign-ios.a"
                  fi
                else
                  echo "    ⚠️  Failed to build zsign.ios"
                fi
              fi
              
              # Make files writable
              chmod -R u+w dependencies/zsign 2>/dev/null || true
              
              # Verify libraries were staged
              if [ -f "dependencies/zsign/lib/libzsign-sim.a" ] && [ -f "dependencies/zsign/lib/libzsign-ios.a" ]; then
                echo "✅ zsign library staged to dependencies/zsign/ (headers + library only, no source)"
              else
                echo "⚠️  zsign libraries not fully staged:"
                ls -la dependencies/zsign/lib/ 2>/dev/null || echo "  lib/ directory doesn't exist"
              fi
              
              echo "📦 Staging libimobiledevice stack from Nix..."
              mkdir -p dependencies/libimobiledevice/{lib,include,lib-ios}
              
              # Stage all libraries from the stack for iOS Simulator (used by Xcode)
              # Only stage build artifacts: libraries and headers (no source code)
              echo "  → Staging iOS Simulator libraries and headers..."
              
              # libplist
              if [ -d "$LIBPLIST_IOS_SIM/lib" ]; then
                cp $LIBPLIST_IOS_SIM/lib/*.a dependencies/libimobiledevice/lib/ 2>/dev/null || true
                cp -r $LIBPLIST_IOS_SIM/include/* dependencies/libimobiledevice/include/ 2>/dev/null || true
              fi
              
              # libimobiledevice-glue
              if [ -d "$LIBIMOBILEDEVICE_GLUE_IOS_SIM/lib" ]; then
                cp $LIBIMOBILEDEVICE_GLUE_IOS_SIM/lib/*.a dependencies/libimobiledevice/lib/ 2>/dev/null || true
                cp -r $LIBIMOBILEDEVICE_GLUE_IOS_SIM/include/* dependencies/libimobiledevice/include/ 2>/dev/null || true
              fi
              
              # libusbmuxd
              if [ -d "$LIBUSBMUXD_IOS_SIM/lib" ]; then
                cp $LIBUSBMUXD_IOS_SIM/lib/*.a dependencies/libimobiledevice/lib/ 2>/dev/null || true
                cp -r $LIBUSBMUXD_IOS_SIM/include/* dependencies/libimobiledevice/include/ 2>/dev/null || true
              fi
              
              # libimobiledevice
              if [ -d "$LIBIMOBILEDEVICE_IOS_SIM/lib" ]; then
                cp $LIBIMOBILEDEVICE_IOS_SIM/lib/*.a dependencies/libimobiledevice/lib/ 2>/dev/null || true
                cp -r $LIBIMOBILEDEVICE_IOS_SIM/include/* dependencies/libimobiledevice/include/ 2>/dev/null || true
              fi
              
              echo "  → Staging iOS Device libraries..."
              
              if [ -d "$LIBPLIST_IOS/lib" ]; then
                cp $LIBPLIST_IOS/lib/*.a dependencies/libimobiledevice/lib-ios/ 2>/dev/null || true
              fi
              
              if [ -d "$LIBIMOBILEDEVICE_GLUE_IOS/lib" ]; then
                cp $LIBIMOBILEDEVICE_GLUE_IOS/lib/*.a dependencies/libimobiledevice/lib-ios/ 2>/dev/null || true
              fi
              
              if [ -d "$LIBUSBMUXD_IOS/lib" ]; then
                cp $LIBUSBMUXD_IOS/lib/*.a dependencies/libimobiledevice/lib-ios/ 2>/dev/null || true
              fi
              
              if [ -d "$LIBIMOBILEDEVICE_IOS/lib" ]; then
                cp $LIBIMOBILEDEVICE_IOS/lib/*.a dependencies/libimobiledevice/lib-ios/ 2>/dev/null || true
              fi
              
              # Make files writable
              chmod -R u+w dependencies/libimobiledevice 2>/dev/null || true
              
              echo "✅ libimobiledevice stack staged to dependencies/libimobiledevice/ (headers + libraries only, no source)"
              echo ""
              
              # Generate Xcode project using XcodeGen
              echo "🎯 Generating Xcode project with XcodeGen..."
              echo ""
              
              # Use xcodegen from Nix
              XCODEGEN_CMD="${pkgs.xcodegen}/bin/xcodegen"
              if [ ! -f "$XCODEGEN_CMD" ]; then
                echo "❌ xcodegen not found at $XCODEGEN_CMD"
                echo "   xcodegen should be available from Nix"
                exit 1
              fi
              echo "Using xcodegen from Nix: $XCODEGEN_CMD"
              
              echo ""
              echo "Running: $XCODEGEN_CMD generate"
              echo ""
              
              # Run xcodegen and capture output
              if $XCODEGEN_CMD generate 2>&1; then
                echo ""
                echo "✅ Xcode project generated successfully!"
                echo ""
                
                # Show what was generated
                if [ -d "HIAHDesktop.xcodeproj" ]; then
                  echo "📦 Generated project: HIAHDesktop.xcodeproj"
                  
                  # Count targets and files
                  if [ -f "HIAHDesktop.xcodeproj/project.pbxproj" ]; then
                    TARGET_COUNT=$(grep -c "isa = PBXNativeTarget" HIAHDesktop.xcodeproj/project.pbxproj 2>/dev/null || echo "0")
                    echo "   Targets: $TARGET_COUNT"
                    
                    # Show some key information
                    echo ""
                    echo "📋 Project includes:"
                    echo "   - Source files from ./src/"
                    echo "   - Staged libraries from ./dependencies/"
                    echo "   - Swift packages: AltSign, Roxas"
                    echo "   - Static libraries: zsign, OpenSSL, libimobiledevice stack"
                  fi
                fi
                
                echo ""
                echo "📝 Next steps:"
                echo "   1. Open HIAHDesktop.xcodeproj in Xcode"
                echo "   2. Build the project (⌘B)"
                echo ""
                echo "🎯 Single source of truth!"
                echo ""
                echo "💡 If Xcode shows package errors, try:"
                echo "   1. File → Packages → Reset Package Caches"
                echo "   2. File → Packages → Resolve Package Versions"
                echo "   3. Close and reopen the project"
              else
                echo ""
                echo "❌ XcodeGen failed to generate project"
                echo "   Check project.yml for errors"
                exit 1
              fi
            '');
          };
        };

        # Development shell with Rust and build tools
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            # Rust toolchain with iOS cross-compilation
            (rust-bin.stable.latest.default.override {
              targets = [ "aarch64-apple-ios" "aarch64-apple-ios-sim" "x86_64-apple-ios" ];
            })
            
            # Build tools
            cmake
            pkg-config
            
            # SideStore dependencies
            openssl
            
            # Project tools
            xcodegen
          ];
          
          shellHook = ''
            echo "🦀 Rust + iOS Cross-Compilation Environment"
            echo "   rustc: $(rustc --version)"
            echo "   cargo: $(cargo --version)"
            echo "   cmake: $(cmake --version | head -1)"
            echo ""
            echo "iOS Targets installed:"
            rustup target list --installed | grep apple-ios || true
            echo ""
            echo "Build SideStore libs: ./scripts/build-sidestore-libs.sh"
            echo ""
          '';
        };

        formatter = pkgs.nixfmt;
      }
    );
}
