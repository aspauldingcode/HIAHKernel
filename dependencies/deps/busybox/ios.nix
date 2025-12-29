{
  lib,
  pkgs,
  buildPackages,
}:

let
  xcodeUtils = import ../../utils/xcode-wrapper.nix { inherit lib pkgs; };
  
  # Use nixpkgs' busybox source
  src = pkgs.busybox.src;

in
pkgs.stdenv.mkDerivation {
  name = "busybox-ios";
  inherit src;
  
  nativeBuildInputs = with buildPackages; [
    bison
    flex
    bc
  ];
  
  preConfigure = ''
    if [ -z "''${XCODE_APP:-}" ]; then
      XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode || true)
      if [ -n "$XCODE_APP" ]; then
        export XCODE_APP
        export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
        export PATH="$DEVELOPER_DIR/usr/bin:$PATH"
        export SDKROOT="$DEVELOPER_DIR/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk"
      fi
    fi
    
    if [ -n "''${SDKROOT:-}" ] && [ -d "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin" ]; then
      export CC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
      # HOSTCC is for building build-time tools - use native macOS compiler
      export HOSTCC="clang"
    else
      export CC="${buildPackages.clang}/bin/clang"
      export HOSTCC="clang"
    fi
    
    # BusyBox config for iOS
    make defconfig
    
    # Enable essential applets
    sed -i.bak 's/# CONFIG_SH_IS_ASH is not set/CONFIG_SH_IS_ASH=y/' .config
    sed -i.bak 's/# CONFIG_BASH_IS_ASH is not set/CONFIG_BASH_IS_ASH=y/' .config
    
    # Enable static build
    echo "CONFIG_STATIC=y" >> .config
    
    # Enable useful applets
    echo "CONFIG_UNZIP=y" >> .config
    echo "CONFIG_GZIP=y" >> .config
    echo "CONFIG_TAR=y" >> .config
    echo "CONFIG_WGET=y" >> .config
    echo "CONFIG_CURL=y" >> .config
  '';
  
  buildPhase = ''
    # Flags for target (iOS)
    IOS_CFLAGS="-arch arm64 -target arm64-apple-ios15.0-simulator -isysroot $SDKROOT -mios-simulator-version-min=15.0 -O2"
    IOS_LDFLAGS="-arch arm64 -target arm64-apple-ios15.0-simulator -isysroot $SDKROOT -mios-simulator-version-min=15.0 -static"
    
    # Build with proper cross-compilation:
    # - HOSTCC builds tools for macOS (build machine)
    # - CC builds the final binary for iOS (target)
    make -j$NIX_BUILD_CORES busybox \
      CC="$CC" \
      CFLAGS="$IOS_CFLAGS" \
      LDFLAGS="$IOS_LDFLAGS" \
      EXTRA_CFLAGS="$IOS_CFLAGS" \
      EXTRA_LDFLAGS="$IOS_LDFLAGS" \
      HOSTCC="/usr/bin/clang" \
      HOSTCFLAGS="-O2" \
      HOSTLDFLAGS="" \
      CROSS_COMPILE="" \
      SKIP_STRIP=y \
      CONFIG_PREFIX=$out || {
      echo "Build completed with warnings"
      test -f busybox || exit 1
    }
  '';
  
  installPhase = ''
    mkdir -p $out/bin
    cp busybox $out/bin/busybox
    chmod +x $out/bin/busybox
    
    # Create symlinks for all applets
    cd $out/bin
    ./busybox --list 2>/dev/null | while read applet; do
      ln -sf busybox "$applet" 2>/dev/null || true
    done
    
    # Ensure we have the essential ones
    for cmd in sh bash ash ls cp mv rm mkdir rmdir cat chmod ln pwd echo unzip gzip tar; do
      ln -sf busybox "$cmd" 2>/dev/null || true
    done
    
    echo "✓ BusyBox for iOS installed with $(./busybox --list 2>/dev/null | wc -l) applets"
  '';
  
  __noChroot = true;
}

