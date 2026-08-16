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

Three pieces stop that:

- The `\k<depName>` backreference in `matchStrings` makes the `?dir=` directory
  and the tag prefix agree before a pin is considered at all. A `golden-github`
  directory pinned to a `golden-infra` tag matches nothing, which is the right
  answer — that pin is already wrong and Renovate should not paper over it.
- `extractVersionTemplate` is `^{{{depName}}}-(?<version>.+)$`, which keeps only
  the one pack's tags and strips the prefix so `semver` can compare them.
- `depName` therefore has to stay the pack name. Setting `depNameTemplate` would
  overwrite it with the repo slug, the anchor would become
  `^Fomiller/flake-hub-…`, and it would match no tag at all. `packageName` is
  what the datasource is queried with, so that is where the repo slug goes.

`tests/preset_test.py` runs the regex and resolves the templates the way
Renovate does, including that overwrite. Renovate's regexes are JS, so the test
translates the two constructs Python spells differently rather than keeping a
second copy of the pattern that could drift.

## The nix manager is off

Consumers regenerate `flake.lock` in their own workflow. Letting Renovate's nix
manager touch it too produces two conflicting bumps for the same input.
