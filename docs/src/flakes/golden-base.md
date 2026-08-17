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
    recipes = [ ];  # list, default
  };
  unmanaged = [ ];  # list, default
}
```

## Configuration

| Key | Type | Required |
|---|---|---|
| `description` | string | no |
| `gitignore` | list | no |
| `just.recipes` | list | no |
| `name` | string | yes |
| `unmanaged` | list | no |

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
