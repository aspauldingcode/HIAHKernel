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
in

{
  inherit em-proxy minimuxer roxas altsign;
  
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
      
      echo ""
      echo "✅ SideStore components packaged:"
      echo "   Packages: $(ls $out/SwiftPackages/ | wc -l) items"
      echo "   Binaries: $(ls $out/bin/ | wc -l) items"
      echo "   Libraries: $(ls $out/lib/ | wc -l) items"
    '';
    
    meta = with lib; {
      description = "Complete SideStore component bundle for HIAH Desktop";
      license = licenses.agpl3Plus;
      platforms = platforms.darwin;
    };
  };
}
