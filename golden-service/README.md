# golden-service

The files a compiled service needs. Add this pack when the repo builds a binary
and ships it as a container.

## Files it owns

| Path | Class | Notes |
| --- | --- | --- |
| `Dockerfile` | managed | multi-stage build, images from the language registry. Not emitted when `service.container = false` |

## Schema

| Key | Type | Required | Default |
| --- | --- | --- | --- |
| `language` | enum `go`\|`rust` | yes | — |
| `service.container` | bool | no | `true` |
| `service.port` | int | no | `8080` |
| `service.binary` | string | no | the repo `name` |

`service.binary` has no pack default because it falls back to the repo's own
name, which a pack cannot see. The template resolves it.

## The language registry

`registry.nix` maps each language to its build image, runtime image, setup step
and build/test/lint commands. Templates index it as `languages[language]`. The
engine performs no lookup of its own — it merges the registry into the render
data and the template does the rest. Adding a language is one entry here plus a
branch in the templates that need it.

## Turning the container off

`service.container = false` gates the whole `Dockerfile` template, so it renders
empty and never lands. A managed path missing from the rendered files is deleted
from the repo, so flipping the flag on an existing repo removes the file rather
than leaving a stale one behind.
