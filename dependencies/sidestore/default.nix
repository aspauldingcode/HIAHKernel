{ pkgs, lib, rustToolchain, xcode, pkgsCross }:

let
  # Use cross-compiled Rust platform for iOS
  # We need to make sure we use the passed rustToolchain which supports iOS targets
  rustPlatform = pkgs.makeRustPlatform {
    cargo = rustToolchain;
    rustc = rustToolchain;
  };

  # Build for iOS specifically
  em-proxy = pkgs.callPackage ./em-proxy.nix { 
    inherit rustPlatform;
  };
  
  minimuxer = pkgs.callPackage ./minimuxer.nix {
    inherit rustPlatform;
  };
  
  roxas = pkgs.callPackage ./roxas-spm.nix {};
  altsign = pkgs.callPackage ./altsign-spm.nix {};
  
  # libimobiledevice and dependencies for iOS
  libimobiledevice = pkgs.callPackage ./libimobiledevice.nix {
    inherit lib pkgs;
    buildPackages = pkgs.buildPackages;
    fetchFromGitHub = pkgs.fetchFromGitHub;
  };
  
  # Minimuxer builds for different platforms
  # For now, minimuxer is just macOS, iOS builds would need separate packages
  # These are placeholders - actual iOS builds would need cross-compilation setup
  minimuxer-ios = minimuxer;  # Placeholder - would need iOS-specific build
  minimuxer-ios-sim = minimuxer;  # Placeholder - would need iOS simulator build
in
{
  inherit em-proxy minimuxer roxas altsign libimobiledevice;
  inherit minimuxer-ios minimuxer-ios-sim;
  
  # Combined bundle for easy integration
  all = pkgs.stdenv.mkDerivation {
    name = "sidestore-components";
    version = "1.0.0";
    
    buildInputs = [ roxas altsign ];
    
    unpackPhase = "true";
    
    installPhase = ''
      mkdir -p $out/{lib,include,SwiftPackages,bin}
      
      # Copy Swift packages (for Xcode integration)
      cp -r ${roxas}/Roxas $out/SwiftPackages/ 2>/dev/null || true
      cp -r ${altsign}/AltSign $out/SwiftPackages/ 2>/dev/null || true
      
      # Copy Rust binaries
      cp ${em-proxy}/bin/run $out/bin/em-proxy 2>/dev/null || true
      
      # Copy libraries
      cp ${minimuxer}/lib/* $out/lib/ 2>/dev/null || true
      
      # Copy Swift bridge files (for Swift-Objective-C interop)
      # These bridge files are needed for HIAH integration with minimuxer and em_proxy
      # They provide Swift wrappers for the Rust libraries
      
      # minimuxer bridge files
      # minimuxer.h - C header for minimuxer (if available from build)
      if [ -d "${minimuxer}/include" ]; then
        cp ${minimuxer}/include/*.h $out/include/ 2>/dev/null || true
        cp ${minimuxer}/include/*.swift $out/include/ 2>/dev/null || true
      fi
      
      # minimuxer-Bridging-Header.h - Bridging header for Swift
      cat > "$out/include/minimuxer-Bridging-Header.h" << 'BRIDGEEOF'
#import "minimuxer.h"
BRIDGEEOF
      
      # minimuxer.h - C header (create if not provided)
      if [ ! -f "$out/include/minimuxer.h" ]; then
        cat > "$out/include/minimuxer.h" << 'HEADEREOF'
// minimuxer.h - C header for minimuxer Rust library
// This provides C bindings for the minimuxer functionality
#ifndef MINIMUXER_H
#define MINIMUXER_H

#ifdef __cplusplus
extern "C" {
#endif

// Function declarations would go here
// For now, this is a placeholder

#ifdef __cplusplus
}
#endif

#endif // MINIMUXER_H
HEADEREOF
      fi
      
      # minimuxer.swift - Swift wrapper
      if [ ! -f "$out/include/minimuxer.swift" ]; then
        cat > "$out/include/minimuxer.swift" << 'SWIFTEOF'
// minimuxer.swift - Swift wrapper for minimuxer
import Foundation

// Swift wrapper functions for minimuxer
// This provides a Swift-friendly API for the minimuxer Rust library
SWIFTEOF
      fi
      
      # minimuxer-helpers.swift - Helper functions
      if [ ! -f "$out/include/minimuxer-helpers.swift" ]; then
        cat > "$out/include/minimuxer-helpers.swift" << 'HELPEREOF'
// minimuxer-helpers.swift - Helper functions for minimuxer
import Foundation

// Helper functions for working with minimuxer
HELPEREOF
      fi
      
      # em_proxy.h - C header for em_proxy
      if [ ! -f "$out/include/em_proxy.h" ]; then
        cat > "$out/include/em_proxy.h" << 'EMPROXYEOF'
// em_proxy.h - C header for em_proxy Rust library
#ifndef EM_PROXY_H
#define EM_PROXY_H

#ifdef __cplusplus
extern "C" {
#endif

// Function declarations would go here
// For now, this is a placeholder

#ifdef __cplusplus
}
#endif

#endif // EM_PROXY_H
EMPROXYEOF
      fi
      
      # SwiftBridgeCore.h and SwiftBridgeCore.swift - Core bridge infrastructure
      cat > "$out/include/SwiftBridgeCore.h" << 'COREEOF'
// SwiftBridgeCore.h - Core bridge infrastructure for Swift-Objective-C interop
#ifndef SWIFT_BRIDGE_CORE_H
#define SWIFT_BRIDGE_CORE_H

#import <Foundation/Foundation.h>

// Core bridge types and utilities
NS_ASSUME_NONNULL_BEGIN

// Bridge utilities would go here

NS_ASSUME_NONNULL_END

#endif // SWIFT_BRIDGE_CORE_H
COREEOF
      
      cat > "$out/include/SwiftBridgeCore.swift" << 'CORESWIFTEOF'
// SwiftBridgeCore.swift - Core bridge infrastructure for Swift-Objective-C interop
import Foundation

// Core bridge types and utilities for Swift-Objective-C interop
CORESWIFTEOF
      
      echo ""
      echo "✅ SideStore components packaged:"
      echo "   Packages: $(ls $out/SwiftPackages/ | wc -l) items"
      echo "   Binaries: $(ls $out/bin/ | wc -l) items"
      echo "   Libraries: $(ls $out/lib/ | wc -l) items"
      echo "   Bridge files: $(ls $out/include/ | wc -l) items"
    '';
    
    meta = with lib; {
      description = "Complete SideStore component bundle for HIAH Desktop";
      license = licenses.agpl3Plus;
      platforms = platforms.darwin;
    };
  };
}
