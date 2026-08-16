# Ownership classes

Every path a pack emits is classified. The class decides what `generate` does to
it.

| Class | Behavior |
| --- | --- |
| `managed` | Overwritten every run. If the template renders empty, the file is **deleted**. |
| `scaffold` | Written once. After that it is the repo's, and `generate` never touches it again. |
| `retired` | Deleted, if present. |
| `unmanaged` | Never touched. Declared per repo in `repo.nix`, not per pack. |

A path that a pack emits but no glob classifies is an error, not a default. So
is a `retired` path a pack still emits, and a path matching both a managed and a
scaffold glob.

## Deletion is the gating mechanism

A managed path missing from the rendered tree is deleted. That is not a
side effect — it is how a pack turns a file off. `service.container = false`
gates the whole Dockerfile template, the render comes out empty, makejinja does
not copy an empty render out, and `generate` removes the file from the repo.

The consequence: if you delete a template, every repo pinned to the next release
loses that file. That is usually what you want. When it is not, the path goes in
`retired` first.

## The executable bit

Separate from the class. A pack lists globs under `executable`, and anything
matched lands `0755` instead of `0644`. A file is managed *and* executable; the
two are independent.

Mode counts as drift on its own. A file whose contents are right but whose mode
is wrong gets corrected and reported as a change.

## I want to hand-edit a generated file

You don't. Three options, in order of preference:

1. Change `repo.nix`. Most differences between repos are meant to be
   configuration.
2. Change the template in the pack that owns it. If the difference is one every
   repo would want, this is the right place.
3. Add the path to `unmanaged` in `repo.nix`. The generator then leaves it
   alone entirely — and stops enforcing it, forever, silently. A stale
   `unmanaged` entry that matches no generated path is an error, so at least the
   list cannot rot unnoticed.
