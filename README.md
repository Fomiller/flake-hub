# flake-hub

A declarative golden-file generator built on Nix flakes. Each repo you manage
with it points at one or more "packs" — flakes that own a set of files — and
runs `nix run .#generate` to bring its working tree in line.

## Flakes in this repo

Each flake lives in its own top-level directory.

| Directory      | What it is                                             |
| -------------- | ------------------------------------------------------- |
| `golden-engine`| The driver. Merges packs, renders templates, builds the ownership plan. |
| `golden-base`  | A pack. Files every repo gets, no matter what it is.    |

More packs are planned (a GitHub-workflows pack, a service pack, an infra
pack, an ArgoCD pack) but only `golden-engine` and `golden-base` exist today.

## Referencing a flake

A consumer flake never points at the repo root. It points at one directory,
using the `?dir=` query parameter, pinned to a tag:

```
github:Fomiller/flake-hub?dir=<dir>&ref=refs/tags/<dir>-<version>
```

Tags are named `<dir>-<version>` (for example `golden-base-0.1.0`), so each
flake in the repo is versioned and released independently.

Example input line:

```nix
golden-base.url = "github:Fomiller/flake-hub?dir=golden-base&ref=refs/tags/golden-base-0.1.0";
```

For local development against a checkout instead of a tag, use a `path:`
input:

```nix
golden-base.url = "path:/abs/path/to/flake-hub/golden-base";
```

If you're testing a consumer repo against a local checkout, you need a third
override, not just the obvious two:

```bash
nix run .#generate \
  --override-input golden-engine path:/abs/path/to/flake-hub/golden-engine \
  --override-input golden-base   path:/abs/path/to/flake-hub/golden-base \
  --override-input golden-base/golden-engine path:/abs/path/to/flake-hub/golden-engine
```

`golden-base`'s own flake pins `golden-engine` as a relative-path input, and a
top-level `--override-input` doesn't reach a transitive input of another
input. Skip the third override and `golden-base` comes from your checkout
while `golden-engine` comes from wherever `golden-base`'s lock file points —
the two can silently disagree.

## Docs

Fuller docs (how packs, ownership classes, and the reconcile step fit
together) are planned but not written yet.

## Contributing

See `golden-engine/README.md` if you're changing the engine, or
`golden-base/README.md` if you're consuming or changing the base pack.
