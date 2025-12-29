{ lib, fetchFromGitHub, rustPlatform }:

rustPlatform.buildRustPackage rec {
  pname = "em-proxy";
  version = "unstable-2025-12-29";
  
  src = fetchFromGitHub {
    owner = "jkcoxson";
    repo = "em_proxy";
    rev = "master";
    sha256 = "sha256-uOt2FdB3f6eZfupHwB0xDHJOon11bNSTP2V/0nhLRUc=";
  };
  
  cargoLock = {
    lockFile = ./em-proxy.lock;
  };
  
  postPatch = ''
    ln -s ${./em-proxy.lock} Cargo.lock
  '';
  
  doCheck = false; # Skip tests for cross-compilation
  
  meta = with lib; {
    description = "EM Proxy - VPN loopback for SideStore";
    homepage = "https://github.com/jkcoxson/em_proxy";
    license = licenses.agpl3Plus;
    platforms = platforms.darwin;
  };
}
