# golden-base

A pack for `golden-engine`. Files every repo gets, whatever it is. If you're
consuming this pack, this README is for you. If you're changing the engine
itself, see `golden-engine/README.md`.

## What it owns

| File            | Class      | Behavior                                    |
| --------------- | ---------- | -------------------------------------------- |
| `.gitignore`    | managed    | Regenerated every run.                       |
| `.editorconfig` | managed    | Regenerated every run.                       |
| `.envrc`        | managed    | Regenerated every run.                       |
| `justfile`      | managed    | Regenerated every run.                       |
| `README.md`     | scaffold   | Written once by `generate`, then yours to edit. |

## Config schema

`golden-base` reads these keys out of the consuming repo's `repo.nix`:

| Key             | Type   | Required | Notes                                |
| --------------- | ------ | -------- | ------------------------------------- |
| `name`          | string | yes      | Repo name. Used in the generated `README.md` and elsewhere. |
| `description`   | string | no       | Shown in the generated `README.md` if set. |
| `gitignore`     | list   | no       | Lines written to `.gitignore`, one per entry. |
| `just.recipes`  | list   | no       | Extra recipes rendered into `justfile`. |
| `unmanaged`     | list   | no       | Generated paths to leave alone. See `golden-engine/README.md` for what "unmanaged" means. |

List keys are additive across packs, so a pack adds its own build output to
`gitignore` instead of shipping a competing `.gitignore`. `repo.nix` is not
additive: setting `gitignore` there replaces the whole list.

## Setting up a new repo

From an empty repo:

```bash
nix run 'github:Fomiller/flake-hub?dir=golden-base&ref=refs/tags/golden-base-<version>#init' -- \
  --name my-repo
```

This writes a `flake.nix` that wires up `golden-engine` and `golden-base`,
and a starter `repo.nix`. To pull in another pack at the same time (once one
exists), pass it by name without the `golden-` prefix:

```bash
nix run '...#init' -- --name my-repo --packs github,service
```

`init` refuses to run if `flake.nix` or `repo.nix` already exists in the
target directory, so it's safe to run only once per repo.

After `init`, run `nix run .#generate` to write the actual files.
