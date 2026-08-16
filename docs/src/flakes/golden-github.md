# golden-github

The files GitHub itself reads: `CODEOWNERS`, `renovate.json`, the drift-check
workflow and the CI workflow.

```nix
golden-github.url = "github:Fomiller/flake-hub?dir=golden-github&ref=refs/tags/golden-github-<version>";
```

<!-- BEGIN GENERATED REFERENCE -->
## Configuration

| Key | Type | Required |
|---|---|---|
| `ci.extraSteps.post` | list | no |
| `ci.extraSteps.pre` | list | no |
| `ci.jobs` | list | no |
| `ci.release` | bool | no |
| `ci.security` | bool | no |
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

This pack owns `ci.yml` but knows nothing about languages. A job carries
`stepsFrom`, an opaque string, and the template resolves it against whatever
registry is in scope.
