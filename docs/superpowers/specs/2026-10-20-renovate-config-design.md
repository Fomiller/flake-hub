# renovate-config design

Date: 2026-10-20
Linear: [FOM-51](https://linear.app/fomiller/issue/FOM-51/create-a-declarative-repository-platform-generator-using-nix-flakes-to)

## Problem

Renovate bumps a flake-hub pack pin as soon as a tag exists. There is no gate
between "flake-hub tagged `golden-base-0.7.0`" and "every consumer repo has a PR
for it". A bad pack release goes out to every repo within the hour, and the only
way to stop it is to close PRs by hand.

The pack-pin preset also lives inside flake-hub, next to the packs it bumps, with
`config:recommended` turned on in every consumer. That second part bumps Go and
GitHub Actions versions inside files the generator owns, which fails the drift
check.

## Goals

- A new pack version reaches consumer repos only after a human promotes it.
- One repo, `Fomiller/renovate-config`, holds both the Renovate rules and the
  promoted versions those rules read.
- Renovate updates pack pins and nothing else.
- Adding a pack needs a version file and a warehouse, not a new preset.

## Non-goals

- Renovate rules for anything other than pack pins. Each later one is its own
  preset.
- Auto-promotion. One line to turn on later; off to start.
- Auto-merging Renovate PRs.
- A pin-staleness report.
- Changing which repos Renovate runs on. `autodiscoverFilter` in homelab stays
  the two example repos.

## Architecture

```
Fomiller/renovate-config
  default.json                        # extended by every repo
  presets/nix-flakes/packs.json       # one preset, every pack
  versions/nix-flakes/<pack>.yaml     # one per pack; Kargo writes `version`
  argocd.yaml                         # read by homelab's services ApplicationSet
  argocd/overlays/prod/
    kustomization.yaml                # inflates kargo-project-chart only
    values.kargo.yaml                 # gitRepos + warehouses + one stage
  tests/                              # preset tests, run in CI
  .github/workflows/validate.yaml
  README.md
```

### Flow

1. flake-hub tags `golden-base-0.7.0`.
2. The `golden-base` warehouse sees it. Its git source filters on
   `^golden-base-`, so no other pack's tags reach it.
3. The `release` stage now has new freight. A human promotes it in the Kargo UI
   or with `kargo promote`.
4. The promotion commits `version: golden-base-0.7.0` into
   `versions/nix-flakes/golden-base.yaml` on `main`.
5. On its next hourly run, Renovate reads that file through the custom
   datasource and opens a pin-bump PR in every repo that pins `golden-base`.
6. That repo's generate workflow commits the regenerated files onto the PR.

### Version files

One file per pack, so a datasource URL can be built from the pack name:

```yaml
# versions/nix-flakes/golden-base.yaml
# Kargo writes `version` on promotion to the release stage. Do not edit it by hand.
repo: github.com/Fomiller/flake-hub
dir: golden-base
sourceUrl: https://github.com/Fomiller/flake-hub
version: golden-base-0.6.0
```

`version` is the full tag. It is what the consumer's `flake.nix` holds, so it
can be compared and written back without stripping a prefix.

`sourceUrl` lets Renovate pull release notes into the PR body. `dir` points it
at the pack's directory in the monorepo.

The first value in each file is the pack's current newest tag. Kargo overwrites
it on the first promotion.

### The preset

`presets/nix-flakes/packs.json` holds one custom datasource and one regex
manager.

The datasource reads the version file for whichever pack the manager matched:

```json
"customDatasources": {
  "flake-hub-pack": {
    "defaultRegistryUrlTemplate": "https://raw.githubusercontent.com/Fomiller/renovate-config/main/versions/nix-flakes/{{packageName}}.yaml",
    "format": "yaml",
    "transformTemplates": [
      "{ \"sourceUrl\": sourceUrl, \"sourceDirectory\": dir, \"releases\": [ { \"version\": version } ] }"
    ]
  }
}
```

The manager matches the pin in `flake.nix` and names the pack as both `depName`
and `packageName`:

- `matchStrings`: the PR #41 pattern, which is valid under RE2 and captures the
  full tag as `currentValue`.
- `datasourceTemplate`: `custom.flake-hub-pack`.
- `packageNameTemplate`: `{{{depName}}}`, so the URL resolves per pack.
- `versioningTemplate`: the regex versioning with a `compatibility` group, from
  PR #41. The datasource only ever returns one release for one pack, so this is
  a second guard, not the only one.

A repo pinning a pack that has no version file gets a lookup failure for that
one dependency. Renovate logs it and moves on.

### default.json

- `extends`: `presets/nix-flakes/packs` by full path. Renovate has no directory
  default, so `//presets/nix-flakes` would look for `presets/nix-flakes.json`.
- `enabledManagers: ["custom.regex"]`. No other manager runs, so Renovate never
  edits a generated file except the pin itself.
- `nix.enabled: false`. Consumers regenerate `flake.lock` in their own workflow.
- `semanticCommits`, type `chore`, scope `deps`.
- `labels: ["dependencies"]`, `prConcurrentLimit: 3`, `prHourlyLimit: 2`.
- `rebaseWhen: "behind-base-branch"`. Otherwise a clean but stale PR sits until
  someone ticks the rebase box.
- `gitIgnoredAuthors: ["41898282+github-actions[bot]@users.noreply.github.com"]`.
  That is the identity `Fomiller/gh-actions`' `nix-generate.yaml` commits the
  regenerated files as. Without it, Renovate sees its own branch as edited by a
  human and stops updating the PR.

### Kargo project

`argocd/overlays/prod/kustomization.yaml` inflates `kargo-project-chart` and
nothing else. `values.kargo.yaml`:

- `gitRepos`: one per pack, all on `https://github.com/Fomiller/flake-hub.git`,
  each with `allowTags: '^<pack>-'`.
- `warehouses`: one per pack, named after it. Each has one `updatePaths` entry
  writing `version` in `versions/nix-flakes/<pack>.yaml`, `rootRelative: true`.
- `stages`: one, `release`, fed by every warehouse. No `autoPromotion`. No
  `argocd` block, since nothing is deployed from these files.

`argocd.yaml` names the app `renovate-config`, env `prod`, namespace
`renovate-config`. Kargo requires the project name and namespace to match.

Kargo needs write access to this repo. The project uses the same `git`
credential every other project gets from the chart defaults.

### Validation

`.github/workflows/validate.yaml`, on every push and PR:

- `renovate-config-validator --strict` over `default.json` and every preset.
  Renovate is pinned, so CI and local runs agree.
- The preset tests: every pattern compiles under RE2, every pin in a sample
  `flake.nix` matches, the versioning parses every version file's tag, and every
  version file has the fields the transform reads.

## Changes outside the repo

- **homelab #65.** `renovate-config.json` extends `github>Fomiller/renovate-config`
  and sets `ignorePresets: ["github>Fomiller/flake-hub//renovate/default"]`. A
  consumer's `renovate.json` still extends the old preset until it picks up the
  new `golden-github`, and the ignore keeps that from being a config error in
  the meantime. Add `https://github.com/Fomiller/renovate-config.git` to the
  `services` ApplicationSet list.
- **flake-hub.** Delete `renovate/`. Close #41 without merging. `golden-github`'s
  `renovate.json` template extends only `github>Fomiller/renovate-config`. The
  README and docs pages that point at `renovate/default.json` point at the new
  repo instead.
- **golden-github's `generate.yml`.** It sets `commit-back` only when
  `github.actor == 'renovate[bot]'`, the hosted Renovate app. The self-hosted
  bot is `fomiller-renovate-bot[bot]`, so today its PRs would fail the drift
  check instead of getting regenerated files. The template compares against
  the self-hosted bot's login.
- **Consumers.** No hand bumps. The first `golden-github` release with the new
  templates goes through Kargo like any other, and Renovate opens the bump PR.
  That PR still runs the old `generate.yml`, whose actor check does not match
  the self-hosted bot, so run `nix run .#generate` on it by hand once. Every
  later PR regenerates on its own.
- **Cleanup.** Once both example repos have merged that bump, drop
  `ignorePresets` from homelab and delete `renovate/` from flake-hub.

## Risks

- **Kargo's tag ordering.** The tags are prefixed, so they cannot use the
  `SemVer` selection strategy. `NewestTag` has to order by tag date, not by
  name, or it picks `golden-base-0.9.0` over `golden-base-0.10.0`. Check this on
  Kargo v1.11 before relying on it.
- **raw.githubusercontent.com caching.** It caches for about five minutes. A
  promotion can take that long to reach Renovate, on top of the hourly schedule.
- **A hand edit to a version file.** Kargo overwrites it on the next promotion.
  The file header says so.

## Done means

- Tagging a pack produces freight in Kargo and no Renovate PR.
- Promoting it commits the version file, and the next Renovate run opens the
  pin-bump PR in each consumer.
- No consumer gets a PR for anything other than a pack pin.
- No file in the repo mentions any organisation other than `Fomiller`.
