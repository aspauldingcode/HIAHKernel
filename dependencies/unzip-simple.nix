# Simple unzip for iOS using Nix's cross-compilation
{ pkgs }:

# Use pkgsCross for iOS
let
  iosPkgs = pkgs.pkgsCross.iphone64;
in
iosPkgs.unzip

