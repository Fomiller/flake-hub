# golden-argocd

The Helm chart a service ships, plus the workflow that publishes it to ECR as
an OCI artifact. Add this pack when the service is deployed by Argo CD.

Requires `golden-service`: the chart needs `service.port`, and this pack marks
it required so a repo that forgets fails at eval instead of at render time.

## Files it owns

| Path | Class | Notes |
| --- | --- | --- |
| `deploy/chart/Chart.yaml` | managed | name and version |
| `deploy/chart/templates/*` | managed | deployment, service, helpers |
| `.github/workflows/publish-chart.yml` | managed | packages on PRs, pushes on main |
| `deploy/chart/values.yaml` | scaffold | written once, then yours |

## Schema

| Key | Type | Required | Default |
| --- | --- | --- | --- |
| `deploy.ecrRepo` | string | yes | — |
| `deploy.roleToAssume` | string | yes | — |
| `deploy.replicas` | int | no | `1` |
| `deploy.chartVersion` | string | no | `0.1.0` |

`deploy.ecrRepo` is the prefix alone. `helm push` appends the chart's own name
to the path it is given, so the ECR repo is `<prefix>/<chart-name>` and the push
target stops at the prefix. Getting this wrong does not error — it silently
creates a second repo.

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
