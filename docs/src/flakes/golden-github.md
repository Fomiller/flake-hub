# golden-github

The files GitHub itself reads: `CODEOWNERS`, `renovate.json`, the drift-check
workflow and the CI workflow.

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
    renovate = true;  # bool, default
    roleToAssume = "";  # string, default
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
| `github.renovate` | bool | no | `true` | Whether to write renovate.json. |
| `github.roleToAssume` | string | no | `""` | IAM role ARN the publish workflows assume through OIDC. |

## Files

| Class | Paths |
|---|---|
| managed | `.github/CODEOWNERS`, `renovate.json`, `.github/workflows/generate.yml`, `.github/workflows/ci.yml` |
| scaffold | `AGENTS.md` |
| retired | `CODEOWNERS` |
<!-- END GENERATED REFERENCE -->

## Notes

`renovate.json` carries no ownership header. JSON has no comment syntax that
Renovate accepts, so nothing in the file says it is generated. `CODEOWNERS` does
carry one.

The CI workflow renders only if some pack contributed a job. `jobs:` with no
children is invalid YAML, so a repo with no jobs gets no `ci.yml` at all.

This pack owns `ci.yml`, and its template resolves `stepsFrom = "language"`
against the `languages` registry. That is a real dependency on the shape of
`golden-service`'s registry, not an abstraction over it — pack defaults are
static data and cannot look anything up, so the render is the only place both
the registry and `language` are in scope.
