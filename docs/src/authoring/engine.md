# Changing the engine

Two rules keep the engine general:

1. **It knows no file layout.** Every path, glob, template and default comes
   from a pack. If a change would put a filename in `golden-engine`, it belongs
   in a pack instead.
2. **It performs no lookups of its own.** Variation between repos is data. The
   language table lives in `golden-service`'s registry and the templates index
   it; the engine just merges the registry into the render data.

## filesDrv and plan

`filesDrv` is the rendered tree. `plan` is the ownership classification. They
are separate on purpose: you can ask what a template produces without asking
what would happen to a repo, and the reconciler needs the second without
re-deriving the first.

`reconcile.py` carries out the plan and names no path of its own. Every path it
touches comes from the plan JSON.

## Every guard needs two things

Validation happens as lazy `throw`s. A `throw` nothing forces never fires — it
sits there unevaluated and the guard silently checks nothing. So a new guard
needs:

1. **A binding a real output forces.** `mkGolden.nix` hashes the plan into
   `filesDrv`'s derivation attributes as `planChecksum`, so building the files
   cannot skip validating the plan. Delete that one line and `filesDrv` builds
   happily for a repo whose plan is invalid.
2. **A test that goes red when the guard is removed.** Not a test that passes
   with the guard — a test you have watched fail without it. Several guards in
   this repo throw for more than one reason, so a test asserting only "it
   throws" can pass against a broken guard. Assert the message.

Both are required. This has bitten the project more than once.

## Checklist for an engine change

- [ ] the change adds no file layout knowledge
- [ ] `golden-engine/VERSION` bumped
- [ ] a nix-unit case in `golden-base/tests/eval_units.nix`
- [ ] that case proven red by reverting the change
- [ ] `nix flake check` green on every pack, since they all consume the engine
