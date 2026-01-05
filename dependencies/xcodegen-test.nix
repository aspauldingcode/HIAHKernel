# Test file to isolate the boost error
{
  pkgs,
  rustPlatform,
  xcode ? null,
}:

let
  lib = pkgs.lib;
  buildPackages = pkgs.buildPackages;
  fetchFromGitHub = pkgs.fetchFromGitHub;

  # Import dependencies
  em-proxy = pkgs.callPackage ./deps/em-proxy/ios.nix {
    inherit rustPlatform lib fetchFromGitHub;
  };
  
  roxas = pkgs.callPackage ./deps/roxas/ios.nix {
    inherit pkgs lib fetchFromGitHub;
  };
  
  # Just import openssl
  openssl = import ./deps/openssl/ios.nix {
    inherit pkgs lib buildPackages xcode;
  };
  
  opensslSim = toString openssl.ios-sim;

in pkgs.stdenv.mkDerivation {
  pname = "test-xcodegen";
  version = "1.0.0";
  src = ./..;
  buildPhase = ''
    echo "openssl: ${opensslSim}"
  '';
  installPhase = "mkdir -p $out && echo done > $out/result";
}
