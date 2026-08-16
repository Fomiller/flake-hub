# golden-service

A compiled service: the Dockerfile, the build-test CI job, and the language
registry that both read.

```nix
golden-service.url = "github:Fomiller/flake-hub?dir=golden-service&ref=refs/tags/golden-service-<version>";
```

<!-- BEGIN GENERATED REFERENCE -->
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

`service.container = false` does not just skip the Dockerfile — it removes it.
A managed path missing from the rendered tree is deleted, so flipping the flag
on an existing repo deletes the file rather than leaving a stale one.

`service.binary` has no default because it falls back to the repo's `name`,
which a pack cannot see. The template resolves it.

The language table lives in this pack's `registry.nix`. Adding a language is a
change here plus a branch in each template that needs it — never a change in a
consumer repo.
