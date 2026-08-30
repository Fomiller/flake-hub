# golden-github

The files GitHub itself reads. Add this pack when a repo lives on GitHub and
wants review routing and dependency updates wired up the same way as every
other repo.

## Files it owns

| Path | Class | Notes |
| --- | --- | --- |
| `CODEOWNERS` | managed | `* <owners>`, from `github.codeowners` |
| `renovate.json` | managed | extends the hub's shared preset |
| `.github/workflows/generate.yml` | managed | regenerates on PRs touching `flake.nix`, `flake.lock` or `repo.nix`; commits back only on Renovate's PRs |
| `.github/workflows/ci.yml` | managed | one job per entry in `ci.jobs`; not emitted at all when no pack contributed one |
| `.github/workflows/publish-image.yml` | managed | builds the image on PRs, pushes to ECR on main; off unless `github.publishImage` |
| `.github/workflows/publish-chart.yml` | managed | packages every `helm/*/Chart.yaml` on PRs, pushes to ECR on main; off unless `github.publishChart` |

## Schema

| Key | Type | Required | Default |
| --- | --- | --- | --- |
| `github.codeowners` | list | yes | — |
| `github.renovate` | bool | no | `true` |
| `github.buildAndTest` | bool | no | `true` |
| `github.agents` | bool | no | `true` |
| `github.publishImage` | bool | no | `false` |
| `github.publishChart` | bool | no | `false` |
| `github.platforms` | list | no | `[ "linux/amd64" ]` |
| `ci.jobs` | list | no | `[ ]` |
| `ci.extraSteps.pre` | list | no | `[ ]` |
| `ci.extraSteps.post` | list | no | `[ ]` |

`init --packs github` seeds `github.codeowners` for you, since a repo that selects this
pack cannot generate without it.

## The publish workflows

`publish-image.yml` builds the repo's container image and `publish-chart.yml`
packages every chart under `helm/`. Both push to ECR on a push to main and
throw the artifact away on a pull request. Both authenticate through OIDC, and
neither names a role: the reusable workflow reads the `AWS_OIDC_ROLE_ARN` secret,
so a role rotation does not touch any repo here.

Versions are computed, never committed. Each workflow asks the reusable one for
the next semver from conventional commits since that artifact's last tag, then
tags the release: `<name>-v0.2.0` for the image, `<chart>-v0.2.0` for the chart.
The two are separate streams, and only commits touching an artifact's own paths
count toward its bump, so a chart-only change does not move the image.

Nothing publishes a moving tag. One immutable tag per release is what lets the
image repository be immutable, and `golden-infra` creates it that way.

Both workflows also take a manual run. Off a feature branch it cuts a candidate
— `0.2.0-rc.1`, counting up until `0.2.0` is cut — so a build can be published
and deployed before it merges. Off the default branch it cuts the stable release
a merge would have cut. Which one you get is the branch, never a choice at
dispatch time, so a prerelease cannot reach main by mistake.

They live here rather than in `golden-argocd` because they publish artifacts
and never write one. `golden-argocd` bootstraps a repo's chart and then leaves
it alone, so a workflow it owned would be the one managed file left reaching
into `helm/`.

Neither ECR repository is created here. Terraform owns them — see
`golden-infra`.

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
