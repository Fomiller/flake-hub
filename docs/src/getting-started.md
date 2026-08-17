# Getting started

## Seed a repo

From an empty repo:

```sh
nix run github:Fomiller/flake-hub?dir=golden-base#init -- \
  --name my-service --packs github,service
```

`--packs` takes the pack names without the `golden-` prefix, comma separated.
`golden-engine` and `golden-base` are always included. The command writes
`flake.nix` and `repo.nix` and refuses to overwrite either if it already
exists.

A pack input is one line — no `follows`. A consumer reads only `<pack>.pack`,
which is a plain import of the pack's `pack.nix`, so a pack flake's own
`nixpkgs` never reaches your build. The engine that runs is the `golden-engine`
you pinned.

`golden-service` marks `language` required and has no default for it, so add it
to `repo.nix` before the first run:

```nix
language = "go";
```

Language code goes under `src/`, with Go's main package at
`src/cmd/<name>/`. `go.mod` stays at the repo root.

Then generate:

```sh
nix run .#generate
```

That writes the files the selected packs own and prints one line per change.
Run it from the repo root — it looks for `repo.nix` there and exits if it is
missing.

## Required keys

A pack can mark a key required. If it is missing, generation fails at eval with
the key named:

```
mkGolden: repo.nix is not valid:
  required key 'language' is not set in repo.nix or any pack default
```

`init` seeds `github.codeowners` when you select `golden-github`, because that one has
no sensible default. The rest you add yourself — a guessed value for something
like `infra.dopplerProject` would be worse than the error.

## Change something

Edit `repo.nix`, then regenerate:

```sh
nix run .#generate
```

Do not hand-edit a generated file. The next run overwrites it. If the output is
wrong, either `repo.nix` is wrong or the pack's template is.

## What happens on a pull request

The generated `.github/workflows/generate.yml` runs on any PR that touches
`flake.nix`, `flake.lock` or `repo.nix`. It regenerates and:

- on a Renovate PR, commits the result back, so the version bump and the file
  changes land together;
- on a human PR, reports the drift without committing.

A PR that changes neither pins nor `repo.nix` does not run it at all.
