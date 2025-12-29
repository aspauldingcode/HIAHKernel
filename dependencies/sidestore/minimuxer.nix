{ lib, fetchFromGitHub, rustPlatform }:

rustPlatform.buildRustPackage rec {
  pname = "minimuxer";
  version = "unstable-2025-12-29";
  
  src = fetchFromGitHub {
    owner = "jkcoxson";
    repo = "minimuxer";
    rev = "master";
    sha256 = "sha256-+5kuVGyUYlNOxJ879DL3WanjDJbxNj0EXzb99yBr7iI=";
  };
  
  cargoHash = "sha256-YO2TDOl3v9ukOH0XxtGL8zmwQ8OXlCbAgumxjIQmw70=";
  
  doCheck = false;
  
  meta = with lib; {
    description = "Minimuxer - Lockdown muxer for SideStore";
    homepage = "https://github.com/jkcoxson/minimuxer";
    license = licenses.agpl3Plus;
    platforms = platforms.darwin;
  };
}
