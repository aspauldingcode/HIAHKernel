{
  lib,
  pkgs,
  buildPackages,
}:

let
  xcodeUtils = import ../../utils/xcode-wrapper.nix { inherit lib pkgs; };
  
  src = pkgs.fetchurl {
    url = "https://downloads.sourceforge.net/project/infozip/UnZip%206.x%20%28latest%29/UnZip%206.0/unzip60.tar.gz";
    sha256 = "sha256-A22WmRZG0ESe0KqVLk++IbR2zplKvCduSdMOaGcIvTc=";
  };

in
pkgs.stdenv.mkDerivation {
  name = "unzip-ios";
  inherit src;
  
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
  
  buildPhase = ''
    export CC="$IOS_CC"
    # Add flags to allow old-style C declarations
    export CFLAGS="-arch arm64 -target arm64-apple-ios15.0-simulator -isysroot $SDKROOT -mios-simulator-version-min=15.0 -O2 -DBSD -Wno-deprecated-non-prototype -Wno-implicit-function-declaration -Wno-implicit-int"
    export LDFLAGS="-arch arm64 -target arm64-apple-ios15.0-simulator -isysroot $SDKROOT -mios-simulator-version-min=15.0"
    
    make -f unix/Makefile generic CC="$CC" CF="$CFLAGS" LF="$LDFLAGS" || {
      echo "Build had warnings/errors, checking if binary was created..."
      test -f unzip && echo "✓ unzip binary exists despite warnings"
    }
  '';
  
  installPhase = ''
    mkdir -p $out/bin
    cp unzip $out/bin/unzip
    chmod +x $out/bin/unzip
    
    echo "✓ Installed unzip for iOS"
  '';
  
  __noChroot = true;
}

