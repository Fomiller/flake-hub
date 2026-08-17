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
    awsProviderVersion = ">=5.0.0";  # string, default
    awsRegion = "us-east-1";  # string, default
    envs = [ "dev" ];  # list, default
    namespace = "fomiller";  # string, default
    stateBucket = "";  # string, default
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
| `infra.ownerEmail` | string | yes | — | Goes on every resource as an owner tag. infra/live/variables.hcl can override it per tree. |
| `infra.stateBucket` | string | no | `""` | S3 bucket holding terraform state. Left empty, root.hcl derives <namespace>-<env>-terraform-state. infra/live/variables.hcl overrides either. |
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

## variables.hcl

Two values can be changed without touching `repo.nix`: the state bucket and the
owner email. Write a `variables.hcl` anywhere at or above a unit — usually
`infra/live/` for the whole repo, or `infra/live/<env>/` for one environment:

```hcl
locals {
  bucket      = "some-other-bucket"
  owner_email = "someone@else"
}
```

The file is optional, is never generated, and may set one key or both. Nearest
file wins.

Order for the bucket: `variables.hcl`, then `infra.stateBucket` from
`repo.nix`, then a derived `<namespace>-<env>-terraform-state`. Order for the
email: `variables.hcl`, then `infra.ownerEmail`.

Both overrides are resolved in `root.hcl`, not in `tags.hcl`. Inside a config
that terragrunt reads through `read_terragrunt_config`, `find_in_parent_folders`
starts above that file's own directory, so a `variables.hcl` sitting beside
`tags.hcl` would never be found.

Three environments are supported: `dev`, `staging` and `prod`. Each is a
separate template gated on membership in `infra.envs`, because makejinja renders
a static tree. A fourth environment means a fourth template in this pack.
