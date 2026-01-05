# xcodegen.nix - Generate HIAHDesktop Xcode project with Nix-managed dependencies
#
# Usage via flake:
#   nix run .#xcgen
#
# Dependencies are imported from ./deps/*/ios.nix and their Nix store paths
# are interpolated into project.yml, making builds fully reproducible.

{
  pkgs,               # Nixpkgs with overlays (from flake)
  rustPlatform,       # Rust platform with iOS targets (from flake)
  xcode ? null,       # Xcode (from flake)
}:

let
  lib = pkgs.lib;
  buildPackages = pkgs.buildPackages;
  fetchFromGitHub = pkgs.fetchFromGitHub;
  
  # ============================================================================
  # Import all dependencies from deps/*/ios.nix
  # ============================================================================
  
  # Rust dependencies
  em-proxy = pkgs.callPackage ./deps/em-proxy/ios.nix {
    inherit rustPlatform lib fetchFromGitHub;
  };
  
  minimuxer = pkgs.callPackage ./deps/minimuxer/ios.nix {
    inherit rustPlatform lib fetchFromGitHub;
  };
  
  # Swift package dependencies
  roxas = pkgs.callPackage ./deps/roxas/ios.nix {
    inherit pkgs lib fetchFromGitHub;
  };
  
  altsign = pkgs.callPackage ./deps/altsign/ios.nix {
    inherit pkgs lib fetchFromGitHub;
  };
  
  # C library dependencies (return { ios-sim; ios; })
  openssl = import ./deps/openssl/ios.nix {
    inherit pkgs lib buildPackages xcode;
  };
  
  zsign = import ./deps/zsign/ios.nix {
    inherit pkgs lib xcode fetchFromGitHub;
    openssl = openssl;
  };
  
  libplist = import ./deps/libplist/ios.nix {
    inherit pkgs lib buildPackages xcode fetchFromGitHub;
  };
  
  libimobiledevice-glue = import ./deps/libimobiledevice-glue/ios.nix {
    inherit pkgs lib buildPackages xcode fetchFromGitHub;
    libplist = libplist;
  };
  
  libusbmuxd = import ./deps/libusbmuxd/ios.nix {
    inherit pkgs lib buildPackages xcode fetchFromGitHub;
    libplist = libplist;
    libimobiledevice-glue = libimobiledevice-glue;
  };
  
  libimobiledevice = import ./deps/libimobiledevice/ios.nix {
    inherit pkgs lib buildPackages xcode fetchFromGitHub;
    libplist = libplist;
    libimobiledevice-glue = libimobiledevice-glue;
    libusbmuxd = libusbmuxd;
  };

  # Generate project.yml content with all Nix store paths embedded
  projectYaml = ''
name: HIAHDesktop
options:
  bundleIdPrefix: com.aspauldingcode
  deploymentTarget:
    iOS: "16.0"
  developmentLanguage: en
  generateEmptyDirectories: true

schemes:
  HIAHDesktop:
    build:
      targets:
        HIAHDesktop: all
    run:
      config: Debug
    profile:
      config: Release
    analyze:
      config: Debug
    archive:
      config: Release

  HIAHKernel:
    build:
      targets:
        HIAHKernel: all
    run:
      config: Debug

settings:
  base:
    PRODUCT_NAME: HIAHDesktop
    MARKETING_VERSION: "1.0"
    CURRENT_PROJECT_VERSION: "1"
    DEVELOPMENT_TEAM: ""
    CODE_SIGN_STYLE: Automatic
    ENABLE_USER_SCRIPT_SANDBOXING: NO
    BUILD_LIBRARY_FOR_DISTRIBUTION: NO
    EXCLUDED_ARCHS[sdk=iphonesimulator*]: x86_64
    ENABLE_BITCODE: NO
    
    # Nix store dependency paths (Rust)
    EM_PROXY_PATH: ${em-proxy}
    MINIMUXER_PATH: ${minimuxer}
    
    # Nix store dependency paths (Swift)
    ROXAS_PATH: ${roxas}
    ALTSIGN_PATH: ${altsign}
    
    # Nix store dependency paths (C libraries - iOS Simulator)
    OPENSSL_SIM_PATH: ${openssl.ios-sim}
    ZSIGN_SIM_PATH: ${zsign.ios-sim}
    LIBPLIST_SIM_PATH: ${libplist.ios-sim}
    LIBIMOBILEDEVICE_GLUE_SIM_PATH: ${libimobiledevice-glue.ios-sim}
    LIBUSBMUXD_SIM_PATH: ${libusbmuxd.ios-sim}
    LIBIMOBILEDEVICE_SIM_PATH: ${libimobiledevice.ios-sim}
    
    # Nix store dependency paths (C libraries - iOS Device)
    OPENSSL_IOS_PATH: ${openssl.ios}
    ZSIGN_IOS_PATH: ${zsign.ios}
    LIBPLIST_IOS_PATH: ${libplist.ios}
    LIBIMOBILEDEVICE_GLUE_IOS_PATH: ${libimobiledevice-glue.ios}
    LIBUSBMUXD_IOS_PATH: ${libusbmuxd.ios}
    LIBIMOBILEDEVICE_IOS_PATH: ${libimobiledevice.ios}

  configs:
    Debug:
      ONLY_ACTIVE_ARCH: YES
      SWIFT_OPTIMIZATION_LEVEL: -Onone
      GCC_OPTIMIZATION_LEVEL: "0"
      SWIFT_COMPILATION_MODE: incremental

    Release:
      ONLY_ACTIVE_ARCH: NO
      SWIFT_OPTIMIZATION_LEVEL: -Osize
      SWIFT_WHOLE_MODULE_OPTIMIZATION: YES
      SWIFT_COMPILATION_MODE: wholemodule
      GCC_OPTIMIZATION_LEVEL: s
      DEAD_CODE_STRIPPING: YES
      STRIP_INSTALLED_PRODUCT: YES

targets:
  HIAHKernel:
    type: framework
    platform: iOS
    info:
      path: src/HIAHKernel/Info.plist
    dependencies:
      - framework: Security.framework
      - framework: Foundation.framework
    sources:
      - path: src/HIAHKernel/Public
        headerVisibility: public
      - path: src/HIAHKernel/Core
        headerVisibility: project
    settings:
      PRODUCT_NAME: HIAHKernel
      PRODUCT_BUNDLE_IDENTIFIER: com.aspauldingcode.HIAHKernel
      SKIP_INSTALL: YES
      MACH_O_TYPE: mh_dylib
      DEFINES_MODULE: NO
      CLANG_ENABLE_MODULES: NO
      CLANG_CXX_LANGUAGE_STANDARD: c++17
      HEADER_SEARCH_PATHS:
        - $(SRCROOT)/src/HIAHKernel/Public
        - $(SRCROOT)/src/HIAHKernel/Core
        - $(SRCROOT)/src/HIAHKernel/Core/Hooks
        - $(SRCROOT)/src/HIAHKernel/Core/Logging
        - $(SRCROOT)/src/HIAHKernel/Core/Utils
        - $(SRCROOT)/src/HIAHKernel/Core/Signing
        - ${openssl.ios-sim}/include
        - ${zsign.ios-sim}/include
        - ${zsign.ios-sim}/include/zsign
        - ${zsign.ios-sim}/include/zsign/common
        - ${libplist.ios-sim}/include
        - ${libimobiledevice-glue.ios-sim}/include
        - ${libusbmuxd.ios-sim}/include
        - ${libimobiledevice.ios-sim}/include
      LIBRARY_SEARCH_PATHS:
        - ${openssl.ios-sim}/lib
        - ${zsign.ios-sim}/lib
        - ${libplist.ios-sim}/lib
        - ${libimobiledevice-glue.ios-sim}/lib
        - ${libusbmuxd.ios-sim}/lib
        - ${libimobiledevice.ios-sim}/lib
      OTHER_LDFLAGS:
        - -lzsign
        - -lssl
        - -lcrypto
        - -lc++

  HIAHProcessRunner:
    type: app-extension
    platform: iOS
    info:
      path: src/extension/Info.plist
    dependencies:
      - target: HIAHKernel
        embed: false
        link: true
      - framework: Security.framework
      - framework: Foundation.framework
    sources:
      - path: src/extension
        excludes:
          - "*.plist"
      - path: src/HIAHKernel/Public
      - path: src/HIAHKernel/Core
      - path: src/TestSupport
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: com.aspauldingcode.HIAHDesktop.HIAHProcessRunner
      ENABLE_BITCODE: NO
      CODE_SIGN_ENTITLEMENTS: src/extension/Entitlements.plist
      CLANG_ENABLE_MODULES: NO
      CLANG_CXX_LANGUAGE_STANDARD: c++17
      HEADER_SEARCH_PATHS:
        - $(SRCROOT)/src/HIAHKernel/Public
        - $(SRCROOT)/src/HIAHKernel/Core
        - $(SRCROOT)/src/HIAHKernel/Core/Hooks
        - $(SRCROOT)/src/HIAHKernel/Core/Signing
        - $(SRCROOT)/src/HIAHKernel/Core/Utils
        - $(SRCROOT)/src/HIAHKernel/Core/Logging
        - $(SRCROOT)/src/TestSupport
        - ${zsign.ios-sim}/include
        - ${zsign.ios-sim}/include/zsign
        - ${zsign.ios-sim}/include/zsign/common
        - ${openssl.ios-sim}/include
      LIBRARY_SEARCH_PATHS:
        - ${zsign.ios-sim}/lib
        - ${openssl.ios-sim}/lib
      OTHER_LDFLAGS:
        - -lzsign
        - -lssl
        - -lcrypto
        - -lc++

  HIAHDesktop:
    type: application
    platform: iOS
    info:
      path: src/HIAHDesktop/Info.plist
    dependencies:
      - target: HIAHKernel
        embed: true
        link: true
      - target: HIAHProcessRunner
        embed: true
      - framework: UIKit.framework
      - framework: Foundation.framework
      - framework: CoreGraphics.framework
    sources:
      - path: src/HIAHDesktop
      - path: src/Config
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: com.aspauldingcode.HIAHDesktop
      CODE_SIGN_ENTITLEMENTS: src/HIAHDesktop/HIAHDesktop.entitlements
      CLANG_ENABLE_MODULES: NO
      HEADER_SEARCH_PATHS:
        - $(SRCROOT)/src/HIAHKernel/Public
        - $(SRCROOT)/src/Config

  HIAHTop:
    type: application
    platform: iOS
    info:
      path: src/HIAHTop/Info.plist
    dependencies:
      - target: HIAHKernel
        embed: true
        link: true
      - framework: UIKit.framework
      - framework: Foundation.framework
      - framework: CoreGraphics.framework
    sources:
      - path: src/HIAHTop
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: com.aspauldingcode.HIAHTop
      CLANG_ENABLE_MODULES: NO
      HEADER_SEARCH_PATHS:
        - $(SRCROOT)/src/HIAHKernel/Public
  '';

  projectYamlFile = pkgs.writeText "project.yml" projectYaml;

in pkgs.stdenv.mkDerivation {
  pname = "HIAHDesktopXcodeProject";
  version = "1.0.0";

  src = ./..;

  nativeBuildInputs = [ pkgs.xcodegen ];

  buildPhase = ''
    runHook preBuild
    
    echo "🎯 Generating Xcode project with XcodeGen..."
    echo ""
    echo "📦 Dependencies from Nix store:"
    echo "  Rust:"
    echo "    - em-proxy: ${em-proxy}"
    echo "    - minimuxer: ${minimuxer}"
    echo "  Swift:"
    echo "    - roxas: ${roxas}"
    echo "    - altsign: ${altsign}"
    echo "  C Libraries (iOS Simulator):"
    echo "    - openssl: ${openssl.ios-sim}"
    echo "    - zsign: ${zsign.ios-sim}"
    echo "    - libplist: ${libplist.ios-sim}"
    echo "    - libimobiledevice-glue: ${libimobiledevice-glue.ios-sim}"
    echo "    - libusbmuxd: ${libusbmuxd.ios-sim}"
    echo "    - libimobiledevice: ${libimobiledevice.ios-sim}"
    echo ""
    
    cp ${projectYamlFile} project.yml
    
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    
    # XcodeGen needs HOME and USER set
    export HOME="$TMPDIR"
    export USER="nobody"
    
    echo "📦 Running XcodeGen..."
    ${pkgs.xcodegen}/bin/xcodegen generate --spec project.yml
    
    mkdir -p $out
    cp project.yml $out/
    
    if [ -d "HIAHDesktop.xcodeproj" ]; then
      cp -r HIAHDesktop.xcodeproj $out/
      echo "✅ Xcode project generated: $out/HIAHDesktop.xcodeproj"
    else
      echo "❌ Error: HIAHDesktop.xcodeproj not found"
      exit 1
    fi
    
    runHook postInstall
  '';

  meta = with lib; {
    description = "HIAHDesktop Xcode project with Nix-managed dependencies";
    license = licenses.agpl3Plus;
    platforms = platforms.darwin;
  };
}
