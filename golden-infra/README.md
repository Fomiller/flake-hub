# golden-infra

Terragrunt scaffolding and the deploy workflow, for a repo that manages its own
AWS infrastructure. It generates the frame, plus one unit: the ECR
repositories the publish workflows push to. Everything else under
`infra/units/**` and `infra/stacks/**` is yours and is never touched.

## Files it owns

| Path | Class | Notes |
| --- | --- | --- |
| `infra/live/root.hcl` | managed | backend, provider, versions. Every unit includes it |
| `infra/live/service.hcl` | managed | `repo_name`, which namespaces this repo's state |
| `infra/live/tags.hcl` | managed | default tags on every resource |
| `infra/live/version.hcl` | managed | terraform and provider version floors |
| `infra/live/<env>/account.hcl` | managed | one per selected environment |
| `.github/workflows/deploy-infra.yml` | managed | plan on PR, apply on push, per environment |
| `infra/live/<env>/terragrunt.stack.hcl` | scaffold | which stacks the environment gets |
| `infra/live/<env>/README.md` | scaffold | written once, then the directory is yours |
| `infra/stacks/aws/common/terragrunt.stack.hcl` | scaffold | the units every environment shares |
| `infra/units/aws/common/ecr/*` | scaffold | the image and chart repositories. Off with `infra.ecr = false` |

## The layout

```
infra/
  live/
    root.hcl  service.hcl  tags.hcl  version.hcl
    <env>/
      account.hcl
      terragrunt.stack.hcl
      README.md
  stacks/<provider>/<scope>/terragrunt.stack.hcl
  units/<provider>/<scope>/<unit>/
```

Only those three files per environment are committed. Everything else that
appears under `infra/live/<env>/` is written by `terragrunt stack run` from
`stacks/` and `units/`, and is gitignored — the pack adds the ignore lines. A
generated unit directory in git is a copy that goes stale.

## Schema

| Key | Type | Required | Default |
| --- | --- | --- | --- |
| `infra.dopplerProject` | string | yes | — |
| `infra.ownerEmail` | string | yes | — |
| `infra.enabled` | bool | no | `true` |
| `infra.ecr` | bool | no | `true` |
| `infra.namespace` | string | no | `fomiller` |
| `infra.terraformVersion` | string | no | `>=1.11.0` |
| `infra.awsProviderVersion` | string | no | `>=5.0.0` |
| `infra.environments.<env>` | attrsOf | no | dev on, staging and prod off |

`<env>` is `dev`, `staging` or `prod`, and each block takes `enabled`,
`account`, `region`, `rolePrefix`, `profile` and `stateBucket`. Anything not
set falls back to the pack default, so an environment usually needs one or two
lines. The values land in that environment's `account.hcl`.

`infra.enabled = false` retires `infra/` wholesale — hand-written units and
stacks included — and drops the deploy workflow.

## variables.hcl

An optional hand-written `infra/live/variables.hcl` (or
`infra/live/<env>/variables.hcl`, nearest wins) can set `bucket` and
`owner_email`. Both are resolved in `root.hcl`, which is the only file that
reads it — inside a nested `read_terragrunt_config`, `find_in_parent_folders`
starts above that file's own directory, so `tags.hcl` cannot see a sibling
`variables.hcl`.

Bucket order: `variables.hcl`, the environment's `stateBucket` (carried by
`account.hcl`), then a derived `<namespace>-<env>-terraform-state`. Email
order: `variables.hcl`, then `infra.ownerEmail`.

## The state key

`root.hcl` keys state as `<repo_name>/<path relative to the include>`. That is
what lets many repos share one state bucket. A pack that hardcoded the key would
collide the first time two generated repos both had a unit at the same path.

## Which provider a unit gets

`root.hcl` reads it out of the unit's own path. `path_relative_to_include()` is
`<env>/<provider>/<scope>/<unit...>`, so segment 1 is the provider, and the
`provider` and `versions` blocks are generated from a lookup table keyed on it.
Terragrunt rejects a child `generate` block that shadows an inherited one, so
per-unit overrides are not available — it has to be one conditional generator.
Only `aws` ships in the table. Adding a provider is adding an entry.

## Environments are a fixed set

makejinja renders a static tree, so a variable number of directories has to come
from a fixed set of gated templates. `dev`, `staging` and `prod` each have their
own template, gated on `infra.environments.<env>.enabled`. The schema fixes the
allowed names, so a typo is an error rather than a block nothing reads. An
unselected environment
renders empty and is never copied out. A fourth environment means a fourth
template.
