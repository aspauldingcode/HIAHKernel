{
  lib,
  pkgs,
  buildPackages,
}:

let
  xcodeUtils = import ../../utils/xcode-wrapper.nix { inherit lib pkgs; };
  
  src = pkgs.fetchurl {
    url = "https://ftp.gnu.org/gnu/bash/bash-5.2.tar.gz";
    sha256 = "sha256-oTnBZt9/9EccXgczBRZC7lVWwcyKSnjxRVg8XIGrMvs=";
  };

in
pkgs.stdenv.mkDerivation {
  name = "bash-ios";
  inherit src;
  
  nativeBuildInputs = with buildPackages; [
    autoconf
    automake
    bison
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
      --without-bash-malloc \
      --disable-nls \
      --enable-static-link
    
    runHook postConfigure
  '';
  
  buildPhase = ''
    runHook preBuild
    make -j$NIX_BUILD_CORES
    runHook postBuild
  '';
  
  installPhase = ''
    runHook preInstall
    
    mkdir -p $out/bin
    cp bash $out/bin/bash
    chmod +x $out/bin/bash
    ln -s bash $out/bin/sh
    
    echo "✓ Installed bash for iOS"
    
    runHook postInstall
  '';
  
  __noChroot = true;
}

