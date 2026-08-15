# mkGolden { packs = [ ... ]; } pkgs repoConfig -> { filesDrv; plan; generateApp; mergedConfig; }
#
# The engine knows nothing about file layout: every path, glob and directory
# name comes from a pack. Guards throw at eval, before any build starts.
{ packs }:
pkgs:
repoConfig:
let
  lib = pkgs.lib;
  paths = import ./lib/paths.nix { inherit lib; };
  merge = import ./lib/merge.nix { inherit lib paths; };
  configLib = import ./lib/config.nix { inherit lib; };
  planLib = import ./lib/plan.nix { inherit lib; };

  merged = merge.mergePacks packs;
  mergedConfig = configLib.mergeConfig merged repoConfig;
  planData = planLib.mkPlan merged mergedConfig;
  plan = pkgs.writeText "golden-plan.json" (builtins.toJSON planData);

  renderData = pkgs.writeText "golden-data.json" (builtins.toJSON mergedConfig);

  inputArgs = lib.concatMapStringsSep " " (root: "-i ${root}")
    (merged.templateRoots ++ merged.partialRoots);

  filesDrv = pkgs.runCommand "golden-files-${mergedConfig.name}"
    {
      nativeBuildInputs = [ pkgs.makejinja ];
      # Forces every plan guard. Without this a lazy throw never fires.
      planChecksum = builtins.hashString "sha256" (builtins.toJSON planData);
    }
    ''
      mkdir -p "$out"
      makejinja ${inputArgs} -o "$out" -d ${renderData} \
        --undefined strict \
        --exclude-pattern '_*'
    '';
in
{
  inherit filesDrv plan mergedConfig;
}
