# golden-argocd

Bootstraps the Helm chart a service ships and the Argo CD overlay values that
deploy it. Add this pack when the service is deployed by Argo CD.

Requires `golden-service`: the bootstrap chart needs `service.port`, and this
pack marks it required so a repo that forgets fails at eval instead of at
render time.

## It owns nothing

Every path below is `scaffold`: written on the first `nix run .#generate` and
never touched again. The pack has no `managed` files, and `nothing-is-managed`
is the check that keeps it that way.

| Path | Notes |
| --- | --- |
| `helm/<chart>/Chart.yaml` | name and version |
| `helm/<chart>/values.yaml` | chart defaults |
| `helm/<chart>/templates/*` | deployment, service, helpers |
| `argocd/overlays/values.app.base.yaml` | shared across environments |
| `argocd/overlays/*/values.app.yaml` | per-environment overrides |

`<chart>` is the repo's `name`. The chart directory is named after it, so a
repo that grows a second chart puts it beside the first under `helm/`.

## Why nothing is managed

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
| `argocd.environments` | list | no | `[ "dev" ]` |

`argocd.environments` picks which overlays exist. Only `dev`, `staging` and
`prod` are supported, one static template each, for the same reason
`golden-infra` works that way: makejinja renders a static tree.

## The overlay values are not a kustomization

Argo CD cannot authenticate kustomize against a private OCI registry, so a
service is deployed from a native Helm source instead. The Application is
assembled in homelab and reads
`$values/argocd/overlays/values.app.base.yaml` plus the environment's own
`values.app.yaml`. Later wins on any key both set, so the per-environment file
carries only what actually differs.

Nothing in the service's own repo names those paths, so
`overlay-values-files-exist` asserts them literally. A missing one otherwise
fails at sync time, which is a long way from here.

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
