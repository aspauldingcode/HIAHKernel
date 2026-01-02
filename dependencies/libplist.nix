# libplist - iOS build
# Builds libplist for iOS Simulator and Device
# This is the first dependency in the libimobiledevice stack (no dependencies)

{ lib, pkgs, buildPackages, fetchFromGitHub, xcode }:

let
  xcodeUtils = import ./utils/xcode-wrapper.nix { inherit lib pkgs; };
  
  # Fetch from SideStore fork (has iOS patches)
  libplist-src = fetchFromGitHub {
    owner = "SideStore";
    repo = "libplist";
    rev = "master";
    sha256 = "0krgbb05dwkzsabrxqcgp3l107dswq0bv35bnxc8ab18m8ya8293";
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
      IOS_CXX="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
      IOS_AR="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/ar"
      IOS_RANLIB="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/ranlib"
    else
      IOS_CC="${buildPackages.clang}/bin/clang"
      IOS_CXX="${buildPackages.clang}/bin/clang++"
      IOS_AR="${buildPackages.binutils}/bin/ar"
      IOS_RANLIB="${buildPackages.binutils}/bin/ranlib"
    fi
    
    SIMULATOR_ARCH="arm64"
    if [ "$(uname -m)" = "x86_64" ]; then
      SIMULATOR_ARCH="x86_64"
    fi
    
    export CC="$IOS_CC"
    export CXX="$IOS_CXX"
    export AR="$IOS_AR"
    export RANLIB="$IOS_RANLIB"
    export CFLAGS="-arch $SIMULATOR_ARCH -isysroot $SDKROOT -mios-simulator-version-min=15.0 -fPIC"
    export CXXFLAGS="-arch $SIMULATOR_ARCH -isysroot $SDKROOT -mios-simulator-version-min=15.0 -fPIC"
    export LDFLAGS="-arch $SIMULATOR_ARCH -isysroot $SDKROOT -mios-simulator-version-min=15.0"
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
      IOS_CXX="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
      IOS_AR="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/ar"
      IOS_RANLIB="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/ranlib"
    else
      IOS_CC="${buildPackages.clang}/bin/clang"
      IOS_CXX="${buildPackages.clang}/bin/clang++"
      IOS_AR="${buildPackages.binutils}/bin/ar"
      IOS_RANLIB="${buildPackages.binutils}/bin/ranlib"
    fi
    
    export CC="$IOS_CC"
    export CXX="$IOS_CXX"
    export AR="$IOS_AR"
    export RANLIB="$IOS_RANLIB"
    export CFLAGS="-arch arm64 -isysroot $SDKROOT -miphoneos-version-min=15.0 -fPIC"
    export CXXFLAGS="-arch arm64 -isysroot $SDKROOT -miphoneos-version-min=15.0 -fPIC"
    export LDFLAGS="-arch arm64 -isysroot $SDKROOT -miphoneos-version-min=15.0"
  '';

  # Build for iOS Simulator
  ios-sim = pkgs.stdenv.mkDerivation {
    name = "libplist-ios-sim";
    version = "2.6.0";
    
    src = libplist-src;
    
    nativeBuildInputs = with buildPackages; [
      autoconf
      automake
      libtool
      pkg-config
    ];
    
    preConfigure = ''
      ${iosSimSetup}
      
      # Create version file (required for non-git builds)
      echo "2.6.0" > .tarball-version
      
      # Generate configure script
      NOCONFIGURE=1 ./autogen.sh || true
    '';
    
    configurePhase = ''
      runHook preConfigure
      ./configure \
        --prefix=$out \
        --host=arm-apple-darwin \
        --disable-shared \
        --enable-static \
        --without-cython
      runHook postConfigure
    '';
    
    buildPhase = ''
      runHook preBuild
      make -j$NIX_BUILD_CORES
      runHook postBuild
    '';
    
    installPhase = ''
      runHook preInstall
      make install
      runHook postInstall
    '';
    
    __noChroot = true;
  };
  
  # Build for iOS Device
  ios = pkgs.stdenv.mkDerivation {
    name = "libplist-ios";
    version = "2.6.0";
    
    src = libplist-src;
    
    nativeBuildInputs = with buildPackages; [
      autoconf
      automake
      libtool
      pkg-config
    ];
    
    preConfigure = ''
      ${iosDeviceSetup}
      
      # Create version file (required for non-git builds)
      echo "2.6.0" > .tarball-version
      
      NOCONFIGURE=1 ./autogen.sh || true
    '';
    
    configurePhase = ''
      runHook preConfigure
      ./configure \
        --prefix=$out \
        --host=arm-apple-darwin \
        --disable-shared \
        --enable-static \
        --without-cython
      runHook postConfigure
    '';
    
    buildPhase = ''
      runHook preBuild
      make -j$NIX_BUILD_CORES
      runHook postBuild
    '';
    
    installPhase = ''
      runHook preInstall
      make install
      runHook postInstall
    '';
    
    __noChroot = true;
  };

in {
  inherit ios-sim ios;
}
