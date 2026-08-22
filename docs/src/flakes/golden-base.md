# golden-base

The files every repo gets: `.gitignore`, a `justfile` and a `README.md`.
Selecting it is not optional — `init` always includes it.

```nix
golden-base.url = "github:Fomiller/flake-hub?dir=golden-base&ref=refs/tags/golden-base-<version>";
```

<!-- BEGIN GENERATED REFERENCE -->
## repo.nix

Every knob this pack adds. Optional keys show the default they fall back
to, so deleting a line changes nothing. Required keys need a real value.

```nix
{
  name = "…";  # required, string
  description = "";  # string, default
  gitignore = [ "result" "result-*" ".direnv/" ".DS_Store" ];  # list, default
  just = {
    enabled = true;  # bool, default
    recipes = [ ];  # list, default
    variables = [ ];  # list, default
  };
  namePrefix = "";  # string, default
  slug = "";  # string, default
  unmanaged = [ ];  # list, default
}
```

## Configuration

| Key | Type | Required | Default | Description |
|---|---|---|---|---|
| `description` | string | no | `""` | One line about the repo. Shown in the generated README. |
| `gitignore` | list | no | `[ "result" "result-*" ".direnv/" ".DS_Store" ]` | Lines written to .gitignore, one per entry. Packs append to this. |
| `just.enabled` | bool | no | `true` | Whether to write the justfile. False leaves the repo with no recipes at all. |
| `just.recipes` | list | no | `[ ]` | Recipes written to the justfile. Packs append to this. |
| `just.variables` | list | no | `[ ]` | Top-level justfile variables, as { name, value }. Declaring one is what lets `just name=value <recipe>` override it. Packs append to this. |
| `name` | string | yes | — | Repo name. Reaches the README, the chart directory, and the image repository. |
| `namePrefix` | string | no | `""` | Prefix stripped from name to get the slug. Only read when slug is empty. |
| `slug` | string | no | `""` | Short name for display. Empty means name with namePrefix removed. |
| `unmanaged` | list | no | `[ ]` | Paths the engine leaves alone even though a pack owns them. |

## Files

| Class | Paths |
|---|---|
| managed | `.gitignore`, `justfile` |
| scaffold | `README.md` |
| retired | `.editorconfig`, `.envrc` |
<!-- END GENERATED REFERENCE -->

## Notes

`just.recipes` is a shared list. Any pack can append to it, and the entries land
in the `justfile` in pack order. A repo can replace the whole list from
`repo.nix`, but cannot append to it.

`README.md` is scaffold: it is written once, and after that it is yours. The
generator never touches it again, so the first commit is the only chance to get
a starting point from here.
