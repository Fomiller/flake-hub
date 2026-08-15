# golden-engine + golden-base Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A working golden-file generator: `nix run .#generate` in a consumer repo renders the `golden-base` file set, reconciles it into the working tree by ownership class, and is idempotent.

**Architecture:** `golden-engine/` is a flake with no inputs that exposes `lib.mkGolden`. It merges a list of packs, merges the merged pack data with the consumer's `repo.nix`, renders one makejinja pass, emits an ownership plan as JSON, and exposes a `generate` app that runs `reconcile.py` over the rendered tree and the plan. Nix validates and builds; Python executes. `golden-base/` is the first pack — templates plus a `pack.nix`, no logic — and it also hosts the engine's test suites, because the engine has no `pkgs` of its own.

**Tech Stack:** Nix flakes, makejinja 2.8.2 (Jinja2), Python 3 + pytest, nix-unit 2.35.1, nixpkgs-unstable.

## Global Constraints

- Repo: `/Users/forrest/dev/personal/flake-hub`, default branch `main`.
- Spec: `docs/superpowers/specs/2026-08-15-flake-hub-design.md`. Read it before Task 1.
- `golden-engine/flake.nix` has **zero inputs**. `mkGolden` takes `pkgs` from the caller.
- The engine names no file layout — no path, no glob, no directory name. Anything layout-shaped is a pack field. A violation of this is a review rejection, not a nit.
- makejinja is invoked with `--undefined strict` always.
- Partial templates are named `_*.jinja` and live in a pack's `partials/`. They are never emitted.
- Generated-file header text, exactly:
  ```
  # GENERATED FILE — managed by flake-hub (golden-base).
  # Do not edit manually: `nix run .#generate` overwrites it.
  # To change it, edit repo.nix, or the template in the pack that owns it.
  ```
- Every eval guard must be forced by a binding a real output depends on, and must have a nix-unit case that goes red when the guard is deleted.
- Commit messages: conventional prefix, Jira/Linear scope `FOM-51`, `Co-Authored-By: Claude` trailer. No AI attribution in PR descriptions.
- Nix formatting: `nixpkgs-fmt`. Python formatting: `ruff format`.

---

### Task 1: Repo skeleton and the test harness that everything else needs

The engine cannot test itself — it has no `pkgs`. So the harness comes first: a minimal `golden-base` flake that pulls the engine in by relative path and exposes a nix-unit app. Every later task adds cases to it.

**Files:**
- Create: `golden-engine/flake.nix`
- Create: `golden-engine/mkGolden.nix`
- Create: `golden-base/flake.nix`
- Create: `golden-base/tests/eval_units.nix`
- Create: `.gitignore`
- Create: `justfile`

- [ ] **Step 1: Write the engine flake**

`golden-engine/flake.nix`:

```nix
{
  description = "Team-agnostic core of the flake-hub golden-file generator";

  outputs = { self }: {
    lib.mkGolden = import ./mkGolden.nix;

    # Paths, not derivations: packs own the pkgs that run these. `src` is the
    # whole flake directory, so a pack can reach lib/ and tests/ together —
    # a store path cannot be escaped with `/..`.
    src = ./.;
  };
}
```

- [ ] **Step 2: Write the mkGolden stub**

`golden-engine/mkGolden.nix`. It only has to evaluate for now:

```nix
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
```

- [ ] **Step 3: Write the harness flake**

`golden-base/flake.nix`:

```nix
{
  description = "golden-base: files every repo gets, whatever it is";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    golden-engine.url = "path:../golden-engine";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, golden-engine, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        apps.test-eval = {
          type = "app";
          program = toString (pkgs.writeShellScript "test-eval" ''
            exec ${pkgs.nix-unit}/bin/nix-unit \
              --eval-store auto \
              ${./tests/eval_units.nix}
          '');
        };
      })
    // {
      pack = import ./pack.nix;
    };
}
```

Note the `pack` output is outside `eachDefaultSystem` — a pack is system-independent data.

- [ ] **Step 4: Write a passing placeholder test file**

`golden-base/tests/eval_units.nix`:

```nix
{
  testHarnessRuns = {
    expr = 1 + 1;
    expected = 2;
  };
}
```

- [ ] **Step 5: Write pack.nix so the flake evaluates**

`golden-base/pack.nix`:

```nix
{
  name = "golden-base";
  templates = ./templates;
  partials = ./partials;
  defaults = { };
  registry = { };
  ownership = { managed = [ ]; scaffold = [ ]; retired = [ ]; };
  overrides = [ ];
  schema = { };
}
```

Create empty `golden-base/templates/.keep` and `golden-base/partials/.keep` so the paths exist.

- [ ] **Step 6: Run the harness**

Run: `nix run ./golden-base#test-eval`
Expected: PASS, 1 test.

- [ ] **Step 7: Commit**

```bash
git add golden-engine golden-base .gitignore justfile
git commit -m "feat(FOM-51): scaffold golden-engine and the golden-base test harness

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Template path listing

The engine needs to know, at evaluation time, which paths a pack will emit — collision detection, ownership classification and the plan all depend on it. Doing it in Nix means the answers exist before makejinja runs.

**Files:**
- Create: `golden-engine/lib/paths.nix`
- Create: `golden-base/tests/fixtures/paths/templates/README.md.jinja`
- Create: `golden-base/tests/fixtures/paths/templates/.github/workflows/ci.yml.jinja`
- Create: `golden-base/tests/fixtures/paths/templates/static.txt`
- Create: `golden-base/tests/fixtures/paths/partials/_header.jinja`
- Modify: `golden-base/tests/eval_units.nix`

**Interfaces:**
- Produces: `paths.listFiles :: path -> [string]` (relative paths, recursive), `paths.emittedPaths :: path -> [string]` (rendered output paths, `.jinja` stripped, `_`-prefixed files excluded), `paths.partialViolations :: path -> [string]` (files in a partials root not named `_*`).

- [ ] **Step 1: Write the failing tests**

Add to `golden-base/tests/eval_units.nix`:

```nix
let
  pkgs = import <nixpkgs> { };
  paths = import ../../golden-engine/lib/paths.nix { lib = pkgs.lib; };
  fixture = ./fixtures/paths;
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
    expr = paths.emittedPaths "${fixture}/partials";
    expected = [ ];
  };

  testPartialViolationsFlagsUnprefixedFile = {
    expr = paths.partialViolations "${fixture}/templates";
    expected = [ ".github/workflows/ci.yml.jinja" "README.md.jinja" "static.txt" ];
  };
}
```

Fixture file contents are irrelevant to these tests; write `placeholder` into each.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `nix run ./golden-base#test-eval`
Expected: FAIL — `path '/nix/store/.../golden-engine/lib/paths.nix' does not exist`.

- [ ] **Step 3: Implement paths.nix**

`golden-engine/lib/paths.nix`:

```nix
{ lib }:
rec {
  listFiles = root:
    let
      walk = prefix: dir:
        lib.concatLists (lib.mapAttrsToList
          (name: type:
            let rel = if prefix == "" then name else "${prefix}/${name}";
            in
            if type == "directory" then walk rel "${dir}/${name}" else [ rel ])
          (builtins.readDir dir));
    in
    walk "" (toString root);

  isPartial = rel: lib.any (lib.hasPrefix "_") (lib.splitString "/" rel);

  stripJinja = rel: lib.removeSuffix ".jinja" rel;

  emittedPaths = root: map stripJinja (builtins.filter (rel: !isPartial rel) (listFiles root));

  partialViolations = root: builtins.filter (rel: !isPartial rel) (listFiles root);
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `nix run ./golden-base#test-eval`
Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add golden-engine/lib/paths.nix golden-base/tests
git commit -m "feat(FOM-51): list a pack's emitted paths at eval time

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Pack merge and the collision guard

**Files:**
- Create: `golden-engine/lib/merge.nix`
- Modify: `golden-base/tests/eval_units.nix`
- Create: `golden-base/tests/fixtures/packs/a/templates/shared.txt.jinja`
- Create: `golden-base/tests/fixtures/packs/a/templates/only-a.txt.jinja`
- Create: `golden-base/tests/fixtures/packs/b/templates/shared.txt.jinja`

**Interfaces:**
- Consumes: `paths.emittedPaths`, `paths.partialViolations` from Task 2.
- Produces: `merge.mergePacks :: [pack] -> { templateRoots; partialRoots; defaults; registry; ownership; schema; owners; }`. `templateRoots` is in **reverse** pack order, because makejinja's `-i` is first-match-wins and the spec says the later pack wins. `owners` maps emitted path to the pack name that will render it.

- [ ] **Step 1: Write the failing tests**

Add to `golden-base/tests/eval_units.nix`:

```nix
  testMergeUnionsEmittedPaths = {
    expr = builtins.sort builtins.lessThan (builtins.attrNames (merge.mergePacks [ packA packB ]).owners);
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

  testDefaultsDeepMerge = {
    expr = (merge.mergePacks [
      (packA // { defaults = { ci = { security = false; release = true; }; }; })
      (packB // { defaults = { ci = { security = true; }; }; overrides = [ "shared.txt" ]; })
    ]).defaults.ci;
    expected = { security = true; release = true; };
  };
```

with these bindings added to the `let`:

```nix
  merge = import ../../golden-engine/lib/merge.nix { inherit (pkgs) lib; inherit paths; };
  mkPack = name: {
    inherit name;
    templates = ./fixtures/packs + "/${name}/templates";
    partials = null;
    defaults = { };
    registry = { };
    ownership = { managed = [ "**" ]; scaffold = [ ]; retired = [ ]; };
    overrides = [ ];
    schema = { };
  };
  packA = mkPack "a";
  packB = mkPack "b";
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `nix run ./golden-base#test-eval`
Expected: FAIL — `merge.nix does not exist`.

- [ ] **Step 3: Implement merge.nix**

`golden-engine/lib/merge.nix`:

```nix
{ lib, paths }:
{
  mergePacks = packList:
    let
      partialProblems = lib.concatMap
        (pack:
          if pack.partials == null then [ ]
          else map (rel: "${pack.name}: partials/${rel} is not named _*") (paths.partialViolations pack.partials))
        packList;

      # path -> pack name, later packs overwrite earlier ones. A pack may only
      # overwrite a path it declares in `overrides`.
      step = acc: pack:
        let
          emitted = paths.emittedPaths pack.templates;
          clashes = builtins.filter
            (rel: acc.owners ? ${rel} && !(builtins.elem rel pack.overrides))
            emitted;
          errs = map
            (rel: "${pack.name} and ${acc.owners.${rel}} both emit '${rel}'. Add it to ${pack.name}'s `overrides` if that is intended.")
            clashes;
        in
        {
          owners = acc.owners // lib.genAttrs emitted (_: pack.name);
          errors = acc.errors ++ errs;
        };

      folded = lib.foldl' step { owners = { }; errors = partialProblems; } packList;

      guard = value:
        if folded.errors == [ ]
        then value
        else throw "mkGolden: pack merge failed:\n  ${lib.concatStringsSep "\n  " folded.errors}";
    in
    {
      owners = guard folded.owners;
      templateRoots = lib.reverseList (map (p: p.templates) packList);
      partialRoots = builtins.filter (r: r != null) (map (p: p.partials) packList);
      defaults = lib.foldl' lib.recursiveUpdate { } (map (p: p.defaults) packList);
      registry = lib.foldl' lib.recursiveUpdate { } (map (p: p.registry) packList);
      schema = lib.foldl' (a: p: a // p.schema) { } packList;
      ownership = {
        managed = lib.concatMap (p: p.ownership.managed) packList;
        scaffold = lib.concatMap (p: p.ownership.scaffold) packList;
        retired = lib.concatMap (p: p.ownership.retired) packList;
      };
    };
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `nix run ./golden-base#test-eval`
Expected: PASS, 10 tests.

- [ ] **Step 5: Delete the guard and watch a test go red**

Temporarily replace `guard folded.owners` with `folded.owners`. Run the suite. `testUndeclaredCollisionThrows` must fail. Restore the guard and rerun.

- [ ] **Step 6: Commit**

```bash
git add golden-engine/lib/merge.nix golden-base/tests
git commit -m "feat(FOM-51): merge packs and reject undeclared path collisions

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Config merge and schema validation

**Files:**
- Create: `golden-engine/lib/config.nix`
- Modify: `golden-base/tests/eval_units.nix`

**Interfaces:**
- Consumes: `merge.mergePacks` output from Task 3.
- Produces: `config.mergeConfig :: merged -> repoConfig -> attrs`. Schema keys are **dotted strings** (`"service.container"`), values are `{ type; required ? false; values ? null; }` with `type` one of `string`, `bool`, `list`, `attrs`, `enum`.

- [ ] **Step 1: Write the failing tests**

```nix
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
```

with:

```nix
  config = import ../../golden-engine/lib/config.nix { inherit (pkgs) lib; };
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `nix run ./golden-base#test-eval`
Expected: FAIL — `config.nix does not exist`.

- [ ] **Step 3: Implement config.nix**

`golden-engine/lib/config.nix`:

```nix
{ lib }:
let
  flatten = prefix: value:
    if builtins.isAttrs value
    then lib.concatLists (lib.mapAttrsToList
      (k: v: flatten (if prefix == "" then k else "${prefix}.${k}") v)
      value)
    else [{ key = prefix; inherit value; }];

  typeOk = entry: value:
    if entry.type == "string" then builtins.isString value
    else if entry.type == "bool" then builtins.isBool value
    else if entry.type == "list" then builtins.isList value
    else if entry.type == "attrs" then builtins.isAttrs value
    else if entry.type == "enum" then builtins.elem value entry.values
    else throw "mkGolden: schema for '${entry.name or "?"}' has unknown type '${entry.type}'";
in
{
  mergeConfig = merged: repoConfig:
    let
      resolved = lib.recursiveUpdate (lib.recursiveUpdate merged.defaults merged.registry) repoConfig;
      flat = flatten "" repoConfig;

      unknown = map (e: "unknown key '${e.key}' in repo.nix")
        (builtins.filter (e: !(merged.schema ? ${e.key})) flat);

      badType = map
        (e: "key '${e.key}' in repo.nix failed its schema: expected ${merged.schema.${e.key}.type}")
        (builtins.filter (e: merged.schema ? ${e.key} && !(typeOk merged.schema.${e.key} e.value)) flat);

      missing = map (k: "required key '${k}' is not set in repo.nix or any pack default")
        (builtins.filter
          (k: (merged.schema.${k}.required or false) && !(builtins.elem k (map (e: e.key) (flatten "" resolved))))
          (builtins.attrNames merged.schema));

      errors = unknown ++ badType ++ missing;
    in
    if errors == [ ]
    then resolved
    else throw "mkGolden: repo.nix is not valid:\n  ${lib.concatStringsSep "\n  " errors}";
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `nix run ./golden-base#test-eval`
Expected: PASS, 15 tests.

- [ ] **Step 5: Commit**

```bash
git add golden-engine/lib/config.nix golden-base/tests
git commit -m "feat(FOM-51): merge and validate repo.nix against the pack schema

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: The render pass

**Files:**
- Modify: `golden-engine/mkGolden.nix`
- Create: `golden-base/templates/.gitignore.jinja`
- Create: `golden-base/partials/_header.jinja`
- Modify: `golden-base/pack.nix`
- Modify: `golden-base/flake.nix`
- Create: `golden-base/tests/fixtures/repo.nix`
- Create: `golden-base/tests/expected/gitignore-default/.gitignore`

**Interfaces:**
- Consumes: `mergePacks`, `mergeConfig`.
- Produces: `mkGolden { packs } pkgs repoConfig` returns an attrset whose `filesDrv` is a derivation containing the rendered tree, and `mergedConfig` is the validated config.

- [ ] **Step 1: Write the failing snapshot check**

Add to `golden-base/flake.nix`, inside the `eachDefaultSystem` body:

```nix
        checks.render-snapshot =
          let
            golden = golden-engine.lib.mkGolden { packs = [ self.pack ]; } pkgs (import ./tests/fixtures/repo.nix);
          in
          pkgs.runCommand "render-snapshot" { } ''
            diff -ru ${./tests/expected/gitignore-default} ${golden.filesDrv}
            touch $out
          '';
```

`golden-base/tests/fixtures/repo.nix`:

```nix
{
  name = "snapshot-repo";
}
```

`golden-base/tests/expected/gitignore-default/.gitignore`:

```
# GENERATED FILE — managed by flake-hub (golden-base).
# Do not edit manually: `nix run .#generate` overwrites it.
# To change it, edit repo.nix, or the template in the pack that owns it.

result
result-*
.direnv/
.DS_Store
```

- [ ] **Step 2: Run the check to verify it fails**

Run: `nix build ./golden-base#checks.aarch64-darwin.render-snapshot -L`
Expected: FAIL — `attribute 'filesDrv' missing`.

- [ ] **Step 3: Write the templates**

`golden-base/partials/_header.jinja`:

```jinja
# GENERATED FILE — managed by flake-hub (golden-base).
# Do not edit manually: `nix run .#generate` overwrites it.
# To change it, edit repo.nix, or the template in the pack that owns it.
```

The pack name is literal, not a variable. Each pack ships its own `_header.jinja`
naming itself, so a file always says which pack owns it. A single injected global
would stamp every file with whichever pack happened to be last in the list.

`golden-base/templates/.gitignore.jinja`:

```jinja
{% include "_header.jinja" %}

result
result-*
.direnv/
.DS_Store
```

Update `golden-base/pack.nix` ownership:

```nix
  ownership = { managed = [ "**" ]; scaffold = [ ]; retired = [ ]; };
```

- [ ] **Step 4: Implement the render in mkGolden.nix**

Replace `golden-engine/mkGolden.nix` with:

```nix
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

  merged = merge.mergePacks packs;
  mergedConfig = configLib.mergeConfig merged repoConfig;

  renderData = pkgs.writeText "golden-data.json" (builtins.toJSON mergedConfig);

  inputArgs = lib.concatMapStringsSep " " (root: "-i ${root}")
    (merged.templateRoots ++ merged.partialRoots);

  filesDrv = pkgs.runCommand "golden-files-${mergedConfig.name}"
    { nativeBuildInputs = [ pkgs.makejinja ]; }
    ''
      mkdir -p "$out"
      makejinja ${inputArgs} -o "$out" -d ${renderData} \
        --undefined strict \
        --exclude-pattern '_*'
    '';
in
{
  inherit filesDrv mergedConfig;
}
```

Two behaviors of makejinja this relies on, both load-bearing:

- `-i` may be repeated and the **first** matching template wins, which is why `mergePacks` reverses the list — the last pack in the caller's list is the one whose template renders.
- A template that renders to nothing is not copied out. That is how a pack gates a file off with a `{% if %}` around the whole body, and it is why the reconcile step in Task 7 treats a managed path missing from `filesDrv` as a deletion.

- [ ] **Step 5: Run the check to verify it passes**

Run: `nix build ./golden-base#checks.aarch64-darwin.render-snapshot -L`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add golden-engine/mkGolden.nix golden-base
git commit -m "feat(FOM-51): render a merged pack tree with makejinja

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Ownership classification and plan emission

**Files:**
- Create: `golden-engine/lib/plan.nix`
- Modify: `golden-engine/mkGolden.nix`
- Modify: `golden-base/tests/eval_units.nix`

**Interfaces:**
- Consumes: `merged.owners` (Task 3), `mergedConfig` (Task 4).
- Produces: `plan.mkPlan :: lib -> merged -> mergedConfig -> { repo; managed; scaffold; retired; unmanaged; }`, all lists of concrete paths, no globs. `mkGolden` gains a `plan` output: a derivation building `golden-plan.json`.

- [ ] **Step 1: Write the failing tests**

```nix
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
      (plan.mkPlan (planFixture // { ownership = { managed = [ "nope/**" ]; scaffold = [ ]; retired = [ ]; }; }) planConfig) null)).success;
    expected = false;
  };

  testStaleUnmanagedEntryThrows = {
    expr = (builtins.tryEval (builtins.deepSeq
      (plan.mkPlan planFixture (planConfig // { unmanaged = [ "not-generated.txt" ]; })) null)).success;
    expected = false;
  };
```

with:

```nix
  plan = import ../../golden-engine/lib/plan.nix { inherit (pkgs) lib; };
  planFixture = {
    owners = { ".gitignore" = "golden-base"; };
    ownership = { managed = [ "**" ]; scaffold = [ ]; retired = [ ]; };
  };
  planConfig = { name = "x"; unmanaged = [ ]; };
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `nix run ./golden-base#test-eval`
Expected: FAIL — `plan.nix does not exist`.

- [ ] **Step 3: Implement plan.nix**

`golden-engine/lib/plan.nix`:

```nix
{ lib }:
let
  # Glob match supporting a trailing `**` and a single `*` per segment.
  # Deliberately small: pack globs are directory prefixes and filenames.
  matches = pattern: path:
    if pattern == "**" then true
    else if lib.hasSuffix "/**" pattern
    then lib.hasPrefix (lib.removeSuffix "**" pattern) path
    else builtins.match (lib.replaceStrings [ "." "*" ] [ "\\." "[^/]*" ] pattern) path != null;

  classOf = ownership: path:
    if lib.any (p: matches p path) ownership.managed then "managed"
    else if lib.any (p: matches p path) ownership.scaffold then "scaffold"
    else null;
in
{
  mkPlan = merged: config:
    let
      emitted = builtins.attrNames merged.owners;
      unmanaged = config.unmanaged or [ ];

      stale = map (u: "unmanaged entry '${u}' in repo.nix matches no generated path")
        (builtins.filter (u: !(builtins.elem u emitted)) unmanaged);

      unclassified = map (p: "'${p}' is rendered by ${merged.owners.${p}} but matches no ownership glob")
        (builtins.filter (p: classOf merged.ownership p == null) emitted);

      errors = stale ++ unclassified;

      live = builtins.filter (p: !(builtins.elem p unmanaged)) emitted;
      byClass = cls: builtins.filter (p: classOf merged.ownership p == cls) live;

      guard = value:
        if errors == [ ]
        then value
        else throw "mkGolden: plan is not valid:\n  ${lib.concatStringsSep "\n  " errors}";
    in
    guard {
      repo = config.name;
      managed = byClass "managed";
      scaffold = byClass "scaffold";
      retired = merged.ownership.retired;
      inherit unmanaged;
    };
}
```

- [ ] **Step 4: Wire the plan into mkGolden**

In `golden-engine/mkGolden.nix`, add to the `let`:

```nix
  planLib = import ./lib/plan.nix { inherit lib; };
  planData = planLib.mkPlan merged mergedConfig;
  plan = pkgs.writeText "golden-plan.json" (builtins.toJSON planData);
```

and add `plan` to the returned attrset. `filesDrv` must also force the guards, or a repo that only builds `filesDrv` skips validation entirely:

```nix
  filesDrv = pkgs.runCommand "golden-files-${mergedConfig.name}"
    {
      nativeBuildInputs = [ pkgs.makejinja ];
      # Forces every plan guard. Without this a lazy throw never fires.
      planChecksum = builtins.hashString "sha256" (builtins.toJSON planData);
    }
    ''...'';
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `nix run ./golden-base#test-eval && nix build ./golden-base#checks.aarch64-darwin.render-snapshot -L`
Expected: PASS, 19 tests, and the snapshot still builds.

- [ ] **Step 6: Delete a guard and watch a test go red**

Remove `planChecksum` from `filesDrv`, then add a bogus `unmanaged = [ "nope" ]` to `tests/fixtures/repo.nix` and build the snapshot. It must still build — proving the guard was unforced. Restore `planChecksum`, rebuild, confirm it now throws, then revert the fixture.

- [ ] **Step 7: Commit**

```bash
git add golden-engine golden-base/tests
git commit -m "feat(FOM-51): emit the ownership plan and force its guards

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: reconcile.py

**Files:**
- Create: `golden-engine/lib/reconcile.py`
- Create: `golden-engine/tests/reconcile_test.py`
- Modify: `golden-base/flake.nix`

**Interfaces:**
- Consumes: `filesDrv` and `golden-plan.json` from Task 6.
- Produces: CLI `reconcile.py --files <dir> --plan <plan.json> --root <repo root>`. Exit 0 on success. Prints one line per action.

Rules, in this order:

1. `retired` — delete the path under root if it exists.
2. `managed` — copy from `files` to root, overwriting. If the path is **absent** from `files` (the template rendered empty), delete it under root instead.
3. `scaffold` — copy only if the path does not exist under root.
4. `unmanaged` — never touched. Not in the plan's managed/scaffold lists at all.

- [ ] **Step 1: Write the failing tests**

`golden-engine/tests/reconcile_test.py`:

```python
import json
import subprocess
import sys
from pathlib import Path

RECONCILE = Path(__file__).parent.parent / "lib" / "reconcile.py"


def run(tmp_path, plan, files):
    files_dir = tmp_path / "files"
    root = tmp_path / "root"
    for rel, content in files.items():
        p = files_dir / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(content)
    root.mkdir(exist_ok=True)
    plan_path = tmp_path / "plan.json"
    plan_path.write_text(json.dumps(plan))
    subprocess.run(
        [sys.executable, str(RECONCILE), "--files", str(files_dir),
         "--plan", str(plan_path), "--root", str(root)],
        check=True,
    )
    return root


def base_plan(**kw):
    plan = {"repo": "t", "managed": [], "scaffold": [], "retired": [], "unmanaged": []}
    plan.update(kw)
    return plan


def test_managed_file_is_written(tmp_path):
    root = run(tmp_path, base_plan(managed=[".gitignore"]), {".gitignore": "a\n"})
    assert (root / ".gitignore").read_text() == "a\n"


def test_managed_file_overwrites_local_edit(tmp_path):
    root = tmp_path / "root"
    root.mkdir()
    (root / ".gitignore").write_text("hand edited\n")
    run(tmp_path, base_plan(managed=[".gitignore"]), {".gitignore": "a\n"})
    assert (root / ".gitignore").read_text() == "a\n"


def test_managed_path_absent_from_files_is_deleted(tmp_path):
    root = tmp_path / "root"
    root.mkdir()
    (root / "Dockerfile").write_text("stale\n")
    run(tmp_path, base_plan(managed=["Dockerfile"]), {})
    assert not (root / "Dockerfile").exists()


def test_scaffold_file_is_written_when_absent(tmp_path):
    root = run(tmp_path, base_plan(scaffold=["cmd/main.go"]), {"cmd/main.go": "package main\n"})
    assert (root / "cmd" / "main.go").read_text() == "package main\n"


def test_scaffold_file_is_left_alone_when_present(tmp_path):
    root = tmp_path / "root"
    root.mkdir()
    (root / "cmd").mkdir()
    (root / "cmd" / "main.go").write_text("mine\n")
    run(tmp_path, base_plan(scaffold=["cmd/main.go"]), {"cmd/main.go": "package main\n"})
    assert (root / "cmd" / "main.go").read_text() == "mine\n"


def test_retired_file_is_deleted(tmp_path):
    root = tmp_path / "root"
    root.mkdir()
    (root / "old.yml").write_text("x\n")
    run(tmp_path, base_plan(retired=["old.yml"]), {})
    assert not (root / "old.yml").exists()


def test_unmanaged_file_is_never_touched(tmp_path):
    root = tmp_path / "root"
    root.mkdir()
    (root / "Dockerfile").write_text("mine\n")
    run(tmp_path, base_plan(unmanaged=["Dockerfile"]), {"Dockerfile": "generated\n"})
    assert (root / "Dockerfile").read_text() == "mine\n"


def test_second_run_changes_nothing(tmp_path):
    plan = base_plan(managed=[".gitignore"], scaffold=["cmd/main.go"])
    files = {".gitignore": "a\n", "cmd/main.go": "package main\n"}
    root = run(tmp_path, plan, files)
    before = {p: p.read_bytes() for p in root.rglob("*") if p.is_file()}
    run(tmp_path, plan, files)
    after = {p: p.read_bytes() for p in root.rglob("*") if p.is_file()}
    assert before == after
```

- [ ] **Step 2: Wire the pytest check and run it to verify it fails**

Add to `golden-base/flake.nix` inside `eachDefaultSystem`:

```nix
        checks.engine-python = pkgs.runCommand "engine-python-tests"
          { nativeBuildInputs = [ pkgs.python3Packages.pytest ]; }
          ''
            cp -r ${golden-engine.src} engine
            chmod -R +w engine
            cd engine
            pytest tests -q
            touch $out
          '';
```

Run: `nix build ./golden-base#checks.aarch64-darwin.engine-python -L`
Expected: FAIL — `reconcile.py` not found.

- [ ] **Step 3: Implement reconcile.py**

`golden-engine/lib/reconcile.py`:

```python
#!/usr/bin/env python3
"""Execute a golden plan against a repository working tree.

Nix builds and validates the plan; this script only carries it out. It names
no file layout of its own: every path it touches comes from the plan.

Pass order is load-bearing. Retired paths are removed before anything is
written, so a path that moved between classes in the same release does not
get deleted after it was just written.
"""

import argparse
import json
import shutil
from pathlib import Path


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--files", required=True, type=Path)
    ap.add_argument("--plan", required=True, type=Path)
    ap.add_argument("--root", required=True, type=Path)
    args = ap.parse_args()

    plan = json.loads(args.plan.read_text())
    actions = 0

    for rel in plan["retired"]:
        actions += remove(args.root / rel, rel, "retired")

    for rel in plan["managed"]:
        src = args.files / rel
        if src.exists():
            actions += write(src, args.root / rel, rel, "managed")
        else:
            actions += remove(args.root / rel, rel, "gated off")

    for rel in plan["scaffold"]:
        dst = args.root / rel
        if dst.exists():
            continue
        src = args.files / rel
        if src.exists():
            actions += write(src, dst, rel, "scaffold")

    print(f"generate: {plan['repo']}: {actions} change(s)")


def write(src: Path, dst: Path, rel: str, why: str) -> int:
    new = src.read_bytes()
    if dst.exists() and dst.read_bytes() == new:
        return 0
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(src, dst)
    dst.chmod(0o644)
    print(f"  {why}: {rel}")
    return 1


def remove(dst: Path, rel: str, why: str) -> int:
    if not dst.exists():
        return 0
    dst.unlink()
    print(f"  {why}: removed {rel}")
    return 1


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `nix build ./golden-base#checks.aarch64-darwin.engine-python -L`
Expected: PASS, 8 tests.

- [ ] **Step 5: Commit**

```bash
git add golden-engine/lib/reconcile.py golden-engine/tests golden-base/flake.nix
git commit -m "feat(FOM-51): reconcile a rendered tree into a repo by ownership class

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: The generate app, end to end

**Files:**
- Modify: `golden-engine/mkGolden.nix`
- Modify: `golden-base/flake.nix`

**Interfaces:**
- Produces: `generateApp` — a flake app. Run from a repo root, it reconciles and prints a summary. This is what consumers call as `nix run .#generate`.

- [ ] **Step 1: Write the failing end-to-end check**

Add to `golden-base/flake.nix`:

```nix
        checks.generate-is-idempotent =
          let
            golden = golden-engine.lib.mkGolden { packs = [ self.pack ]; } pkgs (import ./tests/fixtures/repo.nix);
          in
          pkgs.runCommand "generate-is-idempotent" { nativeBuildInputs = [ pkgs.python3 ]; } ''
            mkdir -p repo && cd repo
            python3 ${golden-engine.src}/lib/reconcile.py \
              --files ${golden.filesDrv} --plan ${golden.plan} --root .
            find . -type f | sort > ../first
            sha256sum $(find . -type f | sort) > ../first-sums

            python3 ${golden-engine.src}/lib/reconcile.py \
              --files ${golden.filesDrv} --plan ${golden.plan} --root . | tee ../second-log
            sha256sum $(find . -type f | sort) > ../second-sums

            diff ../first-sums ../second-sums
            grep -q '0 change(s)' ../second-log
            touch $out
          '';
```

- [ ] **Step 2: Run it to verify it fails**

Run: `nix build ./golden-base#checks.aarch64-darwin.generate-is-idempotent -L`
Expected: FAIL — `attribute 'plan' missing` or the reconcile path does not resolve.

- [ ] **Step 3: Add generateApp to mkGolden**

In `golden-engine/mkGolden.nix`, add to the `let`:

```nix
  generateApp = {
    type = "app";
    program = toString (pkgs.writeShellScript "golden-generate" ''
      set -euo pipefail
      if [ ! -e repo.nix ]; then
        echo "generate: run this from the repo root (no repo.nix here)" >&2
        exit 1
      fi
      exec ${pkgs.python3}/bin/python3 ${./lib/reconcile.py} \
        --files ${filesDrv} \
        --plan ${plan} \
        --root .
    '');
  };
```

and add `generateApp` to the returned attrset.

- [ ] **Step 4: Run it to verify it passes**

Run: `nix build ./golden-base#checks.aarch64-darwin.generate-is-idempotent -L`
Expected: PASS.

- [ ] **Step 5: Prove it by hand**

```bash
mkdir -p /tmp/golden-smoke && cd /tmp/golden-smoke
printf '{ name = "smoke"; }\n' > repo.nix
nix run /Users/forrest/dev/personal/flake-hub/golden-base#generate 2>/dev/null || true
```

The app is exposed per-consumer, not by the pack, so this will fail on the missing output. Instead assert the check output directly:

```bash
nix build ./golden-base#checks.aarch64-darwin.generate-is-idempotent -L
```

Expected: `0 change(s)` in the log of the second run.

- [ ] **Step 6: Commit**

```bash
git add golden-engine/mkGolden.nix golden-base/flake.nix
git commit -m "feat(FOM-51): expose the generate app and prove it is idempotent

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: The real golden-base file set

**Files:**
- Create: `golden-base/templates/.editorconfig.jinja`
- Create: `golden-base/templates/.envrc.jinja`
- Create: `golden-base/templates/justfile.jinja`
- Create: `golden-base/templates/README.md.jinja`
- Modify: `golden-base/pack.nix`
- Modify: `golden-base/tests/expected/gitignore-default/` → rename to `golden-base/tests/expected/default/`
- Modify: `golden-base/flake.nix`

**Interfaces:**
- Consumes: everything from Tasks 5–8.
- Produces: `golden-base` schema keys `name` (string, required), `description` (string), `unmanaged` (list), `just.recipes` (list of strings).

- [ ] **Step 1: Write the failing snapshot**

Rename the expected directory and add the four new expected files. `golden-base/tests/expected/default/justfile`:

```
# GENERATED FILE — managed by flake-hub (golden-base).
# Do not edit manually: `nix run .#generate` overwrites it.
# To change it, edit repo.nix, or the template in the pack that owns it.

import? 'just/base.just'

project := "snapshot-repo"

fetch:
    curl -sSfL https://raw.githubusercontent.com/Fomiller/justfiles/refs/heads/main/base.just > just/base.just

generate:
    nix run .#generate
```

`golden-base/tests/expected/default/.envrc`:

```
# GENERATED FILE — managed by flake-hub (golden-base).
# Do not edit manually: `nix run .#generate` overwrites it.
# To change it, edit repo.nix, or the template in the pack that owns it.

use flake
```

`golden-base/tests/expected/default/.editorconfig`:

```
# GENERATED FILE — managed by flake-hub (golden-base).
# Do not edit manually: `nix run .#generate` overwrites it.
# To change it, edit repo.nix, or the template in the pack that owns it.

root = true

[*]
end_of_line = lf
insert_final_newline = true
charset = utf-8
indent_style = space
indent_size = 2

[*.go]
indent_style = tab

[*.py]
indent_size = 4
```

`golden-base/tests/expected/default/README.md`:

```
# snapshot-repo

Managed by [flake-hub](https://github.com/Fomiller/flake-hub). Run `nix run .#generate`
after changing `repo.nix`.
```

README is `scaffold`, not `managed` — it is written once and then belongs to the repo. It therefore carries no header comment, since Markdown has no comment syntax that renders invisibly everywhere.

Point the existing `render-snapshot` check at `./tests/expected/default`.

- [ ] **Step 2: Run the snapshot to verify it fails**

Run: `nix build ./golden-base#checks.aarch64-darwin.render-snapshot -L`
Expected: FAIL — `Only in .../expected/default: justfile` and three more.

- [ ] **Step 3: Write the templates**

`golden-base/templates/justfile.jinja`:

```jinja
{% include "_header.jinja" %}

import? 'just/base.just'

project := "{{ name }}"

fetch:
    curl -sSfL https://raw.githubusercontent.com/Fomiller/justfiles/refs/heads/main/base.just > just/base.just

generate:
    nix run .#generate
{% for recipe in just.recipes %}

{{ recipe }}
{% endfor %}
```

`golden-base/templates/.envrc.jinja`:

```jinja
{% include "_header.jinja" %}

use flake
```

`golden-base/templates/.editorconfig.jinja`:

```jinja
{% include "_header.jinja" %}

root = true

[*]
end_of_line = lf
insert_final_newline = true
charset = utf-8
indent_style = space
indent_size = 2

[*.go]
indent_style = tab

[*.py]
indent_size = 4
```

`golden-base/templates/README.md.jinja`:

```jinja
# {{ name }}

{% if description %}{{ description }}

{% endif %}Managed by [flake-hub](https://github.com/Fomiller/flake-hub). Run `nix run .#generate`
after changing `repo.nix`.
```

- [ ] **Step 4: Update pack.nix**

```nix
{
  name = "golden-base";
  templates = ./templates;
  partials = ./partials;
  defaults = {
    description = "";
    just.recipes = [ ];
    unmanaged = [ ];
  };
  registry = { };
  ownership = {
    managed = [ ".gitignore" ".editorconfig" ".envrc" "justfile" ];
    scaffold = [ "README.md" ];
    retired = [ ];
  };
  overrides = [ ];
  schema = {
    "name" = { type = "string"; required = true; };
    "description" = { type = "string"; };
    "just.recipes" = { type = "list"; };
    "unmanaged" = { type = "list"; };
  };
}
```

- [ ] **Step 5: Run every check**

Run: `nix flake check ./golden-base -L && nix run ./golden-base#test-eval`
Expected: PASS on all three checks and all eval units.

- [ ] **Step 6: Add a second snapshot case covering the knobs**

Create `golden-base/tests/fixtures/repo-customized.nix`:

```nix
{
  name = "custom-repo";
  description = "A repo that exercises the knobs.";
  just.recipes = [ "smoke:\n    ./scripts/smoke.sh" ];
  unmanaged = [ ".editorconfig" ];
}
```

Create `golden-base/tests/expected/customized/` containing `.gitignore`, `.envrc`, `justfile` (with the `smoke` recipe appended) and `README.md` (with the description paragraph). **`.editorconfig` must be absent** — it is unmanaged, so it never enters the plan.

Add the matching check to `golden-base/flake.nix`, mirroring `render-snapshot` but against `repo-customized.nix` and `./tests/expected/customized`.

Run: `nix flake check ./golden-base -L`
Expected: PASS, 4 checks.

- [ ] **Step 7: Commit**

```bash
git add golden-base
git commit -m "feat(FOM-51): fill out the golden-base file set

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 10: The init app

**Files:**
- Create: `golden-base/init.py`
- Create: `golden-base/pack-versions.nix`
- Create: `golden-base/tests/init_test.py`
- Modify: `golden-base/flake.nix`
- Create: `golden-engine/VERSION`, `golden-base/VERSION`

**Interfaces:**
- Consumes: `pack-versions.nix` — `{ golden-engine = "0.1.0"; golden-base = "0.1.0"; }`. Generated by `release-flake.yaml` in a later plan; hand-written now.
- Produces: `nix run 'github:Fomiller/flake-hub?dir=golden-base#init' -- --name <n> [--packs github,service]`, which writes `flake.nix` and `repo.nix` into the current directory. It refuses to overwrite either.

- [ ] **Step 1: Write the failing tests**

`golden-base/tests/init_test.py`:

```python
import subprocess
import sys
from pathlib import Path

INIT = Path(__file__).parent.parent / "init.py"
VERSIONS = Path(__file__).parent.parent / "pack-versions.nix"


def run(cwd, *args, expect_fail=False):
    r = subprocess.run(
        [sys.executable, str(INIT), "--versions", str(VERSIONS), *args],
        cwd=cwd, capture_output=True, text=True,
    )
    if expect_fail:
        assert r.returncode != 0, r.stdout
    else:
        assert r.returncode == 0, r.stderr
    return r


def test_writes_both_files(tmp_path):
    run(tmp_path, "--name", "foo")
    assert (tmp_path / "flake.nix").exists()
    assert (tmp_path / "repo.nix").exists()


def test_repo_nix_carries_the_name(tmp_path):
    run(tmp_path, "--name", "foo")
    assert 'name = "foo";' in (tmp_path / "repo.nix").read_text()


def test_base_and_engine_are_always_inputs(tmp_path):
    run(tmp_path, "--name", "foo")
    flake = (tmp_path / "flake.nix").read_text()
    assert "dir=golden-engine&ref=refs/tags/golden-engine-" in flake
    assert "dir=golden-base&ref=refs/tags/golden-base-" in flake


def test_extra_packs_are_added_as_inputs(tmp_path):
    run(tmp_path, "--name", "foo", "--packs", "github,service")
    flake = (tmp_path / "flake.nix").read_text()
    assert "golden-github.url" in flake
    assert "golden-service.url" in flake


def test_unknown_pack_is_rejected(tmp_path):
    r = run(tmp_path, "--name", "foo", "--packs", "nonsense", expect_fail=True)
    assert "nonsense" in r.stderr


def test_refuses_to_clobber_existing_files(tmp_path):
    (tmp_path / "repo.nix").write_text("{ name = \"mine\"; }\n")
    run(tmp_path, "--name", "foo", expect_fail=True)
    assert (tmp_path / "repo.nix").read_text() == "{ name = \"mine\"; }\n"
```

- [ ] **Step 2: Add the check and run it to verify it fails**

Add to `golden-base/flake.nix`:

```nix
        checks.init = pkgs.runCommand "init-tests"
          { nativeBuildInputs = [ pkgs.python3Packages.pytest ]; }
          ''
            cp -r ${./.} base && chmod -R +w base && cd base
            pytest tests/init_test.py -q
            touch $out
          '';
```

Run: `nix build ./golden-base#checks.aarch64-darwin.init -L`
Expected: FAIL — `init.py` not found.

- [ ] **Step 3: Write pack-versions.nix and the VERSION files**

`golden-base/pack-versions.nix`:

```nix
# GENERATED FILE — written by release-flake.yaml when any pack is released.
{
  golden-engine = "0.1.0";
  golden-base = "0.1.0";
}
```

`golden-engine/VERSION` and `golden-base/VERSION` both contain `0.1.0`.

- [ ] **Step 4: Implement init.py**

`golden-base/init.py`:

```python
#!/usr/bin/env python3
"""Seed a repo with the three files a flake-hub consumer holds.

Pack versions come from pack-versions.nix, which release-flake.yaml
regenerates. A stale init writes stale pins and the first Renovate run
corrects them.
"""

import argparse
import re
import sys
from pathlib import Path

REPO = "github:Fomiller/flake-hub"
ALWAYS = ["golden-engine", "golden-base"]


def read_versions(path: Path) -> dict[str, str]:
    return dict(re.findall(r'(\S+)\s*=\s*"([^"]+)";', path.read_text()))


def input_line(pack: str, version: str) -> str:
    return f'    {pack}.url = "{REPO}?dir={pack}&ref=refs/tags/{pack}-{version}";'


def render_flake(packs: list[str], versions: dict[str, str]) -> str:
    inputs = "\n".join(input_line(p, versions[p]) for p in packs)
    args = ", ".join(["self", "nixpkgs", "flake-utils"] + packs)
    pack_list = " ".join(f"{p}.pack" for p in packs if p != "golden-engine")
    return f"""{{
  inputs = {{
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
{inputs}
  }};

  outputs = {{ {args} }}:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${{system}};
        golden = golden-engine.lib.mkGolden {{
          packs = [ {pack_list} ];
        }} pkgs (import ./repo.nix);
      in
      {{
        apps.generate = golden.generateApp;
        packages.golden-files = golden.filesDrv;
      }});
}}
"""


def render_repo_nix(name: str) -> str:
    return f'{{\n  name = "{name}";\n  codeowners = [ "@Fomiller" ];\n}}\n'


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--name", required=True)
    ap.add_argument("--packs", default="", help="comma-separated, without the golden- prefix")
    ap.add_argument("--versions", type=Path, default=Path(__file__).parent / "pack-versions.nix")
    args = ap.parse_args()

    versions = read_versions(args.versions)
    extra = [f"golden-{p.strip()}" for p in args.packs.split(",") if p.strip()]
    unknown = [p for p in extra if p not in versions]
    if unknown:
        sys.exit(f"init: unknown pack(s): {', '.join(unknown)}. Known: {', '.join(sorted(versions))}")

    packs = ALWAYS + [p for p in extra if p not in ALWAYS]

    targets = {Path("flake.nix"): render_flake(packs, versions),
               Path("repo.nix"): render_repo_nix(args.name)}
    existing = [str(p) for p in targets if p.exists()]
    if existing:
        sys.exit(f"init: refusing to overwrite {', '.join(existing)}")

    for path, content in targets.items():
        path.write_text(content)
        print(f"init: wrote {path}")
    print("init: now run `nix run .#generate`")


if __name__ == "__main__":
    main()
```

Note `golden-engine` is an input but contributes no `.pack`, which is why `pack_list` filters it out.

- [ ] **Step 5: Expose init as an app**

Add to `golden-base/flake.nix`:

```nix
        apps.init = {
          type = "app";
          program = toString (pkgs.writeShellScript "golden-init" ''
            exec ${pkgs.python3}/bin/python3 ${./init.py} \
              --versions ${./pack-versions.nix} "$@"
          '');
        };
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `nix build ./golden-base#checks.aarch64-darwin.init -L`
Expected: PASS, 6 tests.

- [ ] **Step 7: Smoke test the real loop**

```bash
mkdir -p /tmp/golden-init && cd /tmp/golden-init && git init -q
nix run /Users/forrest/dev/personal/flake-hub/golden-base#init -- --name smoke
nix run .#generate
ls -a
nix run .#generate
```

Expected: the second `generate` prints `0 change(s)`, and `ls -a` shows `.editorconfig`, `.envrc`, `.gitignore`, `README.md`, `justfile`, `flake.nix`, `repo.nix`.

Note the generated `flake.nix` pins tags that do not exist yet, so this smoke test needs `--override-input golden-base path:/Users/forrest/dev/personal/flake-hub/golden-base` (and the same for `golden-engine`) until the first release lands in plan 2.

- [ ] **Step 8: Commit**

```bash
git add golden-base golden-engine/VERSION
git commit -m "feat(FOM-51): add the init app that seeds a consumer repo

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 11: Repo README and engine README

**Files:**
- Create: `README.md`
- Create: `golden-engine/README.md`
- Create: `golden-base/README.md`

- [ ] **Step 1: Write the hub README**

`README.md` — a table of the flakes in the repo, the `?dir=` referencing rule with a copy-pasteable input line, and a pointer to `docs/` (which arrives in plan 4). Cover: each flake lives in its own top-level directory, consumers must use `?dir=` plus a tag, tags are `<dir>-<version>`, and a local checkout uses `path:/abs/path/to/flake-hub/<dir>`.

- [ ] **Step 2: Write golden-engine/README.md**

Aimed at someone changing the engine, not consuming it. Must state: the two rules that keep it team-agnostic (no file layout, no pack-name lists), the `filesDrv` / `plan` split, that every guard needs a forcing binding and a red test, and how to read a repo's plan:

```bash
nix build ./golden-base#checks.$(nix eval --raw --impure --expr builtins.currentSystem).render-snapshot
```

- [ ] **Step 3: Write golden-base/README.md**

Aimed at a consumer. The file set it owns, the schema table (`name`, `description`, `just.recipes`, `unmanaged`), and the `init` invocation.

- [ ] **Step 4: Verify the whole repo one more time**

Run: `nix flake check ./golden-base -L && nix run ./golden-base#test-eval && nixpkgs-fmt --check golden-engine golden-base`
Expected: PASS on all.

- [ ] **Step 5: Commit**

```bash
git add README.md golden-engine/README.md golden-base/README.md
git commit -m "docs(FOM-51): document the hub layout, the engine contract and golden-base

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Deferred to later plans

- `golden-github`, the four gh-actions workflows, `flake-hub-example` — plan 2.
- `golden-service`, `golden-infra`, `golden-argocd` — plan 3.
- mdbook docs and the `mdbook.yaml` fix — plan 4.
- Renovate in the homelab cluster — plan 5.
- `release-flake.yaml` generating `pack-versions.nix` — plan 2. Until then it is hand-edited.
