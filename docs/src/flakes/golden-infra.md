# golden-infra

Terragrunt scaffolding and the deploy workflow, for a repo that manages its own
AWS infrastructure.

```nix
golden-infra.url = "github:Fomiller/flake-hub?dir=golden-infra&ref=refs/tags/golden-infra-<version>";
```

<!-- BEGIN GENERATED REFERENCE -->
## Configuration

| Key | Type | Required |
|---|---|---|
| `infra.awsProviderVersion` | string | no |
| `infra.awsRegion` | string | no |
| `infra.dopplerProject` | string | yes |
| `infra.envs` | list | no |
| `infra.stateBucket` | string | yes |
| `infra.tailscale` | bool | no |
| `infra.terraformVersion` | string | no |

## Files

| Class | Paths |
|---|---|
| managed | `infra/live/root.hcl`, `infra/live/service.hcl`, `infra/live/*/account.hcl`, `.github/workflows/deploy-infra.yml` |
| scaffold | `infra/live/*/README.md` |
| retired | _none_ |
<!-- END GENERATED REFERENCE -->

## Notes

Units and stacks are never generated. This pack creates the frame —
`infra/live/root.hcl`, `service.hcl`, an `account.hcl` per environment and the
workflow — and `infra/units/**` and `infra/stacks/**` are yours.

State is keyed `<repo_name>/<path relative to the include>`, with `repo_name`
from the generated `service.hcl`. That is what lets several repos share one
state bucket.

Three environments are supported: `dev`, `staging` and `prod`. Each is a
separate template gated on membership in `infra.envs`, because makejinja renders
a static tree. A fourth environment means a fourth template in this pack.
