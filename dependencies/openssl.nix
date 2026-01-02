# OpenSSL - iOS build
# Builds OpenSSL for iOS Simulator and Device
# Used by zsign for full code signing functionality (like LiveContainer)

{ lib, pkgs, buildPackages, xcode }:

let
  xcodeUtils = import ./utils/xcode-wrapper.nix { inherit lib pkgs; };
  
  # OpenSSL 3.3.0 (stable, widely used)
  openssl-src = pkgs.fetchurl {
    url = "https://www.openssl.org/source/openssl-3.3.0.tar.gz";
    sha256 = "sha256-00pv30xs7hrmvx19gsrzl5zs6cz0l2cpczh8y2mhd9i26c26prjk=";
  };
  
  # Common iOS cross-compilation setup for Simulator
  iosSimSetup = ''
    if [ -z "''${XCODE_APP:-}" ]; then
      XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode || true)
      if [ -n "$XCODE_APP" ]; then
        export XCODE_APP
        export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
        export PATH="$DEVELOPER_DIR/usr/bin:$PATH"
        export SDKROOT="$DEVELOPER_DIR/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk"
      fi
    fi
    
    export NIX_CFLAGS_COMPILE=""
    export NIX_CXXFLAGS_COMPILE=""
    
    if [ -n "''${SDKROOT:-}" ] && [ -d "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin" ]; then
      IOS_CC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
      IOS_AR="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/ar"
      IOS_RANLIB="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/ranlib"
    else
      IOS_CC="${buildPackages.clang}/bin/clang"
      IOS_AR="${buildPackages.binutils}/bin/ar"
      IOS_RANLIB="${buildPackages.binutils}/bin/ranlib"
    fi
    
    SIMULATOR_ARCH="arm64"
    if [ "$(uname -m)" = "x86_64" ]; then
      SIMULATOR_ARCH="x86_64"
    fi
    
    # OpenSSL Configure script needs these specific environment variables
    export CC="$IOS_CC"
    export AR="$IOS_AR"
    export RANLIB="$IOS_RANLIB"
    export CROSS_TOP="$DEVELOPER_DIR/Platforms/iPhoneSimulator.platform/Developer"
    export CROSS_SDK="iPhoneSimulator.sdk"
    export CROSS_COMPILE=""
    
    # For simulator, use iossimulator64-cross target (works for both arm64 and x86_64 simulators)
    # OpenSSL's iossimulator64-cross handles both architectures
    OPENSSL_TARGET="iossimulator64-cross"
  '';
  
  # iOS Device build setup
  iosDeviceSetup = ''
    if [ -z "''${XCODE_APP:-}" ]; then
      XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode || true)
      if [ -n "$XCODE_APP" ]; then
        export XCODE_APP
        export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
        export PATH="$DEVELOPER_DIR/usr/bin:$PATH"
        export SDKROOT="$DEVELOPER_DIR/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
      fi
    fi
    
    export NIX_CFLAGS_COMPILE=""
    export NIX_CXXFLAGS_COMPILE=""
    
    if [ -n "''${SDKROOT:-}" ] && [ -d "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin" ]; then
      IOS_CC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
      IOS_AR="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/ar"
      IOS_RANLIB="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/ranlib"
    else
      IOS_CC="${buildPackages.clang}/bin/clang"
      IOS_AR="${buildPackages.binutils}/bin/ar"
      IOS_RANLIB="${buildPackages.binutils}/bin/ranlib"
    fi
    
    # OpenSSL Configure script needs these specific environment variables
    export CC="$IOS_CC"
    export AR="$IOS_AR"
    export RANLIB="$IOS_RANLIB"
    export CROSS_TOP="$DEVELOPER_DIR/Platforms/iPhoneOS.platform/Developer"
    export CROSS_SDK="iPhoneOS.sdk"
    export CROSS_COMPILE=""
    
    # For device, use ios64-cross target (arm64)
    OPENSSL_TARGET="ios64-cross"
  '';

  # Build for iOS Simulator
  ios-sim = pkgs.stdenv.mkDerivation {
    name = "openssl-ios-sim";
    version = "3.3.0";
    
    src = openssl-src;
    
    nativeBuildInputs = with buildPackages; [
      perl
      gnumake
    ];
    
    preConfigure = ''
      ${iosSimSetup}
    '';
    
    configurePhase = ''
      runHook preConfigure
      
      echo "Configuring OpenSSL for iOS Simulator ($OPENSSL_TARGET)..."
      echo "  CC=$CC"
      echo "  CROSS_TOP=$CROSS_TOP"
      echo "  CROSS_SDK=$CROSS_SDK"
      echo "  SDKROOT=$SDKROOT"
      
      # OpenSSL uses its own Configure script (not autotools)
      # The Configure script expects specific environment variables (CROSS_TOP, CROSS_SDK)
      ./Configure "$OPENSSL_TARGET" \
        --prefix="$out" \
        --openssldir="$out/ssl" \
        no-shared \
        no-dso \
        no-hw \
        no-engine \
        no-tests \
        -fPIC \
        --cross-compile-prefix=""
      
      runHook postConfigure
    '';
    
    buildPhase = ''
      runHook preBuild
      
      echo "Building OpenSSL for iOS Simulator..."
      # OpenSSL uses 'make' (not 'make install' for cross-compilation)
      ${buildPackages.gnumake}/bin/make -j''${NIX_BUILD_CORES:-1}
      
      runHook postBuild
    '';
    
    installPhase = ''
      runHook preInstall
      
      # OpenSSL's make install doesn't work well for cross-compilation
      # Install manually - stage headers and libraries only (no source)
      mkdir -p "$out/lib" "$out/include/openssl"
      
      # Install static libraries
      if [ -f libcrypto.a ]; then
        cp libcrypto.a $out/lib/
        echo "  ✅ Installed libcrypto.a"
      fi
      if [ -f libssl.a ]; then
        cp libssl.a $out/lib/
        echo "  ✅ Installed libssl.a"
      fi
      
      # Install headers (OpenSSL headers are in include/openssl/)
      if [ -d include/openssl ]; then
        cp -r include/openssl/* $out/include/openssl/
        echo "  ✅ Installed OpenSSL headers"
      fi
      
      runHook postInstall
    '';
    
    __noChroot = true;
  };
  
  # Build for iOS Device
  ios = pkgs.stdenv.mkDerivation {
    name = "openssl-ios";
    version = "3.3.0";
    
    src = openssl-src;
    
    nativeBuildInputs = with buildPackages; [
      perl
      gnumake
    ];
    
    preConfigure = ''
      ${iosDeviceSetup}
      
      # Extract source if it's a tarball
      if [ ! -f Configure ]; then
        tar -xzf $src || true
        cd openssl-* || cd .
      fi
    '';
    
    configurePhase = ''
      runHook preConfigure
      
      echo "Configuring OpenSSL for iOS Device: $OPENSSL_TARGET"
      
      # OpenSSL uses its own Configure script (not autotools)
      ./Configure "$OPENSSL_TARGET" \
        --prefix="$out" \
        --openssldir="$out/ssl" \
        no-shared \
        no-dso \
        no-hw \
        no-engine \
        no-tests \
        -fPIC
      
      runHook postConfigure
    '';
    
    buildPhase = ''
      runHook preBuild
      
      echo "Building OpenSSL for iOS Device..."
      ${buildPackages.gnumake}/bin/make -j''${NIX_BUILD_CORES:-1}
      
      runHook postBuild
    '';
    
    installPhase = ''
      runHook preInstall
      
      # OpenSSL's make install doesn't work well for cross-compilation
      # Install manually - stage headers and libraries only (no source)
      mkdir -p "$out/lib" "$out/include/openssl"
      
      # Install static libraries
      if [ -f libcrypto.a ]; then
        cp libcrypto.a $out/lib/
        echo "  ✅ Installed libcrypto.a"
      fi
      if [ -f libssl.a ]; then
        cp libssl.a $out/lib/
        echo "  ✅ Installed libssl.a"
      fi
      
      # Install headers (OpenSSL headers are in include/openssl/)
      if [ -d include/openssl ]; then
        cp -r include/openssl/* $out/include/openssl/
        echo "  ✅ Installed OpenSSL headers"
      fi
      
      runHook postInstall
    '';
    
    __noChroot = true;
  };

in {
  inherit ios-sim ios;
}
