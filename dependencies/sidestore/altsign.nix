{ pkgs, lib, fetchFromGitHub }:

pkgs.stdenv.mkDerivation rec {
  pname = "altsign";
  version = "unstable-2025-12-29";
  
  src = fetchFromGitHub {
    owner = "SideStore";
    repo = "AltSign";
    rev = "master";
    sha256 = lib.fakeSha256; # Will be updated on first build
    fetchSubmodules = true; # Includes OpenSSL and ldid
  };
  
  buildPhase = ''
    echo "AltSign is a Swift/ObjC framework - no build needed"
  '';
  
  installPhase = ''
    mkdir -p $out/Frameworks/AltSign.framework
    
    # Copy framework sources
    cp -r . $out/Frameworks/AltSign.framework/
    
    echo "✅ AltSign framework staged"
  '';
  
  meta = with lib; {
    description = "AltSign - Code signing framework for SideStore";
    homepage = "https://github.com/SideStore/AltSign";
    license = licenses.agpl3Plus;
    platforms = platforms.darwin;
  };
}

