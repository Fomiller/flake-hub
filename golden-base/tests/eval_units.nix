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
      "meta" = { type = "attrs"; };
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
    executable = [ ];
    schema = { };
  };
  packA = mkPack "a";
  packB = mkPack "b";
  withPartials = pack: pack // { partials = "${fixtures}/packs/${pack.name}/partials"; };

  pathvars = import "${engineSrc}/lib/pathvars.nix" { inherit (pkgs) lib; };
  plan = import "${engineSrc}/lib/plan.nix" { inherit (pkgs) lib; inherit pathvars; };
  planFixture = {
    owners = { ".gitignore" = "golden-base"; };
    ownership = { managed = [ "**" ]; scaffold = [ ]; retired = [ ]; };
    executable = [ ];
  };
  planConfig = { name = "x"; unmanaged = [ ]; };
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

  testPartialRootsAreReversedForFirstMatchWins = {
    expr = (merge.mergePacks [
      (withPartials packA)
      ((withPartials packB) // { overrides = [ "shared.txt" "_shared.jinja" ]; })
    ]).partialRoots;
    expected = [ (withPartials packB).partials (withPartials packA).partials ];
  };

  testUndeclaredPartialCollisionThrows = {
    expr = (builtins.tryEval (builtins.deepSeq
      (merge.mergePacks [
        (withPartials packA)
        ((withPartials packB) // { overrides = [ "shared.txt" ]; })
      ]).partialRoots
      null)).success;
    expected = false;
  };

  testDeclaredPartialCollisionIsAllowed = {
    expr = (builtins.tryEval (builtins.deepSeq
      (merge.mergePacks [
        (withPartials packA)
        ((withPartials packB) // { overrides = [ "shared.txt" "_shared.jinja" ]; })
      ]).partialRoots
      null)).success;
    expected = true;
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

  testPackDefaultListsConcatenateInPackOrder = {
    expr = (merge.mergePacks [
      (packA // { defaults = { ci.steps = [ "a" ]; }; })
      (packB // { defaults = { ci.steps = [ "b" ]; }; overrides = [ "shared.txt" ]; })
    ]).defaults.ci.steps;
    expected = [ "a" "b" ];
  };

  testRepoConfigReplacesAListRatherThanAppending = {
    expr = (config.mergeConfig
      (mergedFixture // {
        defaults = { ci.steps = [ "a" "b" ]; };
        schema = mergedFixture.schema // { "ci.steps" = { type = "list"; }; };
      })
      { name = "x"; ci.steps = [ ]; }).ci.steps;
    expected = [ ];
  };

  testIntTypeAccepted = {
    expr = (config.mergeConfig
      (mergedFixture // { schema = mergedFixture.schema // { "service.port" = { type = "int"; }; }; })
      { name = "x"; service.port = 8080; }).service.port;
    expected = 8080;
  };

  # Asserts the message. Without the `int` branch this throws anyway, but for
  # the wrong reason: unknown type rather than failed schema.
  testIntTypeRejectsString = {
    expr = config.mergeConfig
      (mergedFixture // { schema = mergedFixture.schema // { "service.port" = { type = "int"; }; }; })
      { name = "x"; service.port = "8080"; };
    expectedError = {
      type = "ThrownError";
      msg = "(.|\n)*key 'service.port' in repo.nix failed its schema: expected int(.|\n)*";
    };
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

  testAttrsTypedKeyAcceptsPopulatedValue = {
    expr = (config.mergeConfig mergedFixture { name = "x"; meta = { a = "1"; b = "2"; }; }).meta;
    expected = { a = "1"; b = "2"; };
  };

  testAttrsTypedKeyAcceptsEmptyValue = {
    expr = (config.mergeConfig mergedFixture { name = "x"; meta = { }; }).meta;
    expected = { };
  };

  testUndeclaredEmptyAttrsKeyThrows = {
    expr = (builtins.tryEval (builtins.deepSeq
      (config.mergeConfig mergedFixture { name = "x"; bogus = { }; })
      null)).success;
    expected = false;
  };

  testRequiredAttrsKeyIsSatisfiedWhenSet = {
    expr = (builtins.tryEval (builtins.deepSeq
      (config.mergeConfig
        (mergedFixture // {
          schema = mergedFixture.schema // { "meta" = { type = "attrs"; required = true; }; };
        })
        { name = "x"; meta = { a = "1"; }; })
      null)).success;
    expected = true;
  };

  testPathsClassifyByGlob = {
    expr = (plan.mkPlan planFixture planConfig).managed;
    expected = [ ".gitignore" ];
  };

  testUnmanagedPathLeavesManagedList = {
    expr = (plan.mkPlan planFixture (planConfig // { unmanaged = [ ".gitignore" ]; })).managed;
    expected = [ ];
  };

  testUnclassifiedPathThrows = {
    expr = (builtins.tryEval (builtins.deepSeq
      (plan.mkPlan (planFixture // { ownership = { managed = [ "nope/**" ]; scaffold = [ ]; retired = [ ]; }; }) planConfig)
      null)).success;
    expected = false;
  };

  testStaleUnmanagedEntryThrows = {
    expr = (builtins.tryEval (builtins.deepSeq
      (plan.mkPlan planFixture (planConfig // { unmanaged = [ "not-generated.txt" ]; }))
      null)).success;
    expected = false;
  };

  testGlobMatchesLiteralMetacharacter = {
    expr =
      let
        matched = plan.mkPlan
          { owners = { "foo+bar" = "golden-base"; }; ownership = { managed = [ "foo+bar" ]; scaffold = [ ]; retired = [ ]; }; executable = [ ]; }
          planConfig;
        unrelatedThrows = (builtins.tryEval (builtins.deepSeq
          (plan.mkPlan
            { owners = { "foobar" = "golden-base"; }; ownership = { managed = [ "foo+bar" ]; scaffold = [ ]; retired = [ ]; }; executable = [ ]; }
            planConfig)
          null)).success;
      in
      { managed = matched.managed; unrelatedThrows = unrelatedThrows; };
    expected = { managed = [ "foo+bar" ]; unrelatedThrows = false; };
  };

  testGlobWithParenDoesNotCrash = {
    expr = (plan.mkPlan
      { owners = { "a(b" = "golden-base"; }; ownership = { managed = [ "a(b" ]; scaffold = [ ]; retired = [ ]; }; executable = [ ]; }
      planConfig).managed;
    expected = [ "a(b" ];
  };

  testTemplatedPathIsSubstituted = {
    expr = (plan.mkPlan
      {
        owners = { "helm/{{ name }}/Chart.yaml" = "golden-argocd"; };
        ownership = { managed = [ "helm/*/Chart.yaml" ]; scaffold = [ ]; retired = [ ]; };
        executable = [ ];
      }
      planConfig).managed;
    expected = [ "helm/x/Chart.yaml" ];
  };

  # Only top-level strings are substituted, on both sides. A nested or
  # non-string key in a path would leave the plan pointing somewhere the
  # rendered tree never puts a file, so it has to fail loudly.
  testUnresolvedPathVariableThrows = {
    expr = (builtins.tryEval (builtins.deepSeq
      (plan.mkPlan
        {
          owners = { "helm/{{ service.port }}/Chart.yaml" = "golden-argocd"; };
          ownership = { managed = [ "helm/*/Chart.yaml" ]; scaffold = [ ]; retired = [ ]; };
          executable = [ ];
        }
        planConfig)
      null)).success;
    expected = false;
  };

  testRetiredPathStillEmittedThrows = {
    expr = (builtins.tryEval (builtins.deepSeq
      (plan.mkPlan
        (planFixture // { ownership = planFixture.ownership // { retired = [ ".gitignore" ]; }; })
        planConfig)
      null)).success;
    expected = false;
  };

  testUnmanagedPathNeedsNoOwnershipGlob = {
    expr = (plan.mkPlan
      { owners = { ".gitignore" = "golden-base"; "extra.txt" = "golden-base"; }; ownership = { managed = [ ".gitignore" ]; scaffold = [ ]; retired = [ ]; }; executable = [ ]; }
      (planConfig // { unmanaged = [ "extra.txt" ]; })).managed;
    expected = [ ".gitignore" ];
  };

  # Asserts the message, not just that it throws: without the guard the `stale`
  # check throws anyway, but for the wrong reason.
  testRetiredAndUnmanagedThrows = {
    expr = plan.mkPlan
      (planFixture // { ownership = planFixture.ownership // { retired = [ "old.txt" ]; }; })
      (planConfig // { unmanaged = [ "old.txt" ]; });
    expectedError = {
      type = "ThrownError";
      msg = "(.|\n)*'old.txt' is listed as retired but also declared unmanaged(.|\n)*";
    };
  };

  testExecutableGlobResolvesToEmittedPaths = {
    expr = (plan.mkPlan
      {
        owners = { "scripts/a.sh" = "p"; "README.md" = "p"; };
        ownership = { managed = [ "**" ]; scaffold = [ ]; retired = [ ]; };
        executable = [ "scripts/*" ];
      }
      planConfig).executable;
    expected = [ "scripts/a.sh" ];
  };

  # A repo may unmanage an executable path; that must not read as a typo.
  testUnmanagedExecutablePathIsNotStale = {
    expr = (plan.mkPlan
      {
        owners = { "scripts/a.sh" = "p"; };
        ownership = { managed = [ "**" ]; scaffold = [ ]; retired = [ ]; };
        executable = [ "scripts/*" ];
      }
      (planConfig // { unmanaged = [ "scripts/a.sh" ]; })).executable;
    expected = [ ];
  };

  testExecutableGlobMatchingNothingThrows = {
    expr = plan.mkPlan (planFixture // { executable = [ "scripts/*" ]; }) planConfig;
    expectedError = {
      type = "ThrownError";
      msg = "(.|\n)*executable glob 'scripts/\\*' matches no generated path(.|\n)*";
    };
  };

  testMergeUnionsExecutableAcrossPacks = {
    expr = (merge.mergePacks [
      (packA // { executable = [ "scripts/*" ]; })
      (packB // { overrides = [ "shared.txt" ]; executable = [ "bin/*" ]; })
    ]).executable;
    expected = [ "scripts/*" "bin/*" ];
  };

  testManagedScaffoldOverlapThrows = {
    expr = (builtins.tryEval (builtins.deepSeq
      (plan.mkPlan
        (planFixture // { ownership = planFixture.ownership // { scaffold = [ "**" ]; }; })
        planConfig)
      null)).success;
    expected = false;
  };
}
