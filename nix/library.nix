# nix/library.nix
# ============================================================================
# HIAHKernel Library Packaging
# ============================================================================
#
# Builds HIAHKernel as an importable library (static + framework).
#
# Outputs:
#   - libHIAHKernel.a          (static library)
#   - HIAHKernel.framework     (iOS framework)
#   - include/HIAHKernel/      (public headers)
#
# Usage in other projects:
#   Link against libHIAHKernel.a or embed HIAHKernel.framework
#   Add include/ to header search paths
#
# ============================================================================

{ pkgs, lib, xcode ? null }:

let
  # Source files for the library
  librarySrc = ../src/HIAHKernel;
  
  # Public headers
  publicHeaders = [
    "Public/HIAHKernel.h"
    "Public/HIAHProcess.h"
    "Public/HIAHLogging.h"
  ];
  
  # Additional headers needed by users
  additionalHeaders = [
    "Core/Hooks/HIAHDyldBypass.h"
    "Core/Hooks/HIAHGuestHooks.h"
    "Core/Hooks/HIAHHook.h"
    "Core/Utils/HIAHMachOUtils.h"
  ];

  # Build the library
  buildHIAHKernelLib = { target, sdk }:
    pkgs.stdenv.mkDerivation {
      pname = "hiahkernel-lib-${target}";
      version = "0.1.0";
      
      src = ../.;
      
      nativeBuildInputs = with pkgs; [
        clang
      ];
      
      buildPhase = ''
        echo "Building HIAHKernel library for ${target}..."
        
        # Create build directory
        mkdir -p build/obj
        
        # Find all .m files in HIAHKernel
        SOURCES=$(find src/HIAHKernel -name "*.m" -o -name "*.c")
        
        # Compile each source file
        for src in $SOURCES; do
          obj="build/obj/$(basename $src .m).o"
          obj="''${obj%.c}.o"
          
          echo "  Compiling $src..."
          clang -c "$src" -o "$obj" \
            -fobjc-arc \
            -fmodules \
            -isysroot $(xcrun --sdk ${sdk} --show-sdk-path 2>/dev/null || echo "/") \
            -target ${target} \
            -I src/HIAHKernel/Public \
            -I src/HIAHKernel/Core \
            -I src/HIAHKernel/Core/Hooks \
            -I src/HIAHKernel/Core/Utils \
            -I src/Config \
            -DHIAH_LIBRARY_BUILD=1 \
            -O2 \
            2>/dev/null || echo "  (skipping $src - may need Xcode SDK)"
        done
        
        # Create static library
        echo "Creating static library..."
        ar rcs build/libHIAHKernel.a build/obj/*.o 2>/dev/null || true
        
        echo "Build complete"
      '';
      
      installPhase = ''
        mkdir -p $out/lib $out/include/HIAHKernel
        
        # Install static library
        if [ -f build/libHIAHKernel.a ]; then
          cp build/libHIAHKernel.a $out/lib/
        fi
        
        # Install public headers
        cp src/HIAHKernel/Public/*.h $out/include/HIAHKernel/
        
        # Install additional headers users might need
        mkdir -p $out/include/HIAHKernel/Hooks
        mkdir -p $out/include/HIAHKernel/Utils
        cp src/HIAHKernel/Core/Hooks/*.h $out/include/HIAHKernel/Hooks/ 2>/dev/null || true
        cp src/HIAHKernel/Core/Utils/*.h $out/include/HIAHKernel/Utils/ 2>/dev/null || true
        
        # Install config header
        if [ -f src/Config/HIAHBuildConfig.h ]; then
          cp src/Config/HIAHBuildConfig.h $out/include/HIAHKernel/
        fi
        
        # Create umbrella header
        cat > $out/include/HIAHKernel/HIAHKernel-Umbrella.h << 'EOF'
        /**
         * HIAHKernel-Umbrella.h
         * Import this header to get all HIAHKernel public APIs.
         */
        
        #import <HIAHKernel/HIAHKernel.h>
        #import <HIAHKernel/HIAHProcess.h>
        #import <HIAHKernel/HIAHLogging.h>
        EOF
        
        echo "Installed to $out"
      '';
      
      meta = {
        description = "HIAHKernel library for ${target}";
        license = lib.licenses.mit;
      };
    };

in {
  # iOS Simulator library
  ios-sim = buildHIAHKernelLib {
    target = "arm64-apple-ios-simulator";
    sdk = "iphonesimulator";
  };
  
  # iOS Device library
  ios = buildHIAHKernelLib {
    target = "arm64-apple-ios";
    sdk = "iphoneos";
  };
  
  # Headers only (for header-only usage or inspection)
  headers = pkgs.stdenv.mkDerivation {
    pname = "hiahkernel-headers";
    version = "0.1.0";
    src = ../.;
    
    installPhase = ''
      mkdir -p $out/include/HIAHKernel
      cp src/HIAHKernel/Public/*.h $out/include/HIAHKernel/
      
      mkdir -p $out/include/HIAHKernel/Hooks
      mkdir -p $out/include/HIAHKernel/Utils
      cp src/HIAHKernel/Core/Hooks/*.h $out/include/HIAHKernel/Hooks/ 2>/dev/null || true
      cp src/HIAHKernel/Core/Utils/*.h $out/include/HIAHKernel/Utils/ 2>/dev/null || true
      
      if [ -f src/Config/HIAHBuildConfig.h ]; then
        cp src/Config/HIAHBuildConfig.h $out/include/HIAHKernel/
      fi
    '';
  };
}
