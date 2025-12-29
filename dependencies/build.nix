{
  lib,
  pkgs,
  stdenv,
  buildPackages,
}:

let
  common = import ./common/common.nix { inherit lib pkgs; };
  
  iosModuleSelf = rec {
    buildForIOS =
      name: entry:
      (import ./platforms/ios.nix {
        inherit
          lib
          pkgs
          buildPackages
          common
          ;
        buildModule = iosModuleSelf;
      }).buildForIOS
        name
        entry;
  };
  
  iosModule = iosModuleSelf;
  registry = common.registry;
  
  buildAllForPlatform =
    platform:
    let
      filteredRegistry = lib.filterAttrs (
        _: entry:
        let
          platforms = entry.platforms or [ "ios" ];
        in
        lib.elem platform platforms
      ) registry;
      
      # Direct packages (built-in, not from registry)
      directPkgs =
        if platform == "ios" then
          {
            # Add iOS dependencies here as needed
          }
        else
          { };
    in
    lib.mapAttrs (
      name: entry:
      if platform == "ios" then
        iosModule.buildForIOS name entry
      else
        throw "Unknown platform: ${platform}"
    ) filteredRegistry
    // directPkgs;
in
{
  buildForIOS = iosModuleSelf.buildForIOS;
  buildAllForPlatform = buildAllForPlatform;
  ios = buildAllForPlatform "ios";
}
