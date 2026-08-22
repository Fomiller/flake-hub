# golden-service

A compiled service: the Dockerfile, the build-test CI job, and the language
registry that both read.

```nix
golden-service.url = "github:Fomiller/flake-hub?dir=golden-service&ref=refs/tags/golden-service-<version>";
```

<!-- BEGIN GENERATED REFERENCE -->
## repo.nix

Every knob this pack adds. Optional keys show the default they fall back
to, so deleting a line changes nothing. Required keys need a real value.

```nix
{
  language = "go";  # required, enum: go | rust | node
  service = {
    binary = "…";  # string, no default
    container = true;  # bool, default
    entrypoint = "…";  # string, no default
    port = 8080;  # int, default
  };
}
```

## Configuration

| Key | Type | Required | Default | Description |
|---|---|---|---|---|
| `language` | enum (`go`, `rust`, `node`) | yes | — | Picks the CI steps, the just recipes, and the Dockerfile base images. |
| `service.binary` | string | no | — | Binary name, if it is not the repo name. Compiled languages only. |
| `service.container` | bool | no | `true` | Whether to write a Dockerfile. Off for a library. |
| `service.entrypoint` | string | no | — | node only. Build output the container runs, relative to /app. Defaults to dist/index.js. |
| `service.port` | int | no | `8080` | Port the service listens on. Reaches the Dockerfile and the chart. |

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
