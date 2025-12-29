{ pkgs, lib, fetchFromGitHub }:

# AltSign Swift Package - for integration into Xcode project
pkgs.stdenv.mkDerivation rec {
  pname = "altsign-spm";
  version = "unstable-2025-12-29";
  
  src = fetchFromGitHub {
    owner = "SideStore";
    repo = "AltSign";
    rev = "ff48fa54a5b32e9cc9035ff6acb61e4f0848e364";
    sha256 = "sha256-hYz3QC53vjXSQOmlc/j+HwVe/dV2FD/7NClOBFWBhl4=";
    fetchSubmodules = true; # Includes OpenSSL, ldid, etc
  };
  
  dontBuild = true;
  dontConfigure = true;
  
  installPhase = ''
    mkdir -p $out/AltSign
    
    # Copy entire AltSign package
    cp -r . $out/AltSign/
    
    echo "✅ AltSign Swift Package staged for Xcode integration"
    echo "   Package.swift: $out/AltSign/Package.swift"
    echo "   Sources: $out/AltSign/AltSign/"
    echo ""
    echo "To integrate:"
    echo "  1. Add as local Swift package in Xcode"
    echo "  2. Link AltSign-Static to HIAHLoginWindow target"
  '';
  
  meta = with lib; {
    description = "AltSign - Code signing framework (Swift Package)";
    homepage = "https://github.com/SideStore/AltSign";
    license = licenses.agpl3Plus;
    platforms = platforms.darwin;
  };
}

