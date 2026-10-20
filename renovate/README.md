# renovate

The shared Renovate preset that bumps flake-hub pack pins. Consumers extend it:

```json
{
  "extends": ["github>Fomiller/flake-hub//renovate/default"]
}
```

The cluster's own Renovate config extends the same file, so the regex lives in
one place.

## Why the per-pack anchor

Every pack ships from one repo, tagged `<pack>-<semver>`. So `github-tags` on
`Fomiller/flake-hub` returns every pack's tags for every pin. Without filtering,
a `golden-infra` release looks like an upgrade for a `golden-github` pin.

The versioning stops that. It is a `regex:` versioning whose `compatibility`
group is the pack prefix. Renovate only offers a tag as an upgrade when its
`compatibility` matches the current one, so a `golden-github-*` pin only ever
moves to another `golden-github-*` tag.

`currentValue` is the full tag, prefix included, so the update rewrites the
whole tag and never leaves a stale prefix behind.

Renovate runs these patterns through RE2, which has no backreferences. A
`\k<name>` in `matchStrings` fails validation and Renovate skips the repo with
a config error. `tests/preset_test.py` runs every pattern through RE2 for that
reason.

## The nix manager is off

Consumers regenerate `flake.lock` in their own workflow. Letting Renovate's nix
manager touch it too produces two conflicting bumps for the same input.
