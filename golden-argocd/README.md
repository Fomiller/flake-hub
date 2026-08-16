# golden-argocd

The Helm chart a service ships, the Argo CD overlays that deploy it, and the
workflow that publishes the chart to ECR as an OCI artifact. Add this pack when
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
| `helm/<chart>/values.yaml` | scaffold | chart defaults, written once |
| `argocd/overlays/values.app.base.yaml` | scaffold | shared across environments |
| `argocd/overlays/*/values.app.yaml` | scaffold | per-environment overrides |

`<chart>` is the repo's `name`. The chart directory is named after it, so a
repo that grows a second chart puts it beside the first under `helm/`.

## Schema

| Key | Type | Required | Default |
| --- | --- | --- | --- |
| `deploy.registry` | string | yes | — |
| `deploy.ecrRepo` | string | yes | — |
| `deploy.roleToAssume` | string | yes | — |
| `deploy.envs` | list | no | `[ "dev" ]` |
| `deploy.replicas` | int | no | `1` |
| `deploy.chartVersion` | string | no | `0.1.0` |

`deploy.ecrRepo` is the prefix alone. `helm push` appends the chart's own name
to the path it is given, so the ECR repo is `<prefix>/<chart-name>` and the push
target stops at the prefix. Getting this wrong does not error — it silently
creates a second repo.

`deploy.envs` picks which overlays exist. Only `dev`, `staging` and `prod` are
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
