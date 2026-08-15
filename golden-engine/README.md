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
  engine's own code has no `.gitignore`, no `README.md`, nothing filename-
  shaped in it anywhere.
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
