# golden-docs

An mdbook site under `docs/`, and the workflow that publishes it to GitHub
Pages. The same setup this book uses.

```nix
golden-docs.url = "github:Fomiller/flake-hub?dir=golden-docs&ref=refs/tags/golden-docs-<version>";
```

<!-- BEGIN GENERATED REFERENCE -->
## repo.nix

Every knob this pack adds. Optional keys show the default they fall back
to, so deleting a line changes nothing. Required keys need a real value.

```nix
{
  docs = {
    authors = [ ];  # list, default
    deploy = true;  # bool, default
    repoUrl = "";  # string, default
    theme = "frappe";  # enum: latte | frappe | macchiato | mocha, default
    title = "";  # string, default
  };
}
```

## Configuration

| Key | Type | Required | Default | Description |
|---|---|---|---|---|
| `docs.authors` | list | no | `[ ]` | Names written to book.toml's authors list. |
| `docs.deploy` | bool | no | `true` | Whether to write the workflow that publishes the book to GitHub Pages. |
| `docs.repoUrl` | string | no | `""` | Repo URL. When set, the book gets a source link and per-page edit links. |
| `docs.theme` | enum (`latte`, `frappe`, `macchiato`, `mocha`) | no | `"frappe"` | Catppuccin flavour the book is themed with. |
| `docs.title` | string | no | `""` | Book title. Falls back to the repo name when empty. |

## Files

| Class | Paths |
|---|---|
| managed | `docs/book.toml`, `docs/theme/catppuccin.css`, `.github/workflows/docs.yml` |
| scaffold | `docs/src/SUMMARY.md`, `docs/src/introduction.md` |
| retired | _none_ |
<!-- END GENERATED REFERENCE -->

## Notes

Only `book.toml`, the stylesheet and the workflow are regenerated. `SUMMARY.md`
and `introduction.md` are written once and then left alone, so the pack can seed
a book without owning what the book says. A new chapter is a file under
`docs/src/` and a line in `SUMMARY.md`; the pack never sees either.

The book is Catppuccin themed. `docs/theme/catppuccin.css` is vendored into the
pack and written as a managed file, so a plain `mdbook build` produces the
styled book and nothing has to be fetched at build time. `docs.theme` picks the
flavour, and it sets both `default-theme` and `preferred-dark-theme` so the book
looks the same whatever the reader's OS is set to.

`docs.yml` calls the shared mdbook workflow in `Fomiller/gh-actions`. It runs on
push to main, and only when something under `docs/` or the workflow itself
changed. The repo still needs Pages turned on with GitHub Actions as the source
— that is a repo setting, not a file, so the pack cannot do it.

`docs.deploy = false` drops the workflow entirely, for a book you want to build
locally but not publish. A repo that already has the workflow gets it removed.

`docs.repoUrl` fills in `git-repository-url` and `edit-url-template`, which give
the book a source link and an edit button on every page. The edit template
assumes the book lives at `docs/` on `main`. Leave it empty and both lines are
dropped.
