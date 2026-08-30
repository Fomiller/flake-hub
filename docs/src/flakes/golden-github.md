# golden-github

The files GitHub itself reads: `CODEOWNERS`, `renovate.json`, the drift-check
workflow, the CI workflow, and the two workflows that publish a repo's image
and chart to ECR.

```nix
golden-github.url = "github:Fomiller/flake-hub?dir=golden-github&ref=refs/tags/golden-github-<version>";
```

<!-- BEGIN GENERATED REFERENCE -->
## repo.nix

Every knob this pack adds. Optional keys show the default they fall back
to, so deleting a line changes nothing. Required keys need a real value.

```nix
{
  github = {
    codeowners = [ ];  # required, list
    agents = true;  # bool, default
    buildAndTest = true;  # bool, default
    platforms = [ "linux/amd64" ];  # list, default
    publishChart = false;  # bool, default
    publishImage = false;  # bool, default
    renovate = true;  # bool, default
  };
  ci = {
    extraSteps = {
      post = [ ];  # list, default
      pre = [ ];  # list, default
    };
    jobs = [ ];  # list, default
  };
}
```

## Configuration

| Key | Type | Required | Default | Description |
|---|---|---|---|---|
| `ci.extraSteps.post` | list | no | `[ ]` | Steps run after every CI job's own steps. |
| `ci.extraSteps.pre` | list | no | `[ ]` | Steps run before every CI job's own steps. |
| `ci.jobs` | list | no | `[ ]` | Jobs added to ci.yml. Packs append to this. |
| `github.agents` | bool | no | `true` | Whether to seed AGENTS.md. It is written once; turning this off later leaves the file alone. |
| `github.buildAndTest` | bool | no | `true` | Whether to write ci.yml. False leaves the repo with no build or test workflow. |
| `github.codeowners` | list | yes | — | GitHub handles or teams that own every path. Written to .github/CODEOWNERS. |
| `github.platforms` | list | no | `[ "linux/amd64" ]` | Platforms the image is built for, passed to buildx. |
| `github.publishChart` | bool | no | `false` | Whether to write publish-chart.yml, which packages every helm/*/Chart.yaml and pushes it to ECR. |
| `github.publishImage` | bool | no | `false` | Whether to write publish-image.yml, which builds the repo's container image and pushes it to ECR. |
| `github.renovate` | bool | no | `true` | Whether to write renovate.json. |

## Files

| Class | Paths |
|---|---|
| managed | `.github/CODEOWNERS`, `renovate.json`, `.github/workflows/generate.yml`, `.github/workflows/ci.yml`, `.github/workflows/publish-image.yml`, `.github/workflows/publish-chart.yml` |
| scaffold | `AGENTS.md` |
| retired | `CODEOWNERS` |
<!-- END GENERATED REFERENCE -->

## Notes

`renovate.json` carries no ownership header. JSON has no comment syntax that
Renovate accepts, so nothing in the file says it is generated. `CODEOWNERS` does
carry one.

The CI workflow renders only if some pack contributed a job. `jobs:` with no
children is invalid YAML, so a repo with no jobs gets no `ci.yml` at all.

`publish-image.yml` and `publish-chart.yml` are both off by default. A repo
that ships no image has no ECR repository to push to, so a workflow that ran
would fail on every push to main. Turn them on with `github.publishImage` and
`github.publishChart`. Both authenticate through OIDC and neither names a role:
the reusable workflow reads the `AWS_OIDC_ROLE_ARN` secret, so rotating the role
does not regenerate a single repo.

They live here rather than in `golden-argocd` because they publish artifacts and
never write one. `golden-argocd` bootstraps a repo's chart and then leaves it
alone, so a workflow it owned would be the one managed file left reaching into
`helm/`.

This pack owns `ci.yml`, and its template resolves `stepsFrom = "language"`
against the `languages` registry. That is a real dependency on the shape of
`golden-service`'s registry, not an abstraction over it — pack defaults are
static data and cannot look anything up, so the render is the only place both
the registry and `language` are in scope.
