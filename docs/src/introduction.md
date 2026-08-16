# flake-hub

flake-hub generates the files every repo needs and keeps them current. A repo
holds three files of its own — `flake.nix`, `flake.lock` and `repo.nix` — and
everything else that is boilerplate is rendered from templates that live here.

The hub is not one flake. Each top-level directory is its own flake with its own
version and its own tag, so a repo picks the pieces it wants and upgrades them
one at a time. `golden-engine` does the work; the `golden-*` packs supply
templates, defaults and ownership rules.

When a pack is released, Renovate opens a PR on every repo pinned to it. The
repo's own workflow regenerates the files in that PR, so the diff a reviewer
sees is the actual change, not a version bump they have to imagine.

## The flakes

| Flake | Input |
| --- | --- |
| `golden-engine` | `github:Fomiller/flake-hub?dir=golden-engine&ref=refs/tags/golden-engine-<version>` |
| `golden-base` | `github:Fomiller/flake-hub?dir=golden-base&ref=refs/tags/golden-base-<version>` |
| `golden-github` | `github:Fomiller/flake-hub?dir=golden-github&ref=refs/tags/golden-github-<version>` |
| `golden-service` | `github:Fomiller/flake-hub?dir=golden-service&ref=refs/tags/golden-service-<version>` |
| `golden-infra` | `github:Fomiller/flake-hub?dir=golden-infra&ref=refs/tags/golden-infra-<version>` |
| `golden-argocd` | `github:Fomiller/flake-hub?dir=golden-argocd&ref=refs/tags/golden-argocd-<version>` |

Every pack is tagged `<pack>-<semver>` on this one repo. That is why the
Renovate preset anchors its version match per pack: the tags all share a
namespace.

## The three files a repo holds

- `flake.nix` — the pins, and the `mkGolden` call listing which packs apply.
- `flake.lock` — what Renovate updates.
- `repo.nix` — the repo's own configuration: its name, its owners, its
  language, its environments. Everything else is generated from it.
