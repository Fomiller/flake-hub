# mkGolden { packs = [ ... ]; } pkgs repoConfig -> { filesDrv; plan; generateApp; mergedConfig; }
#
# Field list is authoritative here. The engine knows nothing about file
# layout: every path, glob and directory name comes from a pack.
{ packs }:
pkgs:
repoConfig:
let
  lib = pkgs.lib;
in
{
  inherit packs repoConfig;
  mergedConfig = { };
}
