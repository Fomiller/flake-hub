# golden-argocd

The Helm chart a service ships, the Argo CD overlays that deploy it, and the
two workflows that publish the image and the chart to ECR. Add this pack when
the service is deployed by Argo CD.

Requires `golden-service`: the chart needs `service.port`, and this pack marks
it required so a repo that forgets fails at eval instead of at render time.

## Files it owns

| Path | Class | Notes |
| --- | --- | --- |
| `helm/<chart>/Chart.yaml` | managed | name and version |
| `helm/<chart>/templates/*` | managed | deployment, service, helpers |
| `argocd/overlays/*/kustomization.yaml` | managed | one per selected environment |
| `.github/workflows/publish-chart.yml` | managed | packages on PRs, pushes on main |
| `.github/workflows/publish-image.yml` | managed | builds on PRs, pushes on main |
| `helm/<chart>/values.yaml` | scaffold | chart defaults, written once |
| `argocd/overlays/values.app.base.yaml` | scaffold | shared across environments |
| `argocd/overlays/*/values.app.yaml` | scaffold | per-environment overrides |

`<chart>` is the repo's `name`. The chart directory is named after it, so a
repo that grows a second chart puts it beside the first under `helm/`.

## Schema

| Key | Type | Required | Default |
| --- | --- | --- | --- |
| `argocd.registry` | string | yes | — |
| `argocd.roleToAssume` | string | yes | — |
| `argocd.awsRegion` | string | no | `us-east-1` |
| `argocd.envs` | list | no | `[ "dev" ]` |
| `argocd.replicas` | int | no | `1` |
| `argocd.chartVersion` | string | no | `0.1.0` |
| `argocd.platforms` | list | no | `[ "linux/amd64" ]` |

## Two ECR repositories

A service uses two: `<name>` for the image, `<name>-chart` for the chart. Both
sit at the registry root, so `argocd.registry` is the whole prefix.

The `-chart` suffix is written into `Chart.yaml`'s `name`, not appended by the
publish workflow. `helm push` reads the repository name out of the packaged
chart, so a suffix added at push time would make the published chart disagree
with what `helm template` renders locally. `overlay-chart-name-matches` is the
check that keeps the chart name and the overlays in step.

Neither repository is created by this pack. Terraform owns them — see
`golden-infra`.

`argocd.envs` picks which overlays exist. Only `dev`, `staging` and `prod` are
supported, one static template each, for the same reason `golden-infra` works
that way: makejinja renders a static tree.

## How the overlays layer

Each overlay's `kustomization.yaml` inflates the chart from OCI and points at
two values files: `../values.app.base.yaml` first, then its own
`values.app.yaml`. Later wins on any key both set, so the per-environment file
carries only what actually differs. Both are scaffold — the generator writes
them once and never again.

## The chart directory name is templated

The template lives at `templates/helm/{{ name }}/`. makejinja renders file
contents but copies path names through untouched, so the engine substitutes
`{{ key }}` in paths itself, on both the rendered tree and the plan. See
`golden-engine/README.md`.

## Helm and Jinja both use `{{ }}`

Every chart template is wrapped whole in `{% raw %}`, so Helm's syntax reaches
the file untouched. Only the build-time values step outside the raw block, by
closing and reopening it. There are two of them, both `service.port`.

## The helpers file has no leading underscore

Helm's convention is `_helpers.tpl`, but the engine excludes `_*` from rendering
— that is how partials are kept out of the output. The file is named
`helpers.tpl` instead. It defines templates and renders to nothing, so Helm
drops the empty document and the defines still register. `chart-renders` runs
`helm template` and `helm lint` over the real chart, which is what proves it.
