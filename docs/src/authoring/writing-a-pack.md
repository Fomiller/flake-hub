# Writing a pack

A pack is a directory with a `flake.nix`, a `pack.nix`, a `VERSION`, and
template and partial directories.

## The pack.nix contract

Every field is required. They are read directly, not with a fallback, so a
misspelled field name is an evaluation error rather than silence.

| Field | Type | What it is |
| --- | --- | --- |
| `name` | string | the pack's name, stamped into generated headers |
| `templates` | path | the template root. Every file here becomes a generated path |
| `partials` | path or `null` | includes. Every file must be named `_*` |
| `defaults` | attrs | config defaults. Lists here concatenate across packs |
| `registry` | attrs | lookup tables the templates index. Not validated against the schema |
| `ownership` | attrs | `managed`, `scaffold` and `retired` glob lists |
| `overrides` | list | paths this pack deliberately takes over from an earlier pack |
| `executable` | list | globs whose generated files land `0755` |
| `schema` | attrs | dotted key to `{ type; description; required?; values?; }` |

Schema types: `string`, `bool`, `int`, `list`, `attrs`, `enum` (with `values`).

`description` is one sentence, and it is not optional — `gen-reference` throws
on a key without one, so a pack with an undocumented knob cannot make it into
the docs.

## Templates

A template at `templates/<path>.jinja` renders to `<path>`. The `.jinja`
suffix is stripped; a file without it is copied as-is.

Files named `_*` are excluded from rendering — that is how partials stay out of
the output. It also means a generated file cannot start with an underscore. Helm
charts feel this: the conventional `_helpers.tpl` has to be `helpers.tpl`.

An empty render is not copied out. Wrapping a whole template in
`{% if some.flag %}` is therefore how a pack gates a file off, and a managed
path missing from the render is deleted from the repo.

## Escaping

Jinja owns `{{ }}` and `{% %}`. Two other things want them:

- GitHub Actions expressions: `{% raw %}${{ github.ref }}{% endraw %}`
- Helm: wrap the whole template body in `raw`, and close and reopen it around
  the handful of build-time values.

`trim_blocks` is on, so the newline after a block tag is eaten. That silently
joins the next YAML line onto the current one. Use `{% endraw +%}` when the
newline must survive:

```jinja
  group: {% raw %}${{ github.workflow }}{% endraw +%}
  cancel-in-progress: true
```

Without the `+`, those become one line and the YAML is wrong in a way no
template test would notice — which is why the rendered workflows go through
actionlint.

Data is not re-rendered. A string in `defaults` containing `{{ }}` reaches the
output verbatim, so just recipes with `{{env}}` need no escaping at all.

## Tests

The pattern is a fixture plus an expected tree:

- `tests/fixtures/<case>.nix` — a `repo.nix` for that case
- `tests/expected/<case>/` — the files this pack owns, exactly as rendered
- a check that diffs every file in the expected tree against the render

Snapshot only the paths this pack owns. Another pack's files are covered by that
pack's snapshot, and duplicating them means two places to update for one change.

Assert absences too. A gated file that stops being gated will pass every
snapshot you wrote, because the snapshot only checks files it knows about.

## Checklist for a new pack

- [ ] directory with `flake.nix`, `pack.nix`, `VERSION`, `README.md`
- [ ] a header partial named after the pack (`_<pack>_header.jinja`)
- [ ] at least one fixture and expected tree
- [ ] a check asserting whatever the pack gates off
- [ ] an entry in `.github/workflows/ci.yaml`'s `flake-dirs`
- [ ] an entry in `.github/workflows/release.yaml`'s `flake-dirs`
- [ ] the pack and its version in `golden-base/pack-versions.nix`
- [ ] a page under `docs/src/flakes/` with the generated-region markers
