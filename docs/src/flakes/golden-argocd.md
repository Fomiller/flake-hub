# golden-argocd

Bootstraps the Helm chart a service ships and the Argo CD overlay values that
deploy it. Everything it writes is scaffold, so the repo owns its chart from
the first generate onwards.

```nix
golden-argocd.url = "github:Fomiller/flake-hub?dir=golden-argocd&ref=refs/tags/golden-argocd-<version>";
```

<!-- BEGIN GENERATED REFERENCE -->
## repo.nix

Every knob this pack adds. Optional keys show the default they fall back
to, so deleting a line changes nothing. Required keys need a real value.

```nix
{
  service = {
    port = 0;  # required, int
  };
  argocd = {
    enabled = true;  # bool, default
    environment = "dev";  # string, default
    kargo = true;  # bool, default
    namespace = "";  # string, default
    notifications = "";  # string, default
  };
}
```

## Configuration

| Key | Type | Required | Default | Description |
|---|---|---|---|---|
| `argocd.enabled` | bool | no | `true` | Whether this repo ships a chart and overlays. False deletes argocd/ and helm/. |
| `argocd.environment` | string | no | `"dev"` | Which environment this repo deploys to. One of dev, staging, prod. |
| `argocd.kargo` | bool | no | `true` | Whether the overlay also installs a Kargo promotion pipeline. |
| `argocd.namespace` | string | no | `""` | Namespace the workload deploys into. Empty means the repo name. |
| `argocd.notifications` | string | no | `""` | Where Argo CD sends sync notifications. Empty means none. |
| `service.port` | int | yes | — | Port the chart's Service and Deployment expose. |

## Files

| Class | Paths |
|---|---|
| managed | `argocd.yaml` |
| scaffold | `helm/*/Chart.yaml`, `helm/*/values.yaml`, `helm/*/templates/*`, `argocd/overlays/values.app.base.yaml`, `argocd/overlays/*/values.app.yaml`, `argocd/overlays/*/values.kargo.yaml`, `argocd/overlays/*/kustomization.yaml` |
| retired | `deploy/chart/Chart.yaml`, `deploy/chart/values.yaml`, `deploy/chart/templates/deployment.yaml`, `deploy/chart/templates/service.yaml`, `deploy/chart/templates/helpers.tpl`, `kargo/values.yaml` |
<!-- END GENERATED REFERENCE -->

## Notes

Requires `golden-service`. The bootstrap chart needs `service.port`, and this
pack marks that key required so a repo that forgets fails at eval rather than at
render time.

The chart lives at `helm/<chart>/`, where `<chart>` is the repo's `name`. The
template path itself is `templates/helm/{{ name }}/`, which works because the
engine substitutes path variables — see the golden-engine page.

One file is managed: the root `argocd.yaml`. homelab's services ApplicationSet
holds a list of repo URLs and asks each one for that file, so a service declares
its own name, environment and namespace instead of homelab keeping a copy.

Everything else is scaffold: `Chart.yaml`, `values.yaml`, the chart templates,
the shared `argocd/overlays/values.app.base.yaml`, and the environment's
`values.app.yaml`, `values.kargo.yaml` and `kustomization.yaml`. What a service
deploys changes for reasons `repo.nix` never sees — a promoted chart version, an
env var, a probe — and a managed file would revert every one of them on the next
generate.

The scaffolded chart runs a hello-world on `service.port`, and the base overlay
values pin no image. A fresh repo has nothing in ECR yet, so a chart pointing
at its own image would render fine and never pull. The repo swaps the image in
when it has one.

`argocd.environment` picks the one overlay that exists. Only `dev`, `staging` and
`prod` are supported, one static template each — the same constraint
`golden-infra` has, because makejinja renders a static tree. It is one
environment rather than a list because there is one cluster.

The overlay is a kustomization that inflates two charts from ECR: the service's
own, and `kargo-project-chart`. One Application therefore carries both the
workload and the pipeline that promotes it, and Kargo needs no directory of its
own. That works only because homelab gives the Argo CD repo-server a helm
registry credential — kustomize shells out to the helm binary, which cannot see
Argo CD's repo-creds.

A promotion commits back into the service repo: the image tag into
`values.app.yaml`, the chart version into `kustomization.yaml`.

A service uses two ECR repositories: `<name>` for the image and `<name>-chart`
for the chart. The `-chart` suffix is part of `Chart.yaml`'s `name` rather than
something the publish workflow appends, because `helm push` reads the repository
name out of the packaged chart — appending at push time would make the published
chart disagree with a local `helm template`. Neither repository is created here;
Terraform owns them. The workflows that publish to them are in `golden-github`.

The helpers file is `helpers.tpl`, not `_helpers.tpl`. The engine excludes `_*`
from rendering, which is how partials stay out of the output.
