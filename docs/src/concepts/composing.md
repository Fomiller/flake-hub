# Composing packs

Packs are additive. The list in `mkGolden` is ordered, and the order matters in
three places.

## Collisions are errors, not silent wins

Two packs emitting the same path fails at eval:

```
mkGolden: pack merge failed:
  golden-service and golden-base both emit 'justfile'. Add it to golden-service's `overrides` if that is intended.
```

The later pack wins, but only if it names the path in its own `overrides`.
Without that, the collision is an error — so a pack cannot quietly take over a
file another pack owns.

The same rule applies to partials, which is why every pack ships its header
partial under its own name (`_github_header.jinja`, `_service_header.jinja`, and
so on) rather than sharing one.

## Lists concatenate, `repo.nix` replaces

Pack defaults merge additively: two packs contributing to `just.recipes` or
`ci.jobs` both keep their entries, in pack order. That is what lets
`golden-service` add a CI job to a workflow `golden-github` owns.

`repo.nix` is not additive. It merges over the result with replace semantics, so
a repo can clear an inherited list with `[ ]` — but cannot append to one.

## The standard combinations

| Repo | Packs |
| --- | --- |
| Anything on GitHub | `golden-base`, `golden-github` |
| A compiled service | the above plus `golden-service` |
| A service deployed by Argo CD | the above plus `golden-argocd` |
| A terragrunt repo | `golden-base`, `golden-github`, `golden-infra` |

`golden-engine` is not in the pack list — it is the thing the list is passed to.

## Contributing to a file you do not own

A pack adds to another pack's file by adding to a shared list in its `defaults`,
never by templating that file. The owning pack decides how the entries render.

Keep the contribution opaque to the owner. `golden-service` contributes a CI job
carrying `stepsFrom = "language"`, and `golden-github` renders it without ever
learning what a language is.
