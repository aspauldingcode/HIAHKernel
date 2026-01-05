# GNU Tools for iOS
# Cross-compiled Unix utilities for HIAH Desktop virtual filesystem

{
  lib,
  pkgs,
  buildPackages,
}:

# Minimal tools bundle - just unzip for .ipa extraction
# Using native macOS binary for simulator (works for testing)
# TODO: Proper iOS cross-compilation for real device deployment
pkgs.stdenv.mkDerivation {
  name = "gnu-tools-ios";
  version = "1.0";
  
  dontUnpack = true;
  
  installPhase = ''
    mkdir -p $out/usr/bin $out/bin
    
    echo "Bundling Unix tools (native for simulator)..."
    
    # Unzip (essential for .ipa extraction)
    if [ -f "${pkgs.unzip}/bin/unzip" ]; then
      cp ${pkgs.unzip}/bin/unzip $out/usr/bin/unzip
      chmod +x $out/usr/bin/unzip
      echo "✓ unzip"
    fi
    
    # Shell (bash/sh for scripts)
    if [ -f "${pkgs.bash}/bin/bash" ]; then
      cp ${pkgs.bash}/bin/bash $out/bin/bash
      ln -s bash $out/bin/sh
      chmod +x $out/bin/bash
      echo "✓ bash/sh"
    fi
    
    echo "NOTE: Using native macOS binaries for simulator testing"
    echo "For real device: Requires proper iOS cross-compilation"
  '';
}

