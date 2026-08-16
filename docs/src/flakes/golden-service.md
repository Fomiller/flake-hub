# golden-service

A compiled service: the Dockerfile, the build-test CI job, and the language
registry that both read.

```nix
golden-service.url = "github:Fomiller/flake-hub?dir=golden-service&ref=refs/tags/golden-service-<version>";
```

<!-- BEGIN GENERATED REFERENCE -->
## repo.nix

Every knob this pack adds. Required keys are filled in; optional ones are
commented out beside the default they fall back to.

```nix
{
  language = "go";  # required, enum: go | rust
  service = {
    # binary = "…";  # string, no default
    # container = true;  # bool, default
    # port = 8080;  # int, default
  };
}
```

## Configuration

| Key | Type | Required |
|---|---|---|
| `language` | enum (`go`, `rust`) | yes |
| `service.binary` | string | no |
| `service.container` | bool | no |
| `service.port` | int | no |

## Files

| Class | Paths |
|---|---|
| managed | `Dockerfile` |
| scaffold | _none_ |
| retired | _none_ |
<!-- END GENERATED REFERENCE -->

## Notes

Language code goes under `src/`. Go's main package is `src/cmd/<binary>/`, and
`go.mod` stays at the repo root so `setup-go` and `go mod download` still find
it. Rust already uses `src/`, so nothing changes there.

Go builds land in `bin/` rather than the repo root. This pack adds `bin/` and
`target/` to `gitignore`, which is a list key and therefore additive across
packs.

`service.container = false` does not just skip the Dockerfile — it removes it.
A managed path missing from the rendered tree is deleted, so flipping the flag
on an existing repo deletes the file rather than leaving a stale one.

`service.binary` has no default because it falls back to the repo's `name`,
which a pack cannot see. The template resolves it.

The language table lives in this pack's `registry.nix`. Adding a language is a
change here plus a branch in each template that needs it — never a change in a
consumer repo.
