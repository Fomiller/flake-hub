{ pkgs, engineSrc, fixtures }:
let
  paths = import "${engineSrc}/lib/paths.nix" { lib = pkgs.lib; };
  fixture = "${fixtures}/paths";
  merge = import "${engineSrc}/lib/merge.nix" { inherit (pkgs) lib; inherit paths; };
  config = import "${engineSrc}/lib/config.nix" { inherit (pkgs) lib; };
  mergedFixture = {
    defaults = { language = "go"; service.container = true; };
    registry = { };
    schema = {
      "name" = { type = "string"; required = true; };
      "language" = { type = "enum"; values = [ "go" "rust" ]; };
      "service.container" = { type = "bool"; };
      "unmanaged" = { type = "list"; };
    };
  };
  mkPack = name: {
    inherit name;
    templates = "${fixtures}/packs/${name}/templates";
    partials = null;
    defaults = { };
    registry = { };
    ownership = { managed = [ "**" ]; scaffold = [ ]; retired = [ ]; };
    overrides = [ ];
    schema = { };
  };
  packA = mkPack "a";
  packB = mkPack "b";
in
{
  testHarnessRuns = { expr = 1 + 1; expected = 2; };

  testListFilesIsRecursive = {
    expr = builtins.sort builtins.lessThan (paths.listFiles "${fixture}/templates");
    expected = [ ".github/workflows/ci.yml.jinja" "README.md.jinja" "static.txt" ];
  };

  testEmittedPathsStripsJinjaSuffix = {
    expr = builtins.sort builtins.lessThan (paths.emittedPaths "${fixture}/templates");
    expected = [ ".github/workflows/ci.yml" "README.md" "static.txt" ];
  };

  testEmittedPathsExcludesPartials = {
    expr = builtins.sort builtins.lessThan (paths.emittedPaths "${fixture}/partials");
    expected = [ "orphan" ];
  };

  testPartialViolationsFlagsUnprefixedFile = {
    expr = paths.partialViolations "${fixture}/templates";
    expected = [ ".github/workflows/ci.yml.jinja" "README.md.jinja" "static.txt" ];
  };

  testPartialViolationsFlagsOrphanInPartialsRoot = {
    expr = paths.partialViolations "${fixture}/partials";
    expected = [ "orphan.jinja" ];
  };

  testMergeUnionsEmittedPaths = {
    expr = builtins.sort builtins.lessThan (builtins.attrNames (merge.mergePacks [ packA (packB // { overrides = [ "shared.txt" ]; }) ]).owners);
    expected = [ "only-a.txt" "shared.txt" ];
  };

  testLaterPackWinsWhenItDeclaresOverride = {
    expr = (merge.mergePacks [ packA (packB // { overrides = [ "shared.txt" ]; }) ]).owners."shared.txt";
    expected = "b";
  };

  testTemplateRootsAreReversedForFirstMatchWins = {
    expr = (merge.mergePacks [ packA (packB // { overrides = [ "shared.txt" ]; }) ]).templateRoots;
    expected = [ packB.templates packA.templates ];
  };

  testUndeclaredCollisionThrows = {
    expr = (builtins.tryEval (builtins.deepSeq (merge.mergePacks [ packA packB ]).owners null)).success;
    expected = false;
  };

  testCollisionThrowsEvenWhenOnlyTemplateRootsRead = {
    expr = (builtins.tryEval (builtins.deepSeq (merge.mergePacks [ packA packB ]).templateRoots null)).success;
    expected = false;
  };

  testDefaultsDeepMerge = {
    expr = (merge.mergePacks [
      (packA // { defaults = { ci = { security = false; release = true; }; }; })
      (packB // { defaults = { ci = { security = true; }; }; overrides = [ "shared.txt" ]; })
    ]).defaults.ci;
    expected = { security = true; release = true; };
  };

  testSchemaDeepMergesDescriptors = {
    expr = (merge.mergePacks [
      (packA // { schema = { name = { type = "string"; required = true; }; }; })
      (packB // { schema = { name = { required = false; }; }; overrides = [ "shared.txt" ]; })
    ]).schema.name;
    expected = { type = "string"; required = false; };
  };

  testRepoConfigBeatsDefaults = {
    expr = (config.mergeConfig mergedFixture { name = "x"; language = "rust"; }).language;
    expected = "rust";
  };

  testUnknownKeyThrows = {
    expr = (builtins.tryEval (builtins.deepSeq (config.mergeConfig mergedFixture { name = "x"; langauge = "go"; }) null)).success;
    expected = false;
  };

  testEnumViolationThrows = {
    expr = (builtins.tryEval (builtins.deepSeq (config.mergeConfig mergedFixture { name = "x"; language = "cobol"; }) null)).success;
    expected = false;
  };

  testMissingRequiredKeyThrows = {
    expr = (builtins.tryEval (builtins.deepSeq (config.mergeConfig mergedFixture { }) null)).success;
    expected = false;
  };

  testNestedKeyValidatesByDottedName = {
    expr = (config.mergeConfig mergedFixture { name = "x"; service.container = false; }).service.container;
    expected = false;
  };
}
