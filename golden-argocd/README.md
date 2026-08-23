# golden-argocd

Bootstraps the Helm chart a service ships and the Argo CD overlay values that
deploy it. Add this pack when the service is deployed by Argo CD.

Requires `golden-service`: the bootstrap chart needs `service.port`, and this
pack marks it required so a repo that forgets fails at eval instead of at
render time.

## It owns one file

| Path | Ownership | Notes |
| --- | --- | --- |
| `argocd.yaml` | managed | what homelab reads to build the Application |
| `helm/<chart>/Chart.yaml` | scaffold | name and version |
| `helm/<chart>/values.yaml` | scaffold | chart defaults |
| `helm/<chart>/templates/*` | scaffold | deployment, service, helpers |
| `argocd/overlays/values.app.base.yaml` | scaffold | shared chart values |
| `argocd/overlays/<env>/values.app.yaml` | scaffold | this environment's overrides |
| `argocd/overlays/<env>/values.kargo.yaml` | scaffold | the promotion pipeline |
| `argocd/overlays/<env>/kustomization.yaml` | scaffold | inflates both charts |

Scaffold means written on the first `nix run .#generate` and never touched
again. `only-argocd-yaml-is-managed` is the check that keeps the list at one.

`<chart>` is the repo's `name`. The chart directory is named after it, so a
repo that grows a second chart puts it beside the first under `helm/`.

## The root argocd.yaml

homelab's services ApplicationSet holds a list of repo URLs and asks each one
for this file. A service therefore declares its own destination rather than
homelab keeping a copy that drifts.

It is the one managed file here because every field in it comes from
`repo.nix`, so regenerating it can only agree with `repo.nix`. Nothing a
promotion writes lives in it.

## Why the rest is not managed

What a service deploys is the service's own decision, and it changes for
reasons `repo.nix` never sees: a chart version a promotion tool wrote, an env
var, a probe path, a second container. A managed file is regenerated from
`repo.nix`, so every one of those edits would be reverted silently, on whatever
`nix run .#generate` happens to run next.

The cost is real. A later change to the chart's shape does not reach a repo
that already has one. Such a change needs a note in the pack's release and a
manual edit downstream.

## The bootstrap chart is a hello-world

The scaffolded chart runs `hashicorp/http-echo` on `service.port` and puts a
Service in front of it. That is deliberate: a freshly bootstrapped repo has no
image in ECR yet, so a chart pointing at one would render fine and never pull.
The repo swaps the image in when it has one.

The overlay still names a chart version that does not exist yet. A repo has
published nothing on its first commit, so its Application stays unsynced until
`publish-chart.yml` runs on the default branch once. That is one CI run, not a
manual step.

For the same reason `argocd/overlays/values.app.base.yaml` pins no image. It
carries `fullnameOverride`, `replicas`, and the `imagePullSecrets` name, and
leaves `image` to the chart until the repo fills it in.
`base-overlay-pins-no-image` is the check.

## Two ECR repositories

A service uses two: `<name>` for the image, `<name>-chart` for the chart.

The `-chart` suffix is written into `Chart.yaml`'s `name`, not appended by the
publish workflow. `helm push` reads the repository name out of the packaged
chart, so a suffix added at push time would make the published chart disagree
with what `helm template` renders locally. `chart-name-has-the-suffix` is the
check.

Neither repository is created by this pack. Terraform owns them — see
`golden-infra`. The workflows that publish to them live in `golden-github`,
behind `github.publishImage` and `github.publishChart`.

## Schema

| Key | Type | Required | Default |
| --- | --- | --- | --- |
| `argocd.enabled` | bool | no | `true` |
| `argocd.environment` | string | no | `"dev"` |
| `argocd.kargo` | bool | no | `true` |
| `argocd.namespace` | string | no | `""` |
| `argocd.notifications` | string | no | `""` |

`argocd.environment` picks the one overlay that exists. Only `dev`, `staging`
and `prod` are supported, one static template each, for the same reason
`golden-infra` works that way: makejinja renders a static tree.

One environment, not a list, because there is one cluster. A second cluster is
what makes dev and prod meaningfully different, and that is when this becomes a
list again.

`argocd.namespace` empty means the repo's `name`.

## The overlay inflates two charts

`argocd/overlays/<env>/kustomization.yaml` pulls the service's own chart and
`kargo-project-chart` from ECR, so one Application carries both the workload
and the pipeline that promotes it. Kargo therefore needs no directory of its
own; its values sit beside the app's at
`argocd/overlays/<env>/values.kargo.yaml`. `argocd.kargo = false` drops the
second chart and that file.

Two things about this shape are load-bearing:

- Argo CD's repo-server needs a helm registry credential, because kustomize
  shells out to the helm binary rather than using Argo CD's own repo-creds. See
  homelab's `k8s/apps/cluster-resources`.
- `helmCharts[].name` must not contain a slash. kustomize builds a local
  directory out of the name, so a path segment in it resolves wrong. Every
  chart therefore sits at the registry root, with nothing in front of its name.
  `chart-names-have-no-slash` is the check.

The Kargo project runs in the workload's namespace, not one of its own. Kargo
requires a project's name and its namespace to match, so the project is named
after the service. That makes the Kargo chart the thing declaring the
Namespace, and Argo CD's `managedNamespaceMetadata` only applies to a namespace
it creates itself — so `values.kargo.yaml` carries the ECR pull label instead.
Drop it and the pods stop pulling.
`kargo-namespace-keeps-the-pull-label` is the check.

Nothing in the service's repo names the values files by path, so
`overlay-values-files-exist` asserts them literally. A missing one otherwise
fails at sync time, which is a long way from here.

## Kargo promotes into this repo

`values.kargo.yaml` points the pipeline's `updatePaths` at
`argocd/overlays/<env>/values.app.yaml` for the image tag and at the overlay's
own `kustomization.yaml` for the chart version. A promotion is a commit to this
repo, so the running version is readable where the rest of the deploy config
is. `kargo-updates-real-paths` checks those paths exist in what the pack
renders.

## The chart directory name is templated

The template lives at `templates/helm/{{ name }}/`. makejinja renders file
contents but copies path names through untouched, so the engine substitutes
`{{ key }}` in paths itself, on both the rendered tree and the plan. See
`golden-engine/README.md`.

## Helm and Jinja both use `{{ }}`

Every chart template is wrapped whole in `{% raw %}`, so Helm's syntax reaches
the file untouched. Only the build-time values step outside the raw block, by
closing and reopening it.

## The helpers file has no leading underscore

Helm's convention is `_helpers.tpl`, but the engine excludes `_*` from rendering
— that is how partials are kept out of the output. The file is named
`helpers.tpl` instead. It defines templates and renders to nothing, so Helm
drops the empty document and the defines still register. `chart-renders` runs
`helm template` and `helm lint` over the real chart, which is what proves it.
