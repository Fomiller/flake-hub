# flake-hub design

Date: 2026-08-15
Linear: [FOM-51](https://linear.app/fomiller/issue/FOM-51/create-a-declarative-repository-platform-generator-using-nix-flakes-to)

## Problem

Every personal repo re-invents the same files by hand: GitHub workflows, `CODEOWNERS`,
`justfile`, Dockerfile, terragrunt scaffolding, Argo CD deploy manifests. When a pattern
improves in one repo, the others never learn about it. There is no way to answer "which
repos are still on the old CI shape?" short of opening each one.

The fix is a generator: a small set of Nix flakes that own those files, a pinned version
per consumer repo, and CI that fails when a repo drifts from what its pin says it should
contain.

## Goals

- Central Nix flakes generate standard repo files from a per-repo `repo.nix`.
- Consumers hold three files: `flake.nix`, `flake.lock`, `repo.nix`.
- Generation is deterministic: `generate(generate(repo)) == generate(repo)`.
- Generated files carry an ownership header.
- CI detects drift when generated files were hand-edited or the pin moved.
- Version bumps propagate automatically and land regenerated files in the same PR.
- Packs compose: a repo takes only the packs it needs.

## Non-goals

- Migrating `homelab` to consume the generator. Follow-up work.
- Generating terragrunt units, stacks, or terraform modules. Scaffolding and CI only.
- Running generation inside Renovate. Renovate must not execute repo code.
- Writing into other repos from a consumer's `generate` run. No cross-repo commits.

## Architecture

### Hub layout — one flake per directory

```
flake-hub/
  golden-engine/         # driver. no inputs, no file-layout knowledge
    flake.nix            # lib.mkGolden, lib.guardTests
    mkGolden.nix         # pack merge, config merge, render, plan emission, guards
    lib/reconcile.py     # executes the plan against the rendered tree
    tests/
  golden-base/           # pack: justfile, .gitignore, .editorconfig, .envrc, README
  golden-github/         # pack: .github/workflows, CODEOWNERS, renovate.json
  golden-service/        # pack: Dockerfile, language table (go/rust), build CI steps
  golden-infra/          # pack: terragrunt scaffold, deploy-infra workflow
  golden-argocd/         # pack: deploy/chart, chart publish, Application manifest
  docs/                  # mdbook, a page per flake
  justfile
  .github/workflows/
```

Every pack directory has the same shape:

```
<pack>/
  flake.nix
  pack.nix          # the pack contract (below)
  registry.nix      # org-wide defaults and lookup tables
  templates/        # rendered into the consumer tree root
  partials/         # {% include %} only, never emitted
  examples/         # a repo.nix per representative consumer
  tests/
  VERSION
```

Consumers address one flake with the `?dir=` fragment and a tag:

```nix
inputs.golden-github.url =
  "github:Fomiller/flake-hub?dir=golden-github&ref=refs/tags/golden-github-0.1.0";
```

Tags are prefixed with the directory name, so packs release on their own cadence and
Renovate bumps each one independently.

`golden-engine` has **no flake inputs**, on purpose. `mkGolden` takes `pkgs` from the
caller, so every pack renders against the consumer's pinned nixpkgs and the engine pins
nothing for anyone.

### Pack split

| Pack | Owns | Rule of thumb |
|---|---|---|
| `golden-base` | `justfile`, `just/*.just` fetch, `.gitignore`, `.editorconfig`, `.envrc`, README skeleton | Repo-shape files any forge would accept |
| `golden-github` | `.github/workflows/*`, `CODEOWNERS`, `renovate.json`, PR template | Files GitHub itself interprets |
| `golden-service` | `Dockerfile`, language toolchain table, build/test/lint CI steps | Anything that knows the repo compiles something |
| `golden-infra` | `root.hcl`, `infra/live/<env>` skeleton, `deploy-infra.yaml`, `just/terraform.just` | Terragrunt scaffolding, not the terraform itself |
| `golden-argocd` | `deploy/chart/**`, chart publish workflow | Kubernetes delivery |

Typical combinations:

- Microservice: `base + github + service + argocd`
- Infrastructure repo: `base + github + infra`
- Library: `base + github + service`, with `service.container = false`

A library wants the language toolchain and the build/test/lint CI steps but has nothing to
ship in an image. So `golden-service` gates its container files on `service.container`,
which defaults to `true`. When it is false the `Dockerfile` and the image-publish workflow
are not rendered at all, and their paths never enter the plan, so the drift check does not
look for them.

Which packs a repo gets is decided by its `flake.nix` inputs, not by a field in
`repo.nix`. Adding a capability means adding an input.

### The pack contract

A pack is data, not code:

```nix
# golden-service/pack.nix
{
  name = "golden-service";
  templates = ./templates;
  partials = ./partials;
  defaults = { language = "go"; };
  registry = import ./registry.nix;
  ownership = {
    managed = [ "Dockerfile" ".github/workflows/build.yml" ];
    scaffold = [ "cmd/**" ];
    retired = [ ".github/workflows/old-build.yml" ];
  };
  overrides = [ ];     # paths this pack may clobber from an earlier pack
  schema = {
    language = { type = "enum"; values = [ "go" "rust" ]; };
  };
}
```

The engine knows no file layout. Not a path, not a glob, not a directory name. If the
engine needs to know where something lives, it is a pack field.

### mkGolden

`mkGolden { packs = [ base github service ]; } pkgs (import ./repo.nix)` runs five steps:

1. **Merge packs**, left to right. Union template roots, deep-merge `defaults` and
   `registry`, concatenate `ownership` globs, union `schema`. A template path emitted by
   two packs throws, naming both packs and the path, unless the later pack lists that path
   in its `overrides`.
2. **Merge config**: pack `defaults` <- `registry` <- `repo.nix`, right-biased. A key in
   `repo.nix` that no pack's `schema` declares throws. A value failing its schema entry
   throws. Both name the offending key.
3. **Render**: one makejinja pass over the merged template tree, data is the merged config
   serialized with `builtins.toJSON`. Output is `filesDrv`, a pure derivation.
4. **Emit plan**: `golden-plan.json` — every path's ownership class, the `unmanaged` list
   from `repo.nix`, the retired paths.
5. **Expose `generateApp`**: runs `lib/reconcile.py` over `filesDrv` and the plan.

Nix validates and builds the plan. Python executes it. Every guard throws at evaluation
time, inside the consumer's own `nix run .#generate`, before any build starts. `mkGolden`
generates no shell.

Outputs: `{ filesDrv; plan; generateApp; mergedConfig; }`.

### Ownership classes

| Class | Behavior |
|---|---|
| `managed` | Overwritten on every run. Drift check enforces it. |
| `scaffold` | Written once if the path is absent. Never touched again. |
| `retired` | Deleted if present. How a pack removes a file it used to own. |
| `unmanaged` | Listed in `repo.nix`. Dropped from generation and from the drift check. |

`unmanaged` is the only escape hatch that removes enforcement, and it lives in `repo.nix`
where a reviewer sees it. Everything else is done through typed extension points:
`ci.extraSteps.pre` / `.post`, `overrides.language.*`, and pack-specific fields.

### Consumer repo

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    golden-engine.url = "github:Fomiller/flake-hub?dir=golden-engine&ref=refs/tags/golden-engine-0.1.0";
    golden-base.url   = "github:Fomiller/flake-hub?dir=golden-base&ref=refs/tags/golden-base-0.1.0";
    golden-github.url = "github:Fomiller/flake-hub?dir=golden-github&ref=refs/tags/golden-github-0.1.0";
    golden-service.url = "github:Fomiller/flake-hub?dir=golden-service&ref=refs/tags/golden-service-0.1.0";
    golden-argocd.url = "github:Fomiller/flake-hub?dir=golden-argocd&ref=refs/tags/golden-argocd-0.1.0";
  };

  outputs = { self, nixpkgs, golden-engine, golden-base, golden-github, golden-service, golden-argocd }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      golden = golden-engine.lib.mkGolden {
        packs = [ golden-base.pack golden-github.pack golden-service.pack golden-argocd.pack ];
      } pkgs (import ./repo.nix);
    in {
      apps.${system}.generate = golden.generateApp;
    };
}
```

```nix
# repo.nix
{
  name = "chat-stat-api";
  codeowners = [ "@Fomiller" ];
  language = "go";
  ci = {
    security = true;
    release = true;
    extraSteps.post = [ "- run: just smoke" ];
  };
  deploy.ecrRepo = "chat-stat-api";
  unmanaged = [ "Dockerfile" ];
}
```

### Bootstrap

`golden-base` exposes an `init` app that writes the three files and runs generation:

```bash
mkdir foo && cd foo && git init
nix run 'github:Fomiller/flake-hub?dir=golden-base#init' -- \
  --name foo --packs github,service,argocd
```

It writes `flake.nix` with the named pack inputs, a `repo.nix` seeded from those packs'
`defaults`, then calls `generate`.

`init` needs to know the current tag of packs it does not own, which nothing else in the
design requires. Rather than have `golden-base` reach across directories at eval time,
`release-flake.yaml` writes `golden-base/pack-versions.nix` — an attrset of pack name to
latest tag — as part of cutting any pack's release, and that commit bumps `golden-base`'s
own `VERSION`. So a stale `init` produces stale pins, and the first Renovate run corrects
them. This is the one place a pack knows another pack's name, and it is generated data,
not hand-maintained.

### Deploy artifacts

`golden-argocd` generates `deploy/chart/` in the service repo. CI packages the chart and
pushes it to ECR as an OCI artifact alongside the image. `homelab` keeps one hand-written
Argo CD app per service under `k8s/apps/<svc>/`, pointing at a published chart version.
The service repo owns its deploy shape; `homelab` stays the GitOps root. No repo writes
into another repo.

## Workflows

Added to `fomiller/gh-actions`:

- **`nix-generate.yaml`** (consumer-side). Installs Nix, restores the homelab attic cache,
  runs `nix run .#generate`, then `git diff --exit-code`. Input `commit-back: true` makes
  it commit and push instead of failing. Pushes use `GITHUB_TOKEN`, which by design does
  not retrigger workflows — that is the loop prevention, not the `paths:` filter alone.
- **`nix-flake-check.yaml`** (hub-side). Matrix over changed flake directories. Runs
  `nix flake check ./<dir>` plus that flake's test apps.
- **`helm-ecr.yaml`**. Packages a chart and `helm push oci://` to ECR. `golden-argocd`
  generates the caller.
- **`release-flake.yaml`** (hub-side). On merge to main, for each changed flake directory
  reads its `VERSION` file, cuts tag `<dir>-<version>`, creates a GitHub Release. A
  separate PR check fails when a flake's files changed and its `VERSION` did not.

Changed to `fomiller/gh-actions`:

- **`mdbook.yaml`**. Currently uses `configure-pages@v2`, `upload-pages-artifact@v1`,
  `deploy-pages@v1`, all deprecated, and installs whatever mdbook release is newest at run
  time. Bump to v5 / v3 / v4 and take the mdbook version as an input with a pinned default,
  so a docs build is reproducible.

The generated consumer workflow triggers only on generator inputs:

```yaml
on:
  pull_request:
    paths: [ flake.lock, flake.nix, repo.nix ]
```

## Propagation

Renovate runs in the homelab cluster as an Argo CD app, following the existing
`k8s/apps/<name>/` layout:

```
homelab/k8s/apps/renovate/
  config.json
  namespace.yaml
  kustomization.yaml
  values.yaml
  external-secrets.yaml
  renovate-config.js
```

- Chart is `renovatebot/renovate`, which deploys a CronJob. Hourly.
- Auth via a GitHub App on the `Fomiller` account, not a PAT. `RENOVATE_GITHUB_APP_ID` and
  the private key come from Doppler through External Secrets, same as every other app in
  the cluster. Creating the App and installing it on the repos is a manual step for
  Forrest; the docs cover it.
- `autodiscover: true`, filtered to `Fomiller/*`. New repos are picked up by existing.
- Egress to github.com only. No ingress, no Tailscale exposure.

Flow:

```
merge to main
  -> release-flake.yaml tags golden-github-0.2.0
  -> cluster Renovate bumps the pin in each consumer's flake.nix and flake.lock
  -> consumer PR runs nix-generate.yaml with commit-back
  -> regenerated files land in the same PR
```

Pack pins are tag URLs rather than plain flake refs, so Renovate's `nix` manager is not
enough. A `customManagers` regex over `flake.nix` matches the `?dir=<pack>&ref=refs/tags/<pack>-<version>`
form with datasource `github-tags` on `Fomiller/flake-hub`, and `extractVersion` anchored
to the directory prefix so `golden-infra-1.0.0` never bumps a `golden-github` pin. The
regex lives in the ConfigMap and has a test fixture in the hub.

Self-hosting also permits `allowedPostUpgradeCommands` — running `nix run .#generate`
inside Renovate. Deliberately not used. Generation stays in the consumer workflow so
Renovate never executes repo code.

## Error handling

Everything that can fail at evaluation does, so the consumer sees it before a build starts:

- Unknown key in `repo.nix`, or a value that fails its schema entry. Names the key.
- Two packs emitting the same path without an `overrides` entry. Names both packs.
- A required field with no default from any pack.
- An `unmanaged` entry matching no generated path — a stale escape hatch is a silent
  enforcement hole, so it is an error, not a warning.

`reconcile.py` failures are runtime and report the plan path plus the offending file.
Because Nix is lazy, every guard is routed through a binding a real output forces, so a
`throw` cannot quietly stop firing when its last consumer disappears.

## Testing

| Layer | Test |
|---|---|
| Engine | Python unit tests for `reconcile.py`. nix-unit eval-guard cases, run from a pack because the engine has no `pkgs` of its own |
| Each pack | Golden snapshot: `tests/fixtures/<case>/repo.nix` plus a committed expected tree, compared against `filesDrv` under `nix flake check` |
| Composition | Fixtures mixing packs. One asserts a deliberate collision throws and names both packs |
| Idempotence | Generate twice into a temp tree, assert the second run is a no-op |
| Renovate regex | Fixture `flake.nix` files, assert the right pin bumps and neighbours do not |
| End to end | `flake-hub-example` repo on `base + github + service + argocd`. Hub CI regenerates it and diffs |

Eval guards need a test that goes red when the guard is deleted. A guard nothing forces
looks present and does nothing.

## Docs

mdbook at `docs/`, published by `mdbook.yaml` on push to main, matching the
`aws-infra-shared-services` setup (`docs/book.toml`, `docs/src/SUMMARY.md`).

- Getting started: bootstrap a repo, the three files
- A page per flake, written for someone consuming it
- Ownership classes
- Writing a pack: the `pack.nix` contract
- Composing packs: merge order, collisions, overrides
- Propagation: tags, Renovate, drift
- Runbook: creating the GitHub App, Doppler secrets

Pack pages are hand-written, but each one's config reference table is generated from that
pack's `schema`, so the table cannot drift from the code.

## Build order

1. `golden-engine` + `golden-base` + snapshot tests. Smallest thing that renders a file.
2. `golden-github`, then `nix-generate.yaml` and `release-flake.yaml` in `gh-actions`.
3. `flake-hub-example`. Drift loop proven by hand.
4. `golden-service`, `golden-infra`, `golden-argocd`.
5. mdbook docs and the `mdbook.yaml` fix.
6. Renovate into `homelab`, `autodiscover` filtered to `flake-hub-example` first, widened
   once a PR looks right.

## Repos touched

| Repo | Change |
|---|---|
| `Fomiller/flake-hub` | New. Six flakes plus docs |
| `Fomiller/gh-actions` | Four new reusable workflows, one fix |
| `Fomiller/flake-hub-example` | New. End-to-end consumer |
| `Fomiller/homelab` | New Argo CD app: `k8s/apps/renovate/`. Additive, no change to existing infra |

## Open items

- The GitHub App has to be created and installed by hand before Renovate can run. Blocks
  step 6 only.
- ECR repositories for published charts need to exist. `homelab`'s AWS unit already
  manages ECR, so this is a terragrunt change in `homelab`, tracked separately when the
  first real service ships.
