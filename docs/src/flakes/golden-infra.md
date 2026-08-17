# golden-infra

Terragrunt scaffolding and the deploy workflow, for a repo that manages its own
AWS infrastructure.

```nix
golden-infra.url = "github:Fomiller/flake-hub?dir=golden-infra&ref=refs/tags/golden-infra-<version>";
```

<!-- BEGIN GENERATED REFERENCE -->
## repo.nix

Every knob this pack adds. Optional keys show the default they fall back
to, so deleting a line changes nothing. Required keys need a real value.

```nix
{
  infra = {
    dopplerProject = "…";  # required, string
    ownerEmail = "…";  # required, string
    stateBucket = "…";  # required, string
    awsProviderVersion = ">=5.0.0";  # string, default
    awsRegion = "us-east-1";  # string, default
    envs = [ "dev" ];  # list, default
    namespace = "fomiller";  # string, default
    tailscale = true;  # bool, default
    terraformVersion = ">=1.11.0";  # string, default
  };
}
```

## Configuration

| Key | Type | Required | Default | Description |
|---|---|---|---|---|
| `infra.awsProviderVersion` | string | no | `">=5.0.0"` | Version constraint written to the generated aws provider block. |
| `infra.awsRegion` | string | no | `"us-east-1"` | Region for the AWS provider and the state backend. |
| `infra.dopplerProject` | string | yes | — | Doppler project the deploy workflow pulls secrets from. |
| `infra.envs` | list | no | `[ "dev" ]` | Which environments get a directory under infra/live/. Only dev, staging and prod exist. |
| `infra.namespace` | string | no | `"fomiller"` | Prefix on resource names, so two repos in one account do not collide. |
| `infra.ownerEmail` | string | yes | — | Goes on every resource as an owner tag. |
| `infra.stateBucket` | string | yes | — | S3 bucket holding terraform state. Shared across repos. |
| `infra.tailscale` | bool | no | `true` | Whether the deploy workflow joins Tailscale before running terragrunt. |
| `infra.terraformVersion` | string | no | `">=1.11.0"` | Version constraint written to the generated required_version. |

## Files

| Class | Paths |
|---|---|
| managed | `infra/live/root.hcl`, `infra/live/service.hcl`, `infra/live/tags.hcl`, `infra/live/version.hcl`, `infra/live/*/account.hcl`, `.github/workflows/deploy-infra.yml` |
| scaffold | `infra/live/*/README.md`, `infra/live/*/terragrunt.stack.hcl` |
| retired | _none_ |
<!-- END GENERATED REFERENCE -->

## Notes

Units and stacks are never generated. This pack creates the frame — the four
shared files under `infra/live/`, an `account.hcl` and a starter
`terragrunt.stack.hcl` per environment, and the workflow. `infra/units/**` and
`infra/stacks/**` are yours.

Only those files are committed under `infra/live/<env>/`. Everything else that
turns up there is written by `terragrunt stack run` and is gitignored; the pack
adds the ignore lines. A generated unit directory in git is a copy that goes
stale.

`root.hcl` derives which provider to configure from the unit's own path —
`path_relative_to_include()` is `<env>/<provider>/<scope>/<unit...>`, and
segment 1 is the provider. Terragrunt treats a child `generate` block that
shadows an inherited one as an error, so this cannot be a per-unit override.

State is keyed `<repo_name>/<path relative to the include>`, with `repo_name`
from the generated `service.hcl`. That is what lets several repos share one
state bucket.

Three environments are supported: `dev`, `staging` and `prod`. Each is a
separate template gated on membership in `infra.envs`, because makejinja renders
a static tree. A fourth environment means a fourth template in this pack.
