{ pkgs, engineSrc, basePack, githubPack }:
let
  paths = import "${engineSrc}/lib/paths.nix" { lib = pkgs.lib; };
  merge = import "${engineSrc}/lib/merge.nix" { inherit (pkgs) lib; inherit paths; };
  merged = merge.mergePacks [ basePack githubPack ];
in
{
  testCodeownersIsOwnedByThisPack = {
    expr = merged.owners."CODEOWNERS";
    expected = "golden-github";
  };

  # The two packs each ship their own header partial, naming themselves in it.
  # Under one shared name the later pack's copy would win and stamp golden-base's
  # files with the wrong pack. Distinct names is what keeps that from happening,
  # so assert both are reachable rather than trusting the file layout.
  testBothHeaderPartialsSurviveTheMerge = {
    expr = builtins.sort builtins.lessThan
      (pkgs.lib.concatMap paths.listFiles merged.partialRoots);
    expected = [ "_base_header.jinja" "_github_header.jinja" ];
  };

  testMergingTheTwoPacksDoesNotCollide = {
    expr = (builtins.tryEval (builtins.deepSeq merged.owners null)).success;
    expected = true;
  };

  testCodeownersIsRequired = {
    expr = merged.schema."codeowners".required;
    expected = true;
  };
}
