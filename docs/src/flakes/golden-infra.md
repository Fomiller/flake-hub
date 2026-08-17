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
    enabled = true;  # bool, default
    environments = {  # one of: dev, staging, prod
      dev = {
        account = "";  # string
        enabled = true;  # bool
        profile = "";  # string
        region = "us-east-1";  # string
        rolePrefix = "";  # string
        stateBucket = "";  # string
      };
    };
    namespace = "fomiller";  # string, default
    terraformVersion = ">=1.11.0";  # string, default
  };
}
```

## Configuration

| Key | Type | Required | Default | Description |
|---|---|---|---|---|
| `infra.awsProviderVersion` | string | no | `">=5.0.0"` | Version constraint written to the generated aws provider block. |
| `infra.dopplerProject` | string | yes | — | Doppler project the deploy workflow pulls secrets from. |
| `infra.enabled` | bool | no | `true` | Whether this repo manages infrastructure. False deletes infra/ and the deploy workflow. |
| `infra.environments` | attrsOf (`dev`, `staging`, `prod`) | no | — | Per-environment settings. An environment exists under infra/live/ only while its enabled is true. |
| `infra.environments.<name>.account` | string | no | `""` | AWS account ID, written to account.hcl for the units to read. |
| `infra.environments.<name>.enabled` | bool | no | `true` | Whether this environment gets a directory under infra/live/. |
| `infra.environments.<name>.profile` | string | no | `""` | Local AWS profile name, for running terragrunt by hand. |
| `infra.environments.<name>.region` | string | no | `"us-east-1"` | Region for the AWS provider, the state backend and the deploy job. |
| `infra.environments.<name>.rolePrefix` | string | no | `""` | Role-name base the units build their OIDC ARNs from. |
| `infra.environments.<name>.stateBucket` | string | no | `""` | Overrides the derived <namespace>-<env>-terraform-state. infra/live/variables.hcl still wins. |
| `infra.namespace` | string | no | `"fomiller"` | Prefix on resource names, so two repos in one account do not collide. |
| `infra.ownerEmail` | string | yes | — | Goes on every resource as an owner tag. infra/live/variables.hcl can override it per tree. |
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

Order for the bucket: `variables.hcl`, then the environment's `stateBucket`
(which `account.hcl` carries), then a derived
`<namespace>-<env>-terraform-state`. Order for the email: `variables.hcl`, then
`infra.ownerEmail`.

Both overrides are resolved in `root.hcl`, not in `tags.hcl`. Inside a config
that terragrunt reads through `read_terragrunt_config`, `find_in_parent_folders`
starts above that file's own directory, so a `variables.hcl` sitting beside
`tags.hcl` would never be found.

## Environments

Three are supported: `dev`, `staging` and `prod`. Each is a separate template
gated on `infra.environments.<env>.enabled`, because makejinja renders a static
tree. A fourth environment means a fourth template in this pack, which is why
the schema fixes the allowed names — a typo is an error, not a silently ignored
block.

An environment only has to name what it changes. Everything else comes from the
pack default, so this is a complete `repo.nix` for two environments:

```nix
infra = {
  dopplerProject = "my-service";
  ownerEmail = "forrestmillerj@gmail.com";
  environments = {
    dev.account = "111122223333";
    prod = {
      enabled = true;
      account = "444455556666";
      region = "us-west-2";
    };
  };
};
```

`account`, `region`, `profile`, `rolePrefix` and `stateBucket` land in that
environment's `account.hcl`, which is what `root.hcl` and the units read. An
empty one is left out of the file rather than written blank.

## Turning the pack off

`infra.enabled = false` deletes `infra/` outright — units, stacks and all — and
removes the deploy workflow. That is a retired tree, not a gated file: it takes
hand-written code with it. The `plan` and `apply` recipes stay in the justfile,
since pack defaults are static.
