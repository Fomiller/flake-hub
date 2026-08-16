# golden-infra

Terragrunt scaffolding and the deploy workflow, for a repo that manages its own
AWS infrastructure. It generates the frame only: `infra/units/**` and
`infra/stacks/**` are yours and are never touched.

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
| `infra.stateBucket` | string | yes | — |
| `infra.ownerEmail` | string | yes | — |
| `infra.envs` | list | no | `[ "dev" ]` |
| `infra.awsRegion` | string | no | `us-east-1` |
| `infra.namespace` | string | no | `fomiller` |
| `infra.tailscale` | bool | no | `true` |
| `infra.terraformVersion` | string | no | `>=1.11.0` |
| `infra.awsProviderVersion` | string | no | `>=5.0.0` |

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
own template, gated on membership in `infra.envs`. An unselected environment
renders empty and is never copied out. A fourth environment means a fourth
template.
