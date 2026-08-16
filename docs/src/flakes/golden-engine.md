# golden-engine

The engine. It merges packs, validates `repo.nix` against their schemas, renders
the templates and writes the plan. It knows nothing about file layout: every
path, glob and template comes from a pack.

```nix
golden-engine.url = "github:Fomiller/flake-hub?dir=golden-engine&ref=refs/tags/golden-engine-<version>";
```

It has no flake inputs of its own and takes `pkgs` from the caller, so it never
pins a nixpkgs on your behalf.

## mkGolden

```nix
mkGolden { packs = [ ... ]; } pkgs repoConfig
```

returns:

| Output | What it is |
| --- | --- |
| `filesDrv` | a derivation holding the rendered files, one path per generated file |
| `plan` | a derivation holding the ownership classification as JSON |
| `generateApp` | the app that reconciles `filesDrv` and `plan` against a working tree |
| `mergedConfig` | `repo.nix` merged over pack defaults and registries |

`filesDrv` and `plan` are deliberately separate. One answers "what would these
templates produce", the other "what would happen to this repo". You can inspect
either without running the other.

## Templated paths

A template path may carry `{{ key }}` components, for any top-level string in
the merged config. `templates/helm/{{ name }}/Chart.yaml.jinja` lands at
`helm/my-service/Chart.yaml`.

makejinja renders file contents but copies path names through untouched, so
the engine substitutes paths itself, in two places that must agree: the
rendered tree and the plan. A path still holding `{{` after substitution is an
error rather than a silent miss, and ownership globs match the substituted
path — a pack writes `helm/*/Chart.yaml`, not the variable again.

## Guards fire at eval

Schema violations, ownership-glob mistakes and pack collisions all throw during
evaluation, before any build starts. A `throw` nothing forces never fires, so
`filesDrv` carries a `planChecksum` derivation attribute that hashes the plan —
building the files cannot skip validating them.
