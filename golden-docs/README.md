# golden-docs

An mdbook site under `docs/`, and the workflow that publishes it to GitHub
Pages. The same setup flake-hub's own book uses.

## Files it owns

| Path | Class | Notes |
| --- | --- | --- |
| `docs/book.toml` | managed | title, theme, and the repo links |
| `docs/theme/catppuccin.css` | managed | the vendored Catppuccin stylesheet |
| `.github/workflows/docs.yml` | managed | builds and deploys on push to main |
| `docs/src/SUMMARY.md` | scaffold | the table of contents, then yours |
| `docs/src/introduction.md` | scaffold | the first page, then yours |

It also adds `docs/book/` to `.gitignore` and `docs` and `docs-build` recipes to
the justfile.

## Schema

| Key | Type | Required | Default |
| --- | --- | --- | --- |
| `docs.title` | string | no | `""` (the repo name) |
| `docs.authors` | list | no | `[ ]` |
| `docs.theme` | enum | no | `frappe` |
| `docs.repoUrl` | string | no | `""` |
| `docs.deploy` | bool | no | `true` |

## The theme

The book is Catppuccin themed. The stylesheet is vendored into the pack and
written as a managed file, so a plain `mdbook build` produces the styled book —
nothing is fetched at build time and the deploy needs no extra tool.

`docs.theme` picks the flavour: `latte`, `frappe`, `macchiato` or `mocha`. It
sets `default-theme` and `preferred-dark-theme` to the same value, so the book
looks the same whatever the reader's OS is set to.

Refreshing the stylesheet is downloading `catppuccin.css` from the upstream
release into `templates/docs/theme/` and bumping this pack's VERSION.

## The pages are yours

Only `book.toml` and the workflow are regenerated. `SUMMARY.md` and
`introduction.md` are written once and then left alone, so the pack can seed a
book without owning what the book says. Adding a chapter is adding a file under
`docs/src/` and a line to `SUMMARY.md`; the pack never sees either.

## Deploying

`docs.yml` calls the shared mdbook workflow in `Fomiller/gh-actions`, which
builds the book and deploys it to Pages. It runs on push to main, and only when
something under `docs/` or the workflow itself changed. The repo still needs
Pages turned on with GitHub Actions as the source — that is a repo setting, not
a file, so the pack cannot do it.

Set `docs.deploy = false` for a book you want to build locally but not publish.
The workflow is then not written at all, and a repo that already has it gets it
removed.

## Repo links

`docs.repoUrl` fills in `git-repository-url` and `edit-url-template`, which give
the book a source link and an edit button on every page. The edit template
assumes the book lives at `docs/` on the `main` branch. Leave `docs.repoUrl`
empty and both lines are dropped.
