{
  lib,
  pkgs,
  buildPackages,
}:

let
  xcodeUtils = import ../../utils/xcode-wrapper.nix { inherit lib pkgs; };
  
  src = pkgs.fetchurl {
    url = "https://ftp.gnu.org/gnu/coreutils/coreutils-9.4.tar.xz";
    sha256 = "sha256-6mE6TPRGEjJukXIBu7zfvTAd4h/8O1m25cB+BAsnXlI=";
  };

in
pkgs.stdenv.mkDerivation {
  name = "coreutils-ios";
  inherit src;
  
  nativeBuildInputs = with buildPackages; [
    autoconf
    automake
    libtool
    pkg-config
    perl
    texinfo
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
      IOS_CC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
    else
      IOS_CC="${buildPackages.clang}/bin/clang"
    fi
  '';
  
  configurePhase = ''
    runHook preConfigure
    
    export CC="$IOS_CC"
    export CFLAGS="-arch arm64 -target arm64-apple-ios15.0-simulator -isysroot $SDKROOT -mios-simulator-version-min=15.0 -O2"
    export LDFLAGS="-arch arm64 -target arm64-apple-ios15.0-simulator -isysroot $SDKROOT -mios-simulator-version-min=15.0"
    
    ./configure \
      --prefix=$out \
      --host=arm64-apple-ios \
      --disable-nls \
      --disable-year2038 \
      --enable-single-binary=symlinks
    
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
    
    # Verify binaries
    echo "Installed coreutils:"
    ls -la $out/bin/ | head -20
    
    runHook postInstall
  '';
  
  __noChroot = true;
}

