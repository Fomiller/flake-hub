# golden-engine

The driver behind the golden-file generator. This README is for someone
changing the engine, not for someone consuming a pack. If you just want files
in your repo, see `golden-base/README.md` or the pack you're using instead.

## Entry point

```nix
golden-engine.lib.mkGolden { packs = [ ... ]; } pkgs repoConfig
```

`packs` is a list of pack attrsets (see `golden-base/pack.nix` for the shape).
`pkgs` is a nixpkgs instance. `repoConfig` is the consuming repo's `repo.nix`.
It returns:

| Attribute      | What it is                                              |
| -------------- | -------------------------------------------------------- |
| `filesDrv`     | A derivation holding every rendered file, from every pack, merged. |
| `plan`         | A derivation holding the ownership classification as JSON. |
| `generateApp`  | An `apps`-shaped attrset that reconciles a working tree against `filesDrv` and `plan`. |
| `mergedConfig` | The repo's config after defaults, registry values, and schema validation. |

## The two team-agnostic rules

The engine hardcodes no file layout and no pack names.

- **No file layout.** Every path, glob, and directory name the engine ever
  touches comes from a pack (`templates`, `partials`, `ownership` globs). The
  engine's own code has no `.gitignore`, no `README.md`, no notion of what a
  repo looks like. The one exception is `repo.nix`: `mkGolden.nix`'s
  `generateApp` checks for it to tell "you're at the repo root" from "you're
  somewhere else". That name is the engine↔consumer contract, and it's the
  only filename the engine is allowed to know.
- **No pack-name lists.** The engine doesn't know `golden-base` or any other
  pack exists. `packs` is just a list passed in by whoever calls `mkGolden`.
  Adding a new pack never means touching engine code.

If you're adding something to the engine and it needs to know a specific
path or pack name to work, that's a sign it belongs in a pack, not here.

## Why `filesDrv` and `plan` are separate

`filesDrv` is the raw makejinja render of every template in every pack. It
knows nothing about ownership — it's just "here's what these templates
produce for this config."

`plan` is the ownership classification: which paths are `managed`,
`scaffold`, `retired`, or `unmanaged`. It's built from the packs' ownership
globs, independently of the render.

`reconcile.py` is the only thing that combines them. It reads the plan and
copies files out of `filesDrv` accordingly. Keeping the render and the
ownership decision apart means you can inspect either one on its own —
what would this template produce, versus what would happen to a repo — without
running the other.

## Ownership classes

| Class       | Behavior                                                     |
| ----------- | -------------------------------------------------------------- |
| `managed`   | Overwritten every run. If the template renders empty, the file is deleted. |
| `scaffold`  | Written once. After that, it's the repo's — `generate` never touches it again. |
| `retired`   | Deleted, if present.                                          |
| `unmanaged` | Never touched. Declared per-repo in `repo.nix`, not per-pack.  |

## Retiring a whole tree

A pack can declare that a directory stops belonging to the repo when a config
key is off:

```nix
retireTrees = [
  { unless = "argocd.enabled"; trees = [ "argocd" "helm" ]; }
];
```

`unless` is a dotted key that must resolve to a bool in the merged config.
When it is `false`, every listed directory is deleted recursively — hand-written
files included. That is the difference from a `managed` file rendering empty,
which only removes the generated file.

It is data rather than a function because `pack.nix` is imported with no
arguments. The gate is evaluated in `plan.nix`, which emits `retiredTrees` in
the plan; `reconcile.py` removes them before writing anything, same as
`retired`.

Guards: the gate must exist and be a bool, a tree must be a plain relative
directory (no glob, no `..`), and a repo cannot declare something `unmanaged`
underneath a tree that is being deleted.

## Schema types

`string`, `bool`, `int`, `list`, `attrs`, `enum` (with `values`), and
`attrsOf`.

`attrsOf` is one block shape repeated under names, which is what
`infra.environments` and `argocd.slack` need:

```nix
"infra.environments" = {
  type = "attrsOf";
  keys = [ "dev" "staging" "prod" ];   # optional; omit to allow any name
  fields = {
    enabled = { type = "bool"; description = "..."; };
    account = { type = "string"; description = "..."; };
  };
  description = "...";
};
```

Every block is checked against `fields` — an unknown field or a wrong type is
named with its full dotted path. With `keys` set, a name outside the list is an
error, which is how a typo'd environment gets caught.

## Templated paths

A template path may carry `{{ key }}` components, for any top-level string in
the merged config — `templates/helm/{{ name }}/Chart.yaml.jinja` lands at
`helm/my-service/Chart.yaml`.

makejinja renders file contents but copies path names through untouched, so
the engine does this substitution itself, in two places that have to agree:
`render_paths.py` renames the rendered tree, and `plan.nix` rewrites the
emitted paths before classifying them. Both use the rule in `pathvars.nix`.
If they disagreed, the plan would point at a file the tree never produced.

Only top-level strings substitute. A path still holding `{{` after
substitution is an error, not a silent miss.

Ownership globs match the substituted path, so a pack writes
`helm/*/Chart.yaml` rather than repeating the variable.

## The executable bit

A pack declares an `executable` list of globs beside `ownership`. It is not a
fifth class: a path is classified `managed` or `scaffold` *and*, separately,
executable. Anything matched lands `0755`; everything else lands `0644`.

`plan.nix` resolves the globs to concrete paths, so the plan JSON carries a
flat `executable` list and `reconcile.py` needs no globbing. A glob matching
nothing emitted is an error, same as a stale `unmanaged` entry — both are
typos nobody would otherwise notice.

Mode counts as drift on its own. A file whose bytes are right but whose mode
is wrong gets chmod'd and reported as a change; otherwise the drift check
would call the repo clean.

## Guards

Validation in this engine (schema checks, ownership-glob checks, pack-merge
conflict checks) happens as lazy `throw`s in Nix. A `throw` that nothing
forces never fires — it just sits there unevaluated. Every guard needs two
things:

1. A binding that forces it. `mkGolden.nix` does this with `planChecksum`,
   which hashes the plan and puts it in the `filesDrv` derivation's
   environment, so building `filesDrv` can't skip validating the plan.
2. A test that goes red if the guard is deleted. A guard with no test that
   fails when the guard is removed isn't verified — it's a comment that
   happens to be Nix syntax.

This has bitten the project more than once: a guard existed, but nothing
forced it, and it silently stopped checking anything. Treat "forces it" and
"has a red test" as required, not optional, for any new guard.

## Reading a repo's plan

The fastest way to see what the engine renders for a given `repo.nix` is to
build one of the pack's existing checks and diff it. For example,
`golden-base`'s `render-snapshot` check builds the full render for its test
fixture and diffs it against the expected output:

```bash
nix build ./golden-base#checks.$(nix eval --raw --impure --expr builtins.currentSystem).render-snapshot
```

To see the plan itself rather than the render, evaluate `golden.plan` in a
`nix repl` against a pack and a `repo.nix` of your choosing, or read
`golden-engine/lib/plan.nix` directly — it's short.

## Tests

- `golden-engine/tests` — Python unit tests for `reconcile.py`, run via
  `pytest` (also wired into `golden-base`'s `checks.engine-python`).
- `golden-base`'s checks (`nix flake check ./golden-base`) exercise the
  engine end to end against real fixtures: rendering, idempotency,
  customization, and the `generate` app itself.
