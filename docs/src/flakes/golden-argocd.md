# golden-argocd

The Helm chart a service ships, the Argo CD overlays that deploy it, and the
workflow that publishes the chart to ECR as an OCI artifact.

```nix
golden-argocd.url = "github:Fomiller/flake-hub?dir=golden-argocd&ref=refs/tags/golden-argocd-<version>";
```

<!-- BEGIN GENERATED REFERENCE -->
## repo.nix

Every knob this pack adds. Optional keys show the default they fall back
to, so deleting a line changes nothing. Required keys need a real value.

```nix
{
  argocd = {
    registry = "…";  # required, string
    roleToAssume = "…";  # required, string
    awsRegion = "us-east-1";  # string, default
    chartVersion = "0.1.0";  # string, default
    envs = [ "dev" ];  # list, default
    platforms = [ "linux/amd64" ];  # list, default
    replicas = 1;  # int, default
  };
  service = {
    port = 0;  # required, int
  };
}
```

## Configuration

| Key | Type | Required |
|---|---|---|
| `argocd.awsRegion` | string | no |
| `argocd.chartVersion` | string | no |
| `argocd.envs` | list | no |
| `argocd.platforms` | list | no |
| `argocd.registry` | string | yes |
| `argocd.replicas` | int | no |
| `argocd.roleToAssume` | string | yes |
| `service.port` | int | yes |

## Files

| Class | Paths |
|---|---|
| managed | `helm/*/Chart.yaml`, `helm/*/templates/*`, `argocd/overlays/*/kustomization.yaml`, `.github/workflows/publish-chart.yml`, `.github/workflows/publish-image.yml` |
| scaffold | `helm/*/values.yaml`, `argocd/overlays/values.app.base.yaml`, `argocd/overlays/*/values.app.yaml` |
| retired | `deploy/chart/Chart.yaml`, `deploy/chart/values.yaml`, `deploy/chart/templates/deployment.yaml`, `deploy/chart/templates/service.yaml`, `deploy/chart/templates/helpers.tpl` |
<!-- END GENERATED REFERENCE -->

## Notes

Requires `golden-service`. The chart needs `service.port`, and this pack marks
that key required so a repo that forgets fails at eval rather than at render
time.

The chart lives at `helm/<chart>/`, where `<chart>` is the repo's `name`. The
template path itself is `templates/helm/{{ name }}/`, which works because the
engine substitutes path variables — see the golden-engine page.

Values files are scaffold: the chart's `values.yaml`, the shared
`argocd/overlays/values.app.base.yaml`, and each environment's
`values.app.yaml`. They are the service's own configuration surface.
`Chart.yaml`, the chart templates and each `kustomization.yaml` are
regenerated.

Each overlay inflates the chart from OCI with the base values first and its own
`values.app.yaml` second, so a per-environment file carries only what differs.

`argocd.envs` picks which overlays exist. Only `dev`, `staging` and `prod` are
supported, one static template each — the same constraint `golden-infra` has,
because makejinja renders a static tree.

A service uses two ECR repositories: `<name>` for the image and `<name>-chart`
for the chart, both at the registry root. The `-chart` suffix is part of
`Chart.yaml`'s `name` rather than something the publish workflow appends,
because `helm push` reads the repository name out of the packaged chart —
appending at push time would make the published chart disagree with a local
`helm template`. Neither repository is created here; Terraform owns them.

The helpers file is `helpers.tpl`, not `_helpers.tpl`. The engine excludes `_*`
from rendering, which is how partials stay out of the output.
