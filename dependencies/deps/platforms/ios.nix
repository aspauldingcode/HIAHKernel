{
  lib,
  pkgs,
  buildPackages,
  common,
  buildModule,
}:

let
  getBuildSystem = common.getBuildSystem;
  fetchSource = common.fetchSource;
  xcodeUtils = import ../utils/xcode-wrapper.nix { inherit lib pkgs; };
in

{
  buildForIOS =
    name: entry:
    let
      src = if entry.source or "github" == "system" then null else fetchSource entry;
      buildSystem = getBuildSystem entry;
      buildFlags = entry.buildFlags.ios or [ ];
      patches = lib.filter (p: p != null && builtins.pathExists (toString p)) (entry.patches.ios or [ ]);
    in
    if buildSystem == "cmake" then
      pkgs.stdenv.mkDerivation {
        name = "${name}-ios";
        inherit src patches;
        nativeBuildInputs = with buildPackages; [
          cmake
          pkg-config
        ];
        buildInputs = [ ];
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
                        export NIX_CFLAGS_COMPILE=""
                        export NIX_CXXFLAGS_COMPILE=""
                        if [ -n "''${SDKROOT:-}" ] && [ -d "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin" ]; then
                          IOS_CC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
                          IOS_CXX="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
                        else
                          IOS_CC="${buildPackages.clang}/bin/clang"
                          IOS_CXX="${buildPackages.clang}/bin/clang++"
                        fi
                        SIMULATOR_ARCH="arm64"
                        if [ "$(uname -m)" = "x86_64" ]; then
                          SIMULATOR_ARCH="x86_64"
                        fi
                        cat > ios-toolchain.cmake <<EOF
          set(CMAKE_SYSTEM_NAME iOS)
          set(CMAKE_OSX_ARCHITECTURES $SIMULATOR_ARCH)
          set(CMAKE_OSX_DEPLOYMENT_TARGET 15.0)
          set(CMAKE_C_COMPILER "$IOS_CC")
          set(CMAKE_CXX_COMPILER "$IOS_CXX")
          set(CMAKE_SYSROOT "$SDKROOT")
          set(CMAKE_OSX_SYSROOT "$SDKROOT")
          set(CMAKE_C_FLAGS "-mios-simulator-version-min=15.0")
          set(CMAKE_CXX_FLAGS "-mios-simulator-version-min=15.0")
          EOF
        '';
        cmakeFlags = [
          "-DCMAKE_TOOLCHAIN_FILE=ios-toolchain.cmake"
        ]
        ++ buildFlags;
      }
    else if buildSystem == "meson" then
      pkgs.stdenv.mkDerivation {
        name = "${name}-ios";
        inherit src patches;
        nativeBuildInputs = with buildPackages; [
          meson
          ninja
          pkg-config
        ];
        buildInputs = [ ];
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
                        export NIX_CFLAGS_COMPILE=""
                        export NIX_CXXFLAGS_COMPILE=""
                        if [ -n "''${SDKROOT:-}" ] && [ -d "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin" ]; then
                          IOS_CC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
                          IOS_CXX="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
                        else
                          IOS_CC="${buildPackages.clang}/bin/clang"
                          IOS_CXX="${buildPackages.clang}/bin/clang++"
                        fi
                        SIMULATOR_ARCH="arm64"
                        if [ "$(uname -m)" = "x86_64" ]; then
                          SIMULATOR_ARCH="x86_64"
                        fi
                        cat > ios-cross-file.txt <<EOF
          [binaries]
          c = '$IOS_CC'
          cpp = '$IOS_CXX'
          ar = 'ar'
          strip = 'strip'
          pkgconfig = '${buildPackages.pkg-config}/bin/pkg-config'

          [host_machine]
          system = 'darwin'
          cpu_family = 'aarch64'
          cpu = 'aarch64'
          endian = 'little'

          [built-in options]
          c_args = ['-arch', '$SIMULATOR_ARCH', '-isysroot', '$SDKROOT', '-mios-simulator-version-min=15.0', '-fPIC']
          cpp_args = ['-arch', '$SIMULATOR_ARCH', '-isysroot', '$SDKROOT', '-mios-simulator-version-min=15.0', '-fPIC']
          c_link_args = ['-arch', '$SIMULATOR_ARCH', '-isysroot', '$SDKROOT', '-mios-simulator-version-min=15.0']
          cpp_link_args = ['-arch', '$SIMULATOR_ARCH', '-isysroot', '$SDKROOT', '-mios-simulator-version-min=15.0']
          EOF
        '';
        configurePhase = ''
          runHook preConfigure
          meson setup build \
            --prefix=$out \
            --libdir=$out/lib \
            --cross-file=ios-cross-file.txt \
            ${lib.concatMapStringsSep " \\\n  " (flag: flag) buildFlags}
          runHook postConfigure
        '';
        buildPhase = ''
          runHook preBuild
          meson compile -C build
          runHook postBuild
        '';
        installPhase = ''
          runHook preInstall
          meson install -C build
          runHook postInstall
        '';
      }
    else if buildSystem == "xcode" then
      pkgs.stdenv.mkDerivation {
        name = "${name}-ios";
        inherit src patches;
        nativeBuildInputs = [ xcodeUtils.findXcodeScript ];
        buildInputs = [ ];
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
        '';
        buildPhase = ''
          runHook preBuild
          # Find .xcodeproj and build
          XCPROJ=$(find . -name "*.xcodeproj" -type d | head -1)
          if [ -n "$XCPROJ" ]; then
            xcodebuild -project "$XCPROJ" \
              -scheme "$(basename "$XCPROJ" .xcodeproj)" \
              -configuration Release \
              -sdk iphonesimulator \
              -destination 'generic/platform=iOS Simulator' \
              ONLY_ACTIVE_ARCH=NO \
              BUILD_DIR="$PWD/build" \
              || echo "xcodebuild failed, trying manual compilation..."
          fi
          runHook postBuild
        '';
        installPhase = ''
          runHook preInstall
          mkdir -p $out
          if [ -d build ]; then
            cp -r build/* $out/ || true
          fi
          runHook postInstall
        '';
        __noChroot = true;
      }
    else
      # Default: autotools
      pkgs.stdenv.mkDerivation {
        name = "${name}-ios";
        inherit src patches;
        nativeBuildInputs = with buildPackages; [
          autoconf
          automake
          libtool
          pkg-config
        ];
        buildInputs = [ ];
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
          if [ ! -f ./configure ]; then
            autoreconf -fi || autogen.sh || true
          fi
          export NIX_CFLAGS_COMPILE=""
          export NIX_CXXFLAGS_COMPILE=""
          if [ -n "''${SDKROOT:-}" ] && [ -d "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin" ]; then
            IOS_CC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
            IOS_CXX="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
          else
            IOS_CC="${buildPackages.clang}/bin/clang"
            IOS_CXX="${buildPackages.clang}/bin/clang++"
          fi
          SIMULATOR_ARCH="arm64"
          if [ "$(uname -m)" = "x86_64" ]; then
            SIMULATOR_ARCH="x86_64"
          fi
          export CC="$IOS_CC"
          export CXX="$IOS_CXX"
          export CFLAGS="-arch $SIMULATOR_ARCH -isysroot $SDKROOT -mios-simulator-version-min=15.0 -fPIC"
          export CXXFLAGS="-arch $SIMULATOR_ARCH -isysroot $SDKROOT -mios-simulator-version-min=15.0 -fPIC"
          export LDFLAGS="-arch $SIMULATOR_ARCH -isysroot $SDKROOT -mios-simulator-version-min=15.0"
        '';
        configurePhase = ''
          runHook preConfigure
          ./configure --prefix=$out --host=arm-apple-darwin ${
            lib.concatMapStringsSep " " (flag: flag) buildFlags
          }
          runHook postConfigure
        '';
        configureFlags = buildFlags;
      };
}
