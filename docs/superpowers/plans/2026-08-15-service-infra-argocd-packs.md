# golden-service, golden-infra, golden-argocd Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The three packs that make the generator useful for real repos — a compiled service, a terragrunt repo, and Argo CD delivery — plus the one engine change they all need.

**Architecture:** Packs contribute to files they do not own by adding entries to shared lists in their `defaults` (CI steps, just recipes). That needs one engine change: when pack defaults are merged with each other, lists concatenate; when `repo.nix` is merged on top, lists replace. Language variation is a lookup table in `golden-service`'s registry that templates index by `language`, so the engine still performs no lookups of its own.

**Tech Stack:** Nix flakes, makejinja, Helm, terragrunt, GitHub Actions, ECR (OCI charts).

## Global Constraints

- Prerequisites: plans `2026-08-15-golden-engine-and-base.md` and `2026-08-15-golden-github-and-ci.md` complete and merged.
- Homelab is the reference for the infra layout: `infra/units`, `infra/stacks`, `infra/live/<env>`, `just/terraform.just`, `deploy-infra.yaml` calling `Fomiller/gh-actions/.github/workflows/terragrunt.yaml`. Read `~/dev/personal/homelab` before Task 4. Generate scaffolding and CI only — never units, stacks, or modules.
- Helm templates are full of `{{ }}`, which collides with Jinja. Wrap the entire body of every `deploy/chart/templates/*.yaml.jinja` in `{% raw %}...{% endraw %}` and use `{% endraw +%}` where a newline must survive.
- Every pack change bumps that pack's `VERSION`. `version-bump-check.yaml` enforces it.
- Engine changes bump `golden-engine/VERSION` and need a nix-unit case that goes red when the change is reverted.
- Commit messages: conventional prefix, scope `FOM-51`, `Co-Authored-By: Claude` trailer.
- Read `docs/superpowers/notes/helm-chart-repo-findings.md` before Tasks 2, 4 and 5. It records
  what a hand-built chart repo already got wrong, and this plan is meant to lift from it rather
  than rediscover it.
- Packs do not share partial names. Each pack ships its own header partial named after itself
  (`_service_header.jinja`, `_infra_header.jinja`, `_argocd_header.jinja`). The engine searches
  every pack's partials directory and takes the first match, so a shared name means one pack
  stamping another pack's files with the wrong pack name. The engine rejects two packs shipping
  the same partial path.
- A pack marks a generated file executable with the `executable` glob list in `pack.nix`,
  beside `ownership`. Anything matched lands `0755`. This already exists — see
  `golden-engine/README.md`.

---

## Rework log

Amended 2026-08-16, before execution.

1. **Every pack shipped `_header.jinja`.** Three packs in this plan each created a partial by
   that name, and `golden-base` already ships one. The engine's partial-collision guard throws
   on the second, and `overrides` would only silence the guard while leaving each pack's files
   stamped with whichever pack won the search. Renamed per pack, as `golden-github` already
   does.
2. **The executable bit is done.** This plan originally had to build it before shipping
   `next-version.sh`. It landed in `43a31a8`, so Tasks 2 and 4 use the `executable` field
   directly. Nothing here builds it.
3. **`helm-ecr.yaml` pins helm.** The findings note records that helm 4.2.4 emits a blank line
   before `---` where 4.2.3 does not, which breaks snapshot tests on a patch bump. A workflow
   using whatever helm the runner ships is a snapshot break waiting for a runner-image update.

---

### Task 1: Engine — pack defaults concatenate lists, and an int schema type

Without this, a pack cannot add a CI step or a just recipe to a file another pack owns, and the whole additive-pack idea collapses into one big pack.

**Files:**
- Modify: `golden-engine/lib/merge.nix`
- Modify: `golden-engine/lib/config.nix`
- Modify: `golden-base/tests/eval_units.nix`
- Modify: `golden-engine/VERSION`

**Interfaces:**
- Produces: `merge.mergeDefaults :: [attrs] -> attrs` — recursive merge where two lists at the same key concatenate in pack order. `config.mergeConfig` keeps replace-semantics for `repo.nix`, so a repo can still clear an inherited list with `[ ]`.
- `config.nix` gains schema type `int`.

- [ ] **Step 1: Write the failing tests**

Add to `golden-base/tests/eval_units.nix`:

```nix
  testPackDefaultListsConcatenateInPackOrder = {
    expr = (merge.mergePacks [
      (packA // { defaults = { ci.steps = [ "a" ]; }; })
      (packB // { defaults = { ci.steps = [ "b" ]; }; overrides = [ "shared.txt" ]; })
    ]).defaults.ci.steps;
    expected = [ "a" "b" ];
  };

  testRepoConfigReplacesAListRatherThanAppending = {
    expr = (config.mergeConfig
      (mergedFixture // { defaults = { ci.steps = [ "a" "b" ]; }; schema = mergedFixture.schema // { "ci.steps" = { type = "list"; }; }; })
      { name = "x"; ci.steps = [ ]; }).ci.steps;
    expected = [ ];
  };

  testIntTypeAccepted = {
    expr = (config.mergeConfig
      (mergedFixture // { schema = mergedFixture.schema // { "service.port" = { type = "int"; }; }; })
      { name = "x"; service.port = 8080; }).service.port;
    expected = 8080;
  };

  testIntTypeRejectsString = {
    expr = (builtins.tryEval (builtins.deepSeq (config.mergeConfig
      (mergedFixture // { schema = mergedFixture.schema // { "service.port" = { type = "int"; }; }; })
      { name = "x"; service.port = "8080"; }) null)).success;
    expected = false;
  };
```

- [ ] **Step 2: Run to verify they fail**

Run: `nix run ./golden-base#test-eval`
Expected: FAIL on all four — lists currently replace, and `int` throws `unknown type`.

- [ ] **Step 3: Implement mergeDefaults**

In `golden-engine/lib/merge.nix`, add above `mergePacks`:

```nix
  # Packs are additive, so two packs contributing to the same list both get
  # their entries. repo.nix is not additive — see config.nix, which uses
  # recursiveUpdate so a repo can clear an inherited list with [ ].
  mergeDefaults = lib.foldl'
    (a: b: lib.recursiveUpdateUntil
      (path: l: r: builtins.isList l && builtins.isList r)
      a b)
    { };
```

`recursiveUpdateUntil` stops recursing where the predicate holds and takes the right-hand value, which is not what is wanted — the concatenation has to be explicit. Use this instead:

```nix
  mergeDefaults = defaultsList:
    let
      merge2 = a: b:
        let
          keys = lib.unique (builtins.attrNames a ++ builtins.attrNames b);
          pick = k:
            if !(a ? ${k}) then b.${k}
            else if !(b ? ${k}) then a.${k}
            else if builtins.isList a.${k} && builtins.isList b.${k} then a.${k} ++ b.${k}
            else if builtins.isAttrs a.${k} && builtins.isAttrs b.${k} then merge2 a.${k} b.${k}
            else b.${k};
        in
        lib.genAttrs keys pick;
    in
    lib.foldl' merge2 { } defaultsList;
```

and change `mergePacks` to use it:

```nix
      defaults = mergeDefaults (map (p: p.defaults) packList);
```

Expose `mergeDefaults` in the returned attrset so the test can call it directly.

- [ ] **Step 4: Add the int type**

In `golden-engine/lib/config.nix`, inside `typeOk`, after the `bool` branch:

```nix
    else if entry.type == "int" then builtins.isInt value
```

- [ ] **Step 5: Run to verify they pass**

Run: `nix run ./golden-base#test-eval && nix flake check ./golden-base -L`
Expected: PASS, all units and all checks.

- [ ] **Step 6: Bump and commit**

Set `golden-engine/VERSION` to `0.2.0`.

```bash
git add golden-engine golden-base/tests
git commit -m "feat(FOM-51): concatenate pack default lists so packs can be additive

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: golden-service — the language registry and the Dockerfile

**Files:**
- Create: `golden-service/flake.nix`
- Create: `golden-service/pack.nix`
- Create: `golden-service/registry.nix`
- Create: `golden-service/partials/_service_header.jinja`
- Create: `golden-service/templates/Dockerfile.jinja`
- Create: `golden-service/tests/fixtures/go.nix`
- Create: `golden-service/tests/fixtures/rust.nix`
- Create: `golden-service/tests/fixtures/library.nix`
- Create: `golden-service/tests/expected/{go,rust,library}/`
- Create: `golden-service/VERSION`

**Interfaces:**
- Produces: `golden-service.pack`. Schema: `language` (enum `go`|`rust`, required), `service.container` (bool, default true), `service.port` (int, default 8080), `service.binary` (string, defaults to `name`).
- `registry.languages.<lang>` supplies `buildImage`, `runtimeImage`, `setupStep`, `buildCmd`, `testCmd`, `lintCmd`. Templates index it as `languages[language]`. The engine performs no lookup.

- [ ] **Step 1: Write the three expected trees**

`golden-service/tests/fixtures/go.nix`:

```nix
{
  name = "svc-go";
  codeowners = [ "@Fomiller" ];
  language = "go";
}
```

`golden-service/tests/expected/go/Dockerfile`:

```
# GENERATED FILE — managed by flake-hub (golden-service).
# Do not edit manually: `nix run .#generate` overwrites it.
# To change it, edit repo.nix, or the template in the pack that owns it.

FROM golang:1.23 AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /out/svc-go ./cmd/svc-go

FROM gcr.io/distroless/static-debian12
COPY --from=build /out/svc-go /svc-go
EXPOSE 8080
ENTRYPOINT ["/svc-go"]
```

`golden-service/tests/fixtures/rust.nix` is the same with `language = "rust"` and `name = "svc-rust"`. Its expected `Dockerfile`:

```
# GENERATED FILE — managed by flake-hub (golden-service).
# Do not edit manually: `nix run .#generate` overwrites it.
# To change it, edit repo.nix, or the template in the pack that owns it.

FROM rust:1.82 AS build
WORKDIR /src
COPY . .
RUN cargo build --release

FROM gcr.io/distroless/cc-debian12
COPY --from=build /src/target/release/svc-rust /svc-rust
EXPOSE 8080
ENTRYPOINT ["/svc-rust"]
```

`golden-service/tests/fixtures/library.nix` sets `service.container = false`, and `golden-service/tests/expected/library/` contains **no** `Dockerfile`. The check must assert absence, not just skip it.

- [ ] **Step 2: Write the flake with all three snapshot checks and run to verify they fail**

`golden-service/flake.nix` mirrors `golden-github/flake.nix` from plan 2, with one check per fixture plus:

```nix
        checks.library-has-no-dockerfile =
          let
            golden = golden-engine.lib.mkGolden {
              packs = [ golden-base.pack golden-github.pack self.pack ];
            } pkgs (import ./tests/fixtures/library.nix);
          in
          pkgs.runCommand "library-has-no-dockerfile" { } ''
            if [ -e ${golden.filesDrv}/Dockerfile ]; then
              echo "service.container = false still produced a Dockerfile" >&2
              exit 1
            fi
            touch $out
          '';
```

Run: `nix build ./golden-service#checks.aarch64-darwin.render-go -L`
Expected: FAIL — `pack.nix does not exist`.

- [ ] **Step 3: Write the registry**

`golden-service/registry.nix`:

```nix
{
  languages = {
    go = {
      buildImage = "golang:1.23";
      runtimeImage = "gcr.io/distroless/static-debian12";
      setupStep = ''
        - uses: actions/setup-go@v5
          with:
            go-version-file: go.mod
            cache: true'';
      buildCmd = "go build ./...";
      testCmd = "go test ./... -race -cover";
      lintCmd = "go vet ./...";
    };
    rust = {
      buildImage = "rust:1.82";
      runtimeImage = "gcr.io/distroless/cc-debian12";
      setupStep = "- uses: dtolnay/rust-toolchain@stable";
      buildCmd = "cargo build --release";
      testCmd = "cargo test --all-features";
      lintCmd = "cargo clippy -- -D warnings";
    };
  };
}
```

- [ ] **Step 4: Write the Dockerfile template**

`golden-service/templates/Dockerfile.jinja`:

```jinja
{% if service.container %}{% include "_service_header.jinja" %}

{% if language == "go" %}
FROM {{ languages[language].buildImage }} AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /out/{{ service.binary }} ./cmd/{{ service.binary }}

FROM {{ languages[language].runtimeImage }}
COPY --from=build /out/{{ service.binary }} /{{ service.binary }}
{% elif language == "rust" %}
FROM {{ languages[language].buildImage }} AS build
WORKDIR /src
COPY . .
RUN cargo build --release

FROM {{ languages[language].runtimeImage }}
COPY --from=build /src/target/release/{{ service.binary }} /{{ service.binary }}
{% endif %}
EXPOSE {{ service.port }}
ENTRYPOINT ["/{{ service.binary }}"]
{% endif %}
```

The whole body sits inside `{% if service.container %}`. When false the file renders empty and makejinja does not copy it out — which is also why `reconcile.py` deletes a managed path that is missing from `filesDrv`.

- [ ] **Step 5: Write pack.nix**

```nix
{
  name = "golden-service";
  templates = ./templates;
  partials = ./partials;
  defaults = {
    service = {
      container = true;
      port = 8080;
    };
  };
  registry = import ./registry.nix;
  ownership = {
    managed = [ "Dockerfile" ];
    scaffold = [ ];
    retired = [ ];
  };
  overrides = [ ];
  schema = {
    "language" = { type = "enum"; values = [ "go" "rust" ]; required = true; };
    "service.container" = { type = "bool"; };
    "service.port" = { type = "int"; };
    "service.binary" = { type = "string"; };
  };
}
```

`service.binary` has no default because it defaults to `name`, which packs cannot see. Resolve it in the template with `{{ service.binary | default(name, true) }}` and set the expected snapshots accordingly.

`golden-service/VERSION` contains `0.1.0`.

- [ ] **Step 6: Run all four checks**

Run: `nix flake check ./golden-service -L`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add golden-service
git commit -m "feat(FOM-51): add golden-service with the language registry and Dockerfile

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: golden-service contributes CI steps and just recipes

This is the first real use of the additive merge from Task 1.

**Files:**
- Modify: `golden-github/templates/.github/workflows/ci.yml.jinja` (create)
- Modify: `golden-github/pack.nix`
- Modify: `golden-service/pack.nix`
- Modify: `golden-service/tests/expected/{go,rust,library}/`
- Modify both `VERSION` files

**Interfaces:**
- `golden-github` owns `.github/workflows/ci.yml` and renders `ci.jobs` — a list of `{ name; steps; }` contributed through pack defaults.
- `golden-service` appends one job with the language's setup, build, test and lint steps, and appends `just` recipes.

- [ ] **Step 1: Write the expected ci.yml for the go fixture**

`golden-service/tests/expected/go/.github/workflows/ci.yml`:

```yaml
# GENERATED FILE — managed by flake-hub (golden-github).
# Do not edit manually: `nix run .#generate` overwrites it.
# To change it, edit repo.nix, or the template in the pack that owns it.

name: CI

on:
  pull_request:
  push:
    branches: [main]

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  build-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with:
          go-version-file: go.mod
          cache: true
      - name: build
        run: go build ./...
      - name: test
        run: go test ./... -race -cover
      - name: lint
        run: go vet ./...
```

The `library` fixture gets the same file — a library still builds, tests and lints. Only the Dockerfile and the image push are gated.

- [ ] **Step 2: Run the snapshots to verify they fail**

Run: `nix flake check ./golden-service -L`
Expected: FAIL — `.github/workflows/ci.yml` missing from the rendered tree.

- [ ] **Step 3: Write the ci.yml template in golden-github**

```jinja
{% include "_service_header.jinja" %}

name: CI

on:
  pull_request:
  push:
    branches: [main]

concurrency:
  group: {% raw %}${{ github.workflow }}-${{ github.ref }}{% endraw +%}
  cancel-in-progress: true

jobs:
{% for job in ci.jobs %}
  {{ job.name }}:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
{% for step in ci.extraSteps.pre %}
{{ step | indent(6, true) }}
{% endfor %}
{% for step in job.steps %}
{{ step | indent(6, true) }}
{% endfor %}
{% for step in ci.extraSteps.post %}
{{ step | indent(6, true) }}
{% endfor %}
{% endfor %}
```

Jinja's built-in `indent(width, first)` filter does the YAML alignment; no helper is needed. Add `ci.jobs = [ ]` to `golden-github`'s defaults, `"ci.jobs" = { type = "list"; }` to its schema, and `.github/workflows/ci.yml` to its `ownership.managed`.

If `ci.jobs` is empty the `jobs:` key renders with no children, which is invalid YAML. Guard it: wrap the whole file in `{% if ci.jobs %}` so a repo with no jobs gets no `ci.yml` at all, and add a `golden-github` fixture asserting that.

- [ ] **Step 4: Contribute the job from golden-service**

In `golden-service/pack.nix`, extend `defaults`:

```nix
  defaults = {
    service = { container = true; port = 8080; };
    ci.jobs = [
      {
        name = "build-test";
        steps = [
          "@@SETUP@@"
          "- name: build\n  run: @@BUILD@@"
          "- name: test\n  run: @@TEST@@"
          "- name: lint\n  run: @@LINT@@"
        ];
      }
    ];
  };
```

Placeholders will not work — pack defaults are static data and cannot read `language`. Resolve it in the template instead. Replace the above with a pack default that names the language table entry:

```nix
    ci.jobs = [ { name = "build-test"; stepsFrom = "language"; } ];
```

and in `ci.yml.jinja`, after the checkout step:

```jinja
{% if job.stepsFrom == "language" %}
{{ languages[language].setupStep | indent(6, true) }}
      - name: build
        run: {{ languages[language].buildCmd }}
      - name: test
        run: {{ languages[language].testCmd }}
      - name: lint
        run: {{ languages[language].lintCmd }}
{% endif %}
```

This keeps the lookup in the template, where the config is available, and keeps `golden-github` from knowing what a language is — `stepsFrom` is an opaque string to it.

- [ ] **Step 5: Add the just recipes**

In `golden-service/pack.nix` defaults, add:

```nix
    just.recipes = [
      "build:\n    just _lang-build"
      "test:\n    just _lang-test"
    ];
```

Update the expected `justfile` in each `golden-service` fixture to include them, appended after the base recipes in pack order.

- [ ] **Step 6: Run every check in the repo**

Run: `nix flake check ./golden-base -L && nix flake check ./golden-github -L && nix flake check ./golden-service -L`
Expected: PASS on all.

- [ ] **Step 7: Bump and commit**

Bump `golden-github/VERSION` to `0.3.0` and `golden-service/VERSION` to `0.2.0`.

```bash
git add golden-github golden-service
git commit -m "feat(FOM-51): let packs contribute CI jobs and just recipes

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: golden-infra

**Files:**
- Create: `golden-infra/{flake.nix,pack.nix,registry.nix,VERSION}`
- Create: `golden-infra/partials/_infra_header.jinja`
- Create: `golden-infra/templates/root.hcl.jinja`
- Create: `golden-infra/templates/.github/workflows/deploy-infra.yml.jinja`
- Create: `golden-infra/templates/infra/live/{dev,staging,prod}/README.md.jinja`
- Create: `golden-infra/tests/fixtures/{dev-only.nix,all-envs.nix}`
- Create: `golden-infra/tests/expected/{dev-only,all-envs}/`

**Interfaces:**
- Produces: `golden-infra.pack`. Schema: `infra.envs` (list, default `[ "dev" ]`), `infra.dopplerProject` (string, required), `infra.awsRegion` (string, default `us-east-1`), `infra.tailscale` (bool, default true), `infra.stateBucket` (string, required).
- Generates scaffolding and CI only. `infra/units/**` and `infra/stacks/**` are never generated and never appear in the plan.

- [ ] **Step 1: Read the reference**

Read `~/dev/personal/homelab/.github/workflows/deploy-infra.yaml` and `~/dev/personal/homelab/justfile`. The generated workflow must call the same reusable workflow with the same input names: `environment`, `infra-dir`, `doppler-project`, `tg-plan`, `use-oidc`, `use-tailscale`, `tailscale-tags`.

- [ ] **Step 2: Write the expected tree for the dev-only fixture**

`golden-infra/tests/fixtures/dev-only.nix`:

```nix
{
  name = "infra-dev";
  codeowners = [ "@Fomiller" ];
  infra = {
    dopplerProject = "infra-dev";
    stateBucket = "fomiller-tfstate-dev";
  };
}
```

`golden-infra/tests/expected/dev-only/.github/workflows/deploy-infra.yml`:

```yaml
# GENERATED FILE — managed by flake-hub (golden-infra).
# Do not edit manually: `nix run .#generate` overwrites it.
# To change it, edit repo.nix, or the template in the pack that owns it.

name: Terragrunt Deploy - Infra

on:
  pull_request:
    paths:
      - .github/workflows/deploy-infra.yml
      - infra/**
      - justfile
      - just/terraform.just
  push:
    branches: [main]
    paths:
      - .github/workflows/deploy-infra.yml
      - infra/**
      - justfile
      - just/terraform.just

jobs:
  plan-dev:
    name: Plan Infra (dev)
    if: ${{ github.event_name == 'pull_request' }}
    permissions:
      id-token: write
      contents: read
    uses: Fomiller/gh-actions/.github/workflows/terragrunt.yaml@main
    with:
      environment: dev
      infra-dir: infra/live/dev
      doppler-project: infra-dev
      tg-plan: true
      use-oidc: true
      use-tailscale: true
      tailscale-tags: tag:ci
    secrets: inherit

  apply-dev:
    name: Apply Infra (dev)
    if: ${{ github.event_name == 'push' }}
    permissions:
      id-token: write
      contents: read
    uses: Fomiller/gh-actions/.github/workflows/terragrunt.yaml@main
    with:
      environment: dev
      infra-dir: infra/live/dev
      doppler-project: infra-dev
      use-oidc: true
      use-tailscale: true
      tailscale-tags: tag:ci
    secrets: inherit
```

The `all-envs` fixture sets `infra.envs = [ "dev" "staging" "prod" ]` and expects three plan jobs and three apply jobs, plus three `infra/live/<env>/README.md` files.

- [ ] **Step 3: Run the snapshots to verify they fail**

Run: `nix build ./golden-infra#checks.aarch64-darwin.render-dev-only -L`
Expected: FAIL — pack does not exist.

- [ ] **Step 4: Write the workflow template**

`golden-infra/templates/.github/workflows/deploy-infra.yml.jinja`:

```jinja
{% include "_infra_header.jinja" %}

name: Terragrunt Deploy - Infra

on:
  pull_request:
    paths:
      - .github/workflows/deploy-infra.yml
      - infra/**
      - justfile
      - just/terraform.just
  push:
    branches: [main]
    paths:
      - .github/workflows/deploy-infra.yml
      - infra/**
      - justfile
      - just/terraform.just

jobs:
{% for env in infra.envs %}
  plan-{{ env }}:
    name: Plan Infra ({{ env }})
    if: {% raw %}${{ github.event_name == 'pull_request' }}{% endraw +%}
    permissions:
      id-token: write
      contents: read
    uses: Fomiller/gh-actions/.github/workflows/terragrunt.yaml@main
    with:
      environment: {{ env }}
      infra-dir: infra/live/{{ env }}
      doppler-project: {{ infra.dopplerProject }}
      tg-plan: true
      use-oidc: true
      use-tailscale: {{ infra.tailscale | lower }}
      tailscale-tags: tag:ci
    secrets: inherit

  apply-{{ env }}:
    name: Apply Infra ({{ env }})
    if: {% raw %}${{ github.event_name == 'push' }}{% endraw +%}
    permissions:
      id-token: write
      contents: read
    uses: Fomiller/gh-actions/.github/workflows/terragrunt.yaml@main
    with:
      environment: {{ env }}
      infra-dir: infra/live/{{ env }}
      doppler-project: {{ infra.dopplerProject }}
      use-oidc: true
      use-tailscale: {{ infra.tailscale | lower }}
      tailscale-tags: tag:ci
    secrets: inherit
{% endfor %}
```

- [ ] **Step 5: Write root.hcl and the env skeletons**

`golden-infra/templates/root.hcl.jinja` renders the remote state block and the provider generate block, parameterized on `infra.stateBucket` and `infra.awsRegion`. Model it on `~/dev/personal/homelab/infra/live/dev` — read the existing `root.hcl` or `terragrunt.hcl` there and match the state key convention exactly, since an existing repo adopting this must not lose its state.

`golden-infra/templates/infra/live/dev/README.md.jinja`:

```jinja
{% if "dev" in infra.envs %}
# infra/live/dev

Terragrunt units for the dev environment. These are yours: the generator only
creates this directory and the deploy workflow.
{% endif %}
```

One template per environment, each gated on membership. makejinja renders a static tree, so a variable number of directories has to come from a fixed set of gated templates. Three environments is the supported set; a fourth means a new template file.

An empty render is not copied out, which is exactly the gating mechanism. This is also why these are README files rather than `.gitkeep` — an empty `.gitkeep` would never be written.

- [ ] **Step 6: Write pack.nix**

```nix
{
  name = "golden-infra";
  templates = ./templates;
  partials = ./partials;
  defaults = {
    infra = {
      envs = [ "dev" ];
      awsRegion = "us-east-1";
      tailscale = true;
    };
    just.recipes = [
      "plan env=\"dev\":\n    just tg-plan {{env}}"
      "apply env=\"dev\":\n    just tg-apply {{env}}"
    ];
  };
  registry = { };
  ownership = {
    managed = [ "root.hcl" ".github/workflows/deploy-infra.yml" ];
    scaffold = [ "infra/live/**" ];
    retired = [ ];
  };
  overrides = [ ];
  schema = {
    "infra.envs" = { type = "list"; };
    "infra.dopplerProject" = { type = "string"; required = true; };
    "infra.awsRegion" = { type = "string"; };
    "infra.tailscale" = { type = "bool"; };
    "infra.stateBucket" = { type = "string"; required = true; };
  };
}
```

`just.recipes` entries contain `{{env}}`, which is just syntax and would be eaten by Jinja when the base justfile template renders them. Wrap those two recipe bodies so the rendered justfile keeps them literal — either escape as `{{ '{{env}}' }}` in the pack default, or have the base template emit recipe strings through a `| safe`-style raw path. Pick the escape; it keeps the base template unchanged. Add a snapshot assertion that the rendered justfile contains a literal `{{env}}`.

- [ ] **Step 7: Run the checks**

Run: `nix flake check ./golden-infra -L`
Expected: PASS on both fixtures plus the rendered-workflow actionlint check.

- [ ] **Step 8: Commit**

```bash
git add golden-infra
git commit -m "feat(FOM-51): add golden-infra terragrunt scaffolding and deploy workflow

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: helm-ecr.yaml in gh-actions

**Files:**
- Create: `~/dev/personal/gh-actions/.github/workflows/helm-ecr.yaml`

**Interfaces:**
- Inputs: `chart-path` (string, default `deploy/chart`), `repo-prefix` (string, required), `aws-region` (string, default `us-east-1`), `role-to-assume` (string, required), `version` (string, required). Publishes `oci://<account>.dkr.ecr.<region>.amazonaws.com/<repo-prefix>`.

`repo-prefix` is the prefix alone, never the full path. `helm push` appends the chart's own
name to whatever path it is given, so the ECR repo must be `<prefix>/<chart-name>` and the
push target must stop at the prefix. Getting this wrong does not error — it silently creates
a second repo.

- [ ] **Step 1: Read the existing ECR workflow**

Read `~/dev/personal/gh-actions/.github/workflows/ecr.yaml` and match its input names and OIDC pattern rather than inventing a second convention in the same repo.

- [ ] **Step 2: Write helm-ecr.yaml**

```yaml
# Packages a Helm chart and pushes it to ECR as an OCI artifact. Charts are
# versioned independently of the image; the caller passes the version.
name: helm-ecr

on:
  workflow_call:
    inputs:
      chart-path:
        required: false
        type: string
        default: deploy/chart
      repo-prefix:
        required: true
        type: string
      aws-region:
        required: false
        type: string
        default: us-east-1
      role-to-assume:
        required: true
        type: string
      version:
        required: true
        type: string
      push:
        description: Package only when false. Pull requests should not publish.
        required: false
        type: boolean
        default: true

jobs:
  publish:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
    steps:
      - uses: actions/checkout@v4

      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ inputs.role-to-assume }}
          aws-region: ${{ inputs.aws-region }}

      - uses: aws-actions/amazon-ecr-login@v2
        id: ecr

      # Pinned on purpose. helm 4.2.4 emits a blank line before `---` where
      # 4.2.3 does not, so an unpinned helm breaks consumers' snapshot tests
      # whenever the runner image moves.
      - uses: azure/setup-helm@v4
        with:
          version: v3.16.3

      - name: Lint the chart
        run: helm lint "${{ inputs.chart-path }}"

      - name: Package
        run: |
          helm package "${{ inputs.chart-path }}" \
            --version "${{ inputs.version }}" \
            --app-version "${{ inputs.version }}" \
            --destination dist

      - name: Push
        if: inputs.push
        env:
          REGISTRY: ${{ steps.ecr.outputs.registry }}
        run: |
          chart=$(ls dist/*.tgz)
          helm push "$chart" "oci://$REGISTRY/${{ inputs.repo-prefix }}"
```

- [ ] **Step 3: Verify actionlint**

Run: `nix run nixpkgs#actionlint -- .github/workflows/helm-ecr.yaml`
Expected: no output, exit 0.

- [ ] **Step 4: Commit and PR**

```bash
git add .github/workflows/helm-ecr.yaml
git commit -m "feat(FOM-51): add reusable helm chart publish to ECR

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
git push
gh pr create --title "feat(FOM-51): add reusable helm chart publish to ECR" --body "Packages a Helm chart and pushes it to ECR as an OCI artifact. Same OIDC pattern as ecr.yaml.

Pull requests package and lint but do not push."
```

---

### Task 6: golden-argocd

**Files:**
- Create: `golden-argocd/{flake.nix,pack.nix,VERSION}`
- Create: `golden-argocd/partials/_argocd_header.jinja`
- Create: `golden-argocd/templates/deploy/chart/Chart.yaml.jinja`
- Create: `golden-argocd/templates/deploy/chart/values.yaml.jinja`
- Create: `golden-argocd/templates/deploy/chart/templates/{deployment,service,_helpers.tpl}.jinja`
- Create: `golden-argocd/templates/.github/workflows/publish-chart.yml.jinja`
- Create: `golden-argocd/tests/fixtures/svc.nix`
- Create: `golden-argocd/tests/expected/svc/`

**Interfaces:**
- Produces: `golden-argocd.pack`. Schema: `deploy.ecrRepo` (string, required), `deploy.roleToAssume` (string, required), `deploy.replicas` (int, default 1), `deploy.chartVersion` (string, default `0.1.0`).
- Depends on `service.port` from `golden-service`. A repo taking `golden-argocd` without `golden-service` fails the required-key check on `service.port`, which is the correct behavior and gets a test.

- [ ] **Step 1: Write the failing snapshots**

The expected `deploy/chart/templates/deployment.yaml` contains live Helm syntax:

```yaml
{{- /* GENERATED FILE — managed by flake-hub (golden-argocd). */ -}}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "chart.fullname" . }}
spec:
  replicas: {{ .Values.replicas }}
  selector:
    matchLabels:
      {{- include "chart.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "chart.selectorLabels" . | nindent 8 }}
    spec:
      containers:
        - name: app
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          ports:
            - containerPort: 8080
```

Note the header is a Helm comment, not a `#` comment, so it does not survive into rendered Kubernetes objects.

- [ ] **Step 2: Run to verify it fails**

Run: `nix build ./golden-argocd#checks.aarch64-darwin.render-svc -L`
Expected: FAIL — pack does not exist.

- [ ] **Step 3: Write the chart templates**

Every file under `deploy/chart/templates/` is wrapped whole:

```jinja
{% raw %}{{- /* GENERATED FILE — managed by flake-hub (golden-argocd). */ -}}
apiVersion: apps/v1
kind: Deployment
...
{% endraw %}
```

with the two values that Jinja must substitute pulled out of the raw block. For `containerPort`, close and reopen the raw block:

```jinja
          ports:
            - containerPort: {% endraw %}{{ service.port }}{% raw %}
```

This is fiddly and worth one comment in the file explaining why: Helm and Jinja share `{{ }}`, so everything that Helm must see verbatim is inside `raw`, and only the handful of build-time values step outside it.

- [ ] **Step 4: Write the publish workflow template**

```jinja
{% include "_argocd_header.jinja" %}

name: Publish chart

on:
  pull_request:
    paths: [deploy/chart/**]
  push:
    branches: [main]
    paths: [deploy/chart/**]

jobs:
  chart:
    uses: Fomiller/gh-actions/.github/workflows/helm-ecr.yaml@main
    permissions:
      id-token: write
      contents: read
    with:
      chart-path: deploy/chart
      repo-prefix: {{ deploy.ecrRepo }}
      role-to-assume: {{ deploy.roleToAssume }}
      version: {{ deploy.chartVersion }}
      push: {% raw %}${{ github.event_name == 'push' }}{% endraw +%}
    secrets: inherit
```

- [ ] **Step 5: Write pack.nix and add the missing-dependency test**

`values.yaml` is `scaffold` — it is the service's own configuration surface. `Chart.yaml` and everything under `templates/` are `managed`.

Add a nix-unit case asserting that `mkGolden` with `[ base github argocd ]` and no `golden-service` throws on the missing `service.port`:

```nix
  testArgocdWithoutServicePackThrows = {
    expr = (builtins.tryEval (builtins.deepSeq
      (goldenWithout.mergedConfig) null)).success;
    expected = false;
  };
```

- [ ] **Step 6: Run the checks**

Run: `nix flake check ./golden-argocd -L`
Expected: PASS.

- [ ] **Step 7: Verify the chart actually renders as Helm**

Add a check that runs `helm template` over the generated chart, since a chart that passes a text snapshot can still be invalid Helm:

```nix
        checks.chart-renders = pkgs.runCommand "chart-renders"
          { nativeBuildInputs = [ pkgs.kubernetes-helm ]; }
          ''
            cp -r ${golden.filesDrv}/deploy/chart chart && chmod -R +w chart
            helm template test ./chart > /dev/null
            helm lint ./chart
            touch $out
          '';
```

Run: `nix build ./golden-argocd#checks.aarch64-darwin.chart-renders -L`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add golden-argocd
git commit -m "feat(FOM-51): add golden-argocd chart generation and publish workflow

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Wire the new packs into hub CI and prove them on a real service

**Files:**
- Modify: `flake-hub/.github/workflows/ci.yaml`
- Modify: `flake-hub/.github/workflows/release.yaml`
- Create: `Fomiller/flake-hub-example-service` (new repo)

- [ ] **Step 1: Extend the CI and release matrices**

Both `flake-dirs` lists become:

```
'["golden-base","golden-github","golden-service","golden-infra","golden-argocd","tests"]'
```

with `golden-engine` added to the release list only.

- [ ] **Step 2: Merge and confirm the tags**

Run: `gh release list -R Fomiller/flake-hub`
Expected: tags for all six flakes at their current VERSIONs.

- [ ] **Step 3: Bootstrap a real Go service**

```bash
mkdir -p ~/dev/personal/flake-hub-example-service && cd ~/dev/personal/flake-hub-example-service
git init -q
nix run 'github:Fomiller/flake-hub?dir=golden-base#init' -- \
  --name example-service --packs github,service,argocd
```

Fill in `repo.nix`:

```nix
{
  name = "example-service";
  codeowners = [ "@Fomiller" ];
  language = "go";
  deploy = {
    ecrRepo = "example-service";
    roleToAssume = "arn:aws:iam::<account>:role/github-actions-ecr";
  };
}
```

The account ID comes from the homelab AWS unit — read it rather than guessing.

```bash
nix run .#generate
mkdir -p cmd/example-service
cat > cmd/example-service/main.go <<'EOF'
package main

import (
	"log"
	"net/http"
	"os"
)

func main() {
	http.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	addr := ":" + cmp(os.Getenv("PORT"), "8080")
	log.Printf("listening on %s", addr)
	log.Fatal(http.ListenAndServe(addr, nil))
}

func cmp(v, fallback string) string {
	if v == "" {
		return fallback
	}
	return v
}
EOF
go mod init github.com/Fomiller/example-service
go mod tidy
```

- [ ] **Step 4: Verify locally before pushing**

Run:
```bash
go build ./... && go vet ./...
docker build -t example-service:test .
helm lint deploy/chart
nix run .#generate   # must report 0 change(s)
```
Expected: all four succeed, and the last prints `0 change(s)`.

- [ ] **Step 5: Push and confirm CI**

```bash
git add -A
git commit -m "feat: bootstrap example service from flake-hub

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
gh repo create Fomiller/flake-hub-example-service --public --source=. --remote=origin --push
gh run watch
```

Expected: `CI` and `Publish chart` both pass. `Publish chart` packages but does not push on the initial push to main — confirm the chart landed in ECR, and if the repository does not exist yet, that is the deferred ECR item from the spec: create it in homelab first.

- [ ] **Step 6: Commit any fixes back to the hub**

Anything that had to be hand-fixed in the example repo is a pack bug. Fix the template, bump the pack `VERSION`, regenerate, and confirm `nix run .#generate` reports `0 change(s)`.

---

## Deferred to later plans

- mdbook docs and the `mdbook.yaml` fix — plan 4.
- Renovate in the homelab cluster — plan 5.
- Argo CD `Application` manifests in homelab pointing at the published chart. Hand-written per the spec; the first one lands with the first real service.
- A fourth environment in `golden-infra` needs a fourth gated template. Fine until it isn't.
