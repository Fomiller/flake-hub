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
    environments = [ "dev" ];  # list, default
  };
}
```

## Configuration

| Key | Type | Required | Default | Description |
|---|---|---|---|---|
| `argocd.enabled` | bool | no | `true` | Whether this repo ships a chart and overlays. False deletes argocd/ and helm/. |
| `argocd.environments` | list | no | `[ "dev" ]` | Which environments get an overlay. Only dev, staging and prod exist. |
| `service.port` | int | yes | — | Port the chart's Service and Deployment expose. |

## Files

| Class | Paths |
|---|---|
| managed | _none_ |
| scaffold | `helm/*/Chart.yaml`, `helm/*/values.yaml`, `helm/*/templates/*`, `argocd/overlays/values.app.base.yaml`, `argocd/overlays/*/values.app.yaml` |
| retired | `deploy/chart/Chart.yaml`, `deploy/chart/values.yaml`, `deploy/chart/templates/deployment.yaml`, `deploy/chart/templates/service.yaml`, `deploy/chart/templates/helpers.tpl`, `argocd/overlays/dev/kustomization.yaml`, `argocd/overlays/staging/kustomization.yaml`, `argocd/overlays/prod/kustomization.yaml` |
<!-- END GENERATED REFERENCE -->

## Notes

Requires `golden-service`. The bootstrap chart needs `service.port`, and this
pack marks that key required so a repo that forgets fails at eval rather than at
render time.

The chart lives at `helm/<chart>/`, where `<chart>` is the repo's `name`. The
template path itself is `templates/helm/{{ name }}/`, which works because the
engine substitutes path variables — see the golden-engine page.

Nothing here is managed. Every file is scaffold: `Chart.yaml`, `values.yaml`,
the chart templates, the shared `argocd/overlays/values.app.base.yaml`, and each
environment's `values.app.yaml`. What a service deploys changes for reasons
`repo.nix` never sees — a promoted chart version, an env var, a probe — and a
managed file would revert every one of them on the next generate.

The scaffolded chart runs a hello-world on `service.port`, and the base overlay
values pin no image. A fresh repo has nothing in ECR yet, so a chart pointing
at its own image would render fine and never pull. The repo swaps the image in
when it has one.

`argocd.environments` picks which overlays exist. Only `dev`, `staging` and `prod` are
supported, one static template each — the same constraint `golden-infra` has,
because makejinja renders a static tree.

There is no kustomization. Argo CD cannot authenticate kustomize against a
private OCI registry, so the Application is assembled in homelab from a native
Helm source that reads the base values first and the environment's own
`values.app.yaml` second.

A service uses two ECR repositories: `<name>` for the image and `<name>-chart`
for the chart. The `-chart` suffix is part of `Chart.yaml`'s `name` rather than
something the publish workflow appends, because `helm push` reads the repository
name out of the packaged chart — appending at push time would make the published
chart disagree with a local `helm template`. Neither repository is created here;
Terraform owns them. The workflows that publish to them are in `golden-github`.

The helpers file is `helpers.tpl`, not `_helpers.tpl`. The engine excludes `_*`
from rendering, which is how partials stay out of the output.
