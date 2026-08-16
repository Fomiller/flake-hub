# golden-argocd

The Helm chart a service ships and the workflow that publishes it to ECR as an
OCI artifact.

```nix
golden-argocd.url = "github:Fomiller/flake-hub?dir=golden-argocd&ref=refs/tags/golden-argocd-<version>";
```

<!-- BEGIN GENERATED REFERENCE -->
## Configuration

| Key | Type | Required |
|---|---|---|
| `deploy.chartVersion` | string | no |
| `deploy.ecrRepo` | string | yes |
| `deploy.replicas` | int | no |
| `deploy.roleToAssume` | string | yes |
| `service.port` | int | yes |

## Files

| Class | Paths |
|---|---|
| managed | `deploy/chart/Chart.yaml`, `deploy/chart/templates/*`, `.github/workflows/publish-chart.yml` |
| scaffold | `deploy/chart/values.yaml` |
| retired | _none_ |
<!-- END GENERATED REFERENCE -->

## Notes

Requires `golden-service`. The chart needs `service.port`, and this pack marks
that key required so a repo that forgets fails at eval rather than at render
time.

`values.yaml` is scaffold — it is the service's own configuration surface.
`Chart.yaml` and everything under `templates/` are regenerated.

`deploy.ecrRepo` is the prefix alone. `helm push` appends the chart's own name
to the path it is given, so the ECR repo is `<prefix>/<chart-name>` and the push
target stops at the prefix. Getting this wrong does not error — it silently
creates a second repo.

The helpers file is `helpers.tpl`, not `_helpers.tpl`. The engine excludes `_*`
from rendering, which is how partials stay out of the output.
