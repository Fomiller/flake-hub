# golden-github

The files GitHub itself reads: `CODEOWNERS`, `renovate.json`, the drift-check
workflow and the CI workflow.

```nix
golden-github.url = "github:Fomiller/flake-hub?dir=golden-github&ref=refs/tags/golden-github-<version>";
```

<!-- BEGIN GENERATED REFERENCE -->
## repo.nix

Every knob this pack adds. Required keys are filled in; optional ones are
commented out beside the default they fall back to.

```nix
{
  codeowners = [ ];  # required, list
  ci = {
    extraSteps = {
      # post = [ ];  # list, default
      # pre = [ ];  # list, default
    };
    # jobs = [ ];  # list, default
  };
}
```

## Configuration

| Key | Type | Required |
|---|---|---|
| `ci.extraSteps.post` | list | no |
| `ci.extraSteps.pre` | list | no |
| `ci.jobs` | list | no |
| `codeowners` | list | yes |

## Files

| Class | Paths |
|---|---|
| managed | `CODEOWNERS`, `renovate.json`, `.github/workflows/generate.yml`, `.github/workflows/ci.yml` |
| scaffold | _none_ |
| retired | _none_ |
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
