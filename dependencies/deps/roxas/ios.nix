# roxas - iOS build
# Swift Package Manager package from Riley Testut (AltStore)
# Used for UI components

{ lib, pkgs, fetchFromGitHub }:

pkgs.stdenv.mkDerivation rec {
  pname = "roxas";
  version = "unstable-2025-12-29";
  
  src = fetchFromGitHub {
    owner = "rileytestut";
    repo = "Roxas";
    rev = "master";
    sha256 = "sha256-3nSAO49+DAGLMjVxCKlNUm2JvnOdgqD0gMYfjfuzaOQ=";
  };
  
  dontBuild = true;
  dontConfigure = true;
  
  installPhase = ''
    mkdir -p $out/Roxas
    
    # Copy Roxas sources
    cp -r Roxas/* $out/Roxas/
    
    # Copy podspec for reference
    cp Roxas.podspec $out/ 2>/dev/null || true
    
    echo "✅ Roxas framework staged"
  '';
  
  meta = with lib; {
    description = "Roxas - Utility framework from AltStore";
    homepage = "https://github.com/rileytestut/Roxas";
    license = licenses.unfree; # Part of AltStore
    platforms = platforms.darwin;
  };
}
