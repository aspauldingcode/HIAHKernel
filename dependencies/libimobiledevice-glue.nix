# libimobiledevice-glue - iOS build
# Builds libimobiledevice-glue for iOS Simulator and Device
# Depends on: libplist

{ lib, pkgs, buildPackages, fetchFromGitHub, xcode, libplist }:

let
  xcodeUtils = import ./utils/xcode-wrapper.nix { inherit lib pkgs; };
  
  # Fetch from upstream (libimobiledevice-glue doesn't have a SideStore fork)
  libimobiledevice-glue-src = fetchFromGitHub {
    owner = "libimobiledevice";
    repo = "libimobiledevice-glue";
    rev = "master";
    sha256 = "1ilh107y0nx38nf48cmrdccni707ghkfn8psi0hnmv2dgwr871y4";
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
    name = "libimobiledevice-glue-ios-sim";
    version = "1.3.1";
    
    src = libimobiledevice-glue-src;
    
    nativeBuildInputs = with buildPackages; [
      autoconf
      automake
      libtool
      pkg-config
    ];
    
    preConfigure = ''
      ${iosSimSetup}
      
      # Create version file
      echo "1.3.1" > .tarball-version
      
      # Link against libplist
      export PKG_CONFIG_PATH="${libplist.ios-sim}/lib/pkgconfig:$PKG_CONFIG_PATH"
      export CFLAGS="$CFLAGS -I${libplist.ios-sim}/include"
      export LDFLAGS="$LDFLAGS -L${libplist.ios-sim}/lib"
      
      NOCONFIGURE=1 ./autogen.sh || true
    '';
    
    configurePhase = ''
      runHook preConfigure
      ./configure \
        --prefix=$out \
        --host=arm-apple-darwin \
        --disable-shared \
        --enable-static
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
    name = "libimobiledevice-glue-ios";
    version = "1.3.1";
    
    src = libimobiledevice-glue-src;
    
    nativeBuildInputs = with buildPackages; [
      autoconf
      automake
      libtool
      pkg-config
    ];
    
    preConfigure = ''
      ${iosDeviceSetup}
      
      # Create version file
      echo "1.3.1" > .tarball-version
      
      # Link against libplist
      export PKG_CONFIG_PATH="${libplist.ios}/lib/pkgconfig:$PKG_CONFIG_PATH"
      export CFLAGS="$CFLAGS -I${libplist.ios}/include"
      export LDFLAGS="$LDFLAGS -L${libplist.ios}/lib"
      
      NOCONFIGURE=1 ./autogen.sh || true
    '';
    
    configurePhase = ''
      runHook preConfigure
      ./configure \
        --prefix=$out \
        --host=arm-apple-darwin \
        --disable-shared \
        --enable-static
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
