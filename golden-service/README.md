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
| `language` | enum `go`\|`rust`\|`node` | yes | — |
| `service.container` | bool | no | `true` |
| `service.port` | int | no | `8080` |
| `service.binary` | string | no | the repo `name` |
| `service.entrypoint` | string | no | `dist/index.js` |

`service.binary` has no pack default because it falls back to the repo's own
name, which a pack cannot see. The template resolves it.

`service.entrypoint` applies to `node` only. It is the built script the
container runs, relative to `/app`. An Astro standalone build wants
`dist/server/entry.mjs`.

## Source layout

Language code lives under `src/`. Go puts its main package at
`src/cmd/<binary>/`, with `go.mod` staying at the repo root so `setup-go` and
`go mod download` still find it. Rust needs nothing special — `src/` is already
where Cargo looks.

The Go build writes to `bin/`, not the repo root, so a plain `just build` does
not leave an untracked executable behind. `bin/`, `target/`, `node_modules/`
and `dist/` all come from this pack's `gitignore` entries.

## What `node` expects from the repo

Go and Rust each have one canonical build command, so the registry names the
tool. TypeScript does not — the command depends on the framework — so the
registry calls npm scripts and the repo decides what they run. `package.json`
must define all four:

| Script | Runs |
| --- | --- |
| `build` | whatever produces `dist/` |
| `test` | the test suite |
| `lint` | the linter |
| `typecheck` | `tsc --noEmit`, or `astro check` for an Astro repo |

`typecheck` is separate from `lint` and CI runs both. A bundler strips types
without checking them, so a repo that only lints still ships type errors.

`npm ci` runs in CI and in the Dockerfile, so `package-lock.json` has to be
committed and agree with `package.json`.

Node's version is pinned in `registry.nix` rather than read from a `.nvmrc`,
matching how the Go and Rust images are pinned. Bumping it is an edit there and
a pack release.

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
