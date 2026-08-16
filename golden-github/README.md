# golden-github

The files GitHub itself reads. Add this pack when a repo lives on GitHub and
wants review routing and dependency updates wired up the same way as every
other repo.

## Files it owns

| Path | Class | Notes |
| --- | --- | --- |
| `CODEOWNERS` | managed | `* <owners>`, from `codeowners` |
| `renovate.json` | managed | extends the hub's shared preset |
| `.github/workflows/generate.yml` | managed | regenerates on PRs touching `flake.nix`, `flake.lock` or `repo.nix`; commits back only on Renovate's PRs |
| `.github/workflows/ci.yml` | managed | one job per entry in `ci.jobs`; not emitted at all when no pack contributed one |

## Schema

| Key | Type | Required | Default |
| --- | --- | --- | --- |
| `codeowners` | list | yes | — |
| `ci.jobs` | list | no | `[ ]` |
| `ci.extraSteps.pre` | list | no | `[ ]` |
| `ci.extraSteps.post` | list | no | `[ ]` |

`init --packs github` seeds `codeowners` for you, since a repo that selects this
pack cannot generate without it.

## Generated files with no header

Every other generated file starts with a comment saying it is generated and
should not be hand-edited. `renovate.json` does not, because JSON has no comment
syntax and Renovate rejects a file with one. There is nothing in the file itself
to tell you it is managed — `nix run .#generate` will overwrite your edits.
Change the template here instead.

## The header partial

This pack ships `partials/_github_header.jinja`, its own copy of the header,
naming this pack. Packs do not share partials: the engine searches every pack's
partials directory and takes the first match, so one shared name would mean one
pack stamping another pack's files with the wrong name. The engine rejects two
packs shipping the same partial path for that reason.
