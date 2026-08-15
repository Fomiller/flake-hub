# mdbook Docs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A published mdbook site for flake-hub — a page per flake written for consumers, plus the pack-authoring contract — where every config reference table is generated from the packs themselves and CI fails if it drifts.

**Architecture:** `docs/` is an mdbook, same shape as `aws-infra-shared-services` (`docs/book.toml`, `docs/src/SUMMARY.md`). Prose is hand-written. The per-pack config tables are not: a `docs` flake reads each pack's `schema` and `ownership` and renders Markdown, and a drift check runs the same generator and diffs. That is the same managed/drift model the packs use on consumer repos, applied to the hub's own docs.

**Tech Stack:** mdbook, Nix, GitHub Pages.

## Global Constraints

- Prerequisites: plans 1–3 complete and merged. All six flakes exist with populated `schema` fields.
- Reference layout: `~/dev/personal/aws-infra-shared-services/docs`. Match its `book.toml` conventions.
- `mdbook.yaml` in `gh-actions` is currently broken-ish: `actions/configure-pages@v2`, `actions/upload-pages-artifact@v1`, `actions/deploy-pages@v1` are all deprecated, and it installs whatever mdbook release is newest at run time. Fix it as part of this plan; do not work around it.
- No generated Markdown is hand-edited. If a table is wrong, the generator or the pack is wrong.
- Commit messages: conventional prefix, scope `FOM-51`, `Co-Authored-By: Claude` trailer.

---

### Task 1: Fix mdbook.yaml in gh-actions

**Files:**
- Modify: `~/dev/personal/gh-actions/.github/workflows/mdbook.yaml`

**Interfaces:**
- Inputs: `book-path` (string, default `docs`), `mdbook-version` (string, default `0.4.40`), `deploy` (boolean, default `true`). With `deploy: false` it builds only — that is the pull-request mode, which the current workflow has no way to express.

- [ ] **Step 1: Branch**

```bash
cd ~/dev/personal/gh-actions
git fetch origin
wt -C ~/dev/personal/gh-actions switch --create FOM-51-mdbook-fix \
  --base origin/$(wt -C ~/dev/personal/gh-actions config state default-branch)
```

- [ ] **Step 2: Rewrite the workflow**

```yaml
# Builds an mdbook and optionally publishes it to GitHub Pages.
#
# mdbook-version is pinned rather than resolved from the latest release at run
# time, so a docs build is reproducible and a new mdbook release cannot break
# an unrelated PR.
name: mdbook

on:
  workflow_call:
    inputs:
      book-path:
        required: false
        type: string
        default: docs
      mdbook-version:
        required: false
        type: string
        default: '0.4.40'
      deploy:
        description: Publish to Pages. False builds only, for pull requests.
        required: false
        type: boolean
        default: true

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pages: write
      id-token: write
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    steps:
      - uses: actions/checkout@v4

      - name: Install mdbook
        env:
          VERSION: ${{ inputs.mdbook-version }}
        run: |
          set -euo pipefail
          url="https://github.com/rust-lang/mdbook/releases/download/v${VERSION}/mdbook-v${VERSION}-x86_64-unknown-linux-gnu.tar.gz"
          mkdir -p "$RUNNER_TEMP/mdbook"
          curl -sSfL "$url" | tar -xz --directory="$RUNNER_TEMP/mdbook"
          echo "$RUNNER_TEMP/mdbook" >> "$GITHUB_PATH"

      - name: Build
        run: mdbook build
        working-directory: ${{ inputs.book-path }}

      - name: Setup Pages
        if: inputs.deploy
        uses: actions/configure-pages@v5

      - name: Upload artifact
        if: inputs.deploy
        uses: actions/upload-pages-artifact@v3
        with:
          path: ${{ inputs.book-path }}/book

      - name: Deploy
        id: deployment
        if: inputs.deploy
        uses: actions/deploy-pages@v4
```

Two changes worth knowing about beyond the version bumps: the tarball now unpacks into `RUNNER_TEMP` instead of the repo working directory, so it cannot end up in a build artifact, and `deploy: false` makes the same workflow usable on pull requests.

- [ ] **Step 3: Verify actionlint**

Run: `nix run nixpkgs#actionlint -- .github/workflows/mdbook.yaml`
Expected: no output, exit 0.

- [ ] **Step 4: Check the existing caller still works**

Run: `grep -rn "mdbook.yaml" ~/dev/personal --include='*.yaml' --include='*.yml'`
Any repo calling it with only `book-path` keeps working — the two new inputs have defaults. If a caller passes something else, fix that caller in the same PR.

- [ ] **Step 5: Commit and PR**

```bash
git add .github/workflows/mdbook.yaml
git commit -m "fix(FOM-51): update mdbook workflow to current Pages actions

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
git push -u origin FOM-51-mdbook-fix
gh pr create --title "fix(FOM-51): update mdbook workflow to current Pages actions" --body "configure-pages, upload-pages-artifact and deploy-pages were on v2/v1/v1, all deprecated. Bumped to v5/v3/v4.

mdbook was installed from whatever release was newest at run time. It is pinned now, with the version as an input, so a docs build is reproducible.

Adds a deploy input so pull requests can build the book without publishing it. Existing callers are unaffected — both new inputs have defaults."
```

---

### Task 2: The docs skeleton

**Files:**
- Create: `docs/book.toml`
- Create: `docs/src/SUMMARY.md`
- Create: `docs/src/introduction.md`
- Create: `docs/src/getting-started.md`
- Create: `docs/.gitignore`
- Modify: `justfile`

- [ ] **Step 1: Write book.toml**

```toml
[book]
authors = ["Forrest Miller"]
language = "en"
multilingual = false
src = "src"
title = "flake-hub"

[output.html]
default-theme = "ayu"
git-repository-url = "https://github.com/Fomiller/flake-hub"
edit-url-template = "https://github.com/Fomiller/flake-hub/edit/main/docs/{path}"

[output.html.fold]
enable = true
level = 1
```

`docs/.gitignore` contains `book/`. The `aws-infra-shared-services` book has its build output committed; do not repeat that here.

- [ ] **Step 2: Write SUMMARY.md**

```markdown
# Summary

[Introduction](introduction.md)

- [Getting started](getting-started.md)

# Flakes

- [golden-engine](flakes/golden-engine.md)
- [golden-base](flakes/golden-base.md)
- [golden-github](flakes/golden-github.md)
- [golden-service](flakes/golden-service.md)
- [golden-infra](flakes/golden-infra.md)
- [golden-argocd](flakes/golden-argocd.md)

# Concepts

- [Ownership classes](concepts/ownership.md)
- [Composing packs](concepts/composing.md)
- [Propagation](concepts/propagation.md)

# Authoring

- [Writing a pack](authoring/writing-a-pack.md)
- [Changing the engine](authoring/engine.md)

# Runbooks

- [Renovate GitHub App](runbooks/renovate-app.md)
```

- [ ] **Step 3: Write introduction.md and getting-started.md**

`introduction.md`: what the hub is in four sentences, the table of flakes with `?dir=` URLs, and the three-file consumer shape.

`getting-started.md`: the `init` invocation, what lands, how to change something (`repo.nix`, then `nix run .#generate`), and what the drift check does on a PR. Every command must be copy-pasteable and correct — run each one before writing it down.

- [ ] **Step 4: Add just recipes**

```make
docs:
    mdbook serve docs --open

docs-build:
    mdbook build docs
```

- [ ] **Step 5: Verify the book builds**

Run: `nix run nixpkgs#mdbook -- build docs`
Expected: `docs/book/index.html` exists, no warnings about missing SUMMARY entries.

- [ ] **Step 6: Commit**

```bash
git add docs justfile
git commit -m "docs(FOM-51): add the mdbook skeleton

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Generated config reference tables

**Files:**
- Create: `docs/flake.nix`
- Create: `docs/gen-reference.nix`
- Create: `docs/tests/gen_reference_test.py`
- Create: `docs/src/flakes/*.md` (the generated `<!-- BEGIN -->`/`<!-- END -->` regions)

**Interfaces:**
- Produces: `nix run ./docs#gen-reference`, which rewrites the region between `<!-- BEGIN GENERATED REFERENCE -->` and `<!-- END GENERATED REFERENCE -->` in each `docs/src/flakes/<pack>.md`. Prose outside the markers is never touched.
- Produces: `checks.reference-is-current`, which runs the generator into a temp copy and diffs.

- [ ] **Step 1: Write the failing test**

`docs/tests/gen_reference_test.py`:

```python
"""The reference tables are generated into a marked region so the prose around
them survives. These tests cover the region rewrite, which is the only part
with a way to go wrong silently."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))
from gen_reference import replace_region  # noqa: E402

BEGIN = "<!-- BEGIN GENERATED REFERENCE -->"
END = "<!-- END GENERATED REFERENCE -->"


def test_region_content_is_replaced():
    doc = f"intro\n\n{BEGIN}\nold\n{END}\n\noutro\n"
    out = replace_region(doc, "new")
    assert "old" not in out
    assert "new" in out


def test_prose_outside_the_region_survives():
    doc = f"intro\n\n{BEGIN}\nold\n{END}\n\noutro\n"
    out = replace_region(doc, "new")
    assert out.startswith("intro")
    assert out.rstrip().endswith("outro")


def test_missing_markers_is_an_error():
    try:
        replace_region("no markers here\n", "new")
    except ValueError as e:
        assert "marker" in str(e)
    else:
        raise AssertionError("expected ValueError")


def test_rewrite_is_idempotent():
    doc = f"{BEGIN}\nold\n{END}\n"
    once = replace_region(doc, "new")
    assert replace_region(once, "new") == once
```

- [ ] **Step 2: Run to verify it fails**

Run: `nix build ./docs#checks.aarch64-darwin.gen-reference-tests -L`
Expected: FAIL — no `gen_reference.py`.

- [ ] **Step 3: Write the Nix side**

`docs/gen-reference.nix` takes a pack and returns Markdown:

```nix
{ lib }:
pack:
let
  row = key:
    let e = pack.schema.${key}; in
    "| `${key}` | ${e.type}${lib.optionalString (e ? values) " (${lib.concatStringsSep ", " (map (v: "`${v}`") e.values)})"} | ${if e.required or false then "yes" else "no"} |";

  schemaTable =
    if pack.schema == { } then "This pack takes no configuration."
    else lib.concatStringsSep "\n" ([
      "| Key | Type | Required |"
      "|---|---|---|"
    ] ++ map row (builtins.attrNames pack.schema));

  fileList = cls:
    let paths = pack.ownership.${cls}; in
    if paths == [ ] then "_none_"
    else lib.concatStringsSep ", " (map (p: "`${p}`") paths);
in
''
  ## Configuration

  ${schemaTable}

  ## Files

  | Class | Paths |
  |---|---|
  | managed | ${fileList "managed"} |
  | scaffold | ${fileList "scaffold"} |
  | retired | ${fileList "retired"} |
''
```

- [ ] **Step 4: Write the Python side**

`docs/gen_reference.py` reads a JSON map of pack name to rendered Markdown (produced by the Nix side and passed as a file), then rewrites each page's region:

```python
#!/usr/bin/env python3
"""Rewrite the generated reference region in each flake page.

Nix renders the tables; this only splices them in, so the prose around the
markers stays hand-written.
"""

import argparse
import json
from pathlib import Path

BEGIN = "<!-- BEGIN GENERATED REFERENCE -->"
END = "<!-- END GENERATED REFERENCE -->"


def replace_region(doc: str, body: str) -> str:
    if BEGIN not in doc or END not in doc:
        raise ValueError(f"page is missing the {BEGIN} / {END} marker pair")
    head, rest = doc.split(BEGIN, 1)
    _, tail = rest.split(END, 1)
    return f"{head}{BEGIN}\n{body.strip()}\n{END}{tail}"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--tables", required=True, type=Path)
    ap.add_argument("--pages-dir", required=True, type=Path)
    args = ap.parse_args()

    tables = json.loads(args.tables.read_text())
    for pack, body in tables.items():
        page = args.pages_dir / f"{pack}.md"
        if not page.exists():
            raise SystemExit(f"gen-reference: no page for {pack} at {page}")
        page.write_text(replace_region(page.read_text(), body))
        print(f"gen-reference: updated {page}")


if __name__ == "__main__":
    main()
```

- [ ] **Step 5: Wire the app and the drift check**

`docs/flake.nix` imports every pack, builds the JSON table map, and exposes:

- `apps.gen-reference` — runs `gen_reference.py` against `docs/src/flakes/`.
- `checks.reference-is-current` — copies the repo into the sandbox, runs the same generator, and `diff -r`s `docs/src/flakes` against the copy. Fails with the instruction `run 'nix run ./docs#gen-reference' and commit the result`.
- `checks.gen-reference-tests` — pytest over `docs/tests/`.

- [ ] **Step 6: Run everything**

Run: `nix flake check ./docs -L && nix run ./docs#gen-reference && git diff --exit-code docs/src/flakes`
Expected: checks pass, generator reports six updated pages, and the diff is empty on the second run.

- [ ] **Step 7: Commit**

```bash
git add docs
git commit -m "docs(FOM-51): generate the per-pack config reference from the packs

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: The flake pages

**Files:**
- Create: `docs/src/flakes/{golden-engine,golden-base,golden-github,golden-service,golden-infra,golden-argocd}.md`

Each page: what the flake is for in two or three sentences, the `?dir=` input line, the marker pair for the generated tables, and anything a consumer would otherwise have to read the templates to learn.

- [ ] **Step 1: Write golden-engine.md**

The engine page is different from the others — it has no schema and no files. Cover instead: `mkGolden`'s signature, the `{ filesDrv; plan; generateApp; mergedConfig; }` outputs, that it has no flake inputs and takes `pkgs` from the caller, and that eval guards fire before any build.

- [ ] **Step 2: Write the five pack pages**

For each: the purpose, the input line, the marker pair, and the pack-specific gotchas. The ones that must be written down because they are not obvious from the tables:

- `golden-base` — `just.recipes` entries are appended in pack order; `README.md` is scaffold, so it is yours after the first generate.
- `golden-github` — `renovate.json` and `CODEOWNERS` carry no ownership header, because neither format has a comment syntax that is safe there.
- `golden-service` — `service.container = false` removes the Dockerfile entirely; the language table is in the pack's registry, and adding a language is a pack change, not a repo change.
- `golden-infra` — units and stacks are never generated; only three environments are supported and a fourth needs a template.
- `golden-argocd` — `values.yaml` is scaffold; the chart requires `golden-service` for `service.port`.

- [ ] **Step 3: Regenerate and verify**

Run: `nix run ./docs#gen-reference && nix run nixpkgs#mdbook -- build docs`
Expected: six pages updated, book builds with no broken-link warnings.

- [ ] **Step 4: Commit**

```bash
git add docs/src/flakes
git commit -m "docs(FOM-51): add a page per flake

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Concept and authoring pages

**Files:**
- Create: `docs/src/concepts/{ownership,composing,propagation}.md`
- Create: `docs/src/authoring/{writing-a-pack,engine}.md`
- Create: `docs/src/runbooks/renovate-app.md`

- [ ] **Step 1: ownership.md**

The four classes as a table, then the part that actually causes confusion: a managed path missing from the rendered tree is **deleted**, which is how a pack gates a file off, and `unmanaged` is the only way to keep a path the generator would otherwise own. Include what to do when you want to hand-edit a generated file: you don't — you change `repo.nix`, or the template, or you add the path to `unmanaged` and accept it is no longer enforced.

- [ ] **Step 2: composing.md**

Pack order matters. Later packs win on collision, but only if they declare the path in `overrides`, otherwise it is an error. Pack default lists concatenate in pack order; `repo.nix` replaces them. Include the three standard combinations and the error message a collision produces, verbatim.

- [ ] **Step 3: propagation.md**

The tag-to-PR flow as a diagram, the tag naming rule, the `VERSION` bump check, and why generation runs in the consumer's workflow rather than in Renovate. State plainly that `commit-back` pushes with `GITHUB_TOKEN` and that this is the loop prevention.

- [ ] **Step 4: writing-a-pack.md**

The full `pack.nix` contract field by field, the `_*` partial naming rule, the `{% raw %}` requirement for GitHub `${{ }}` and Helm `{{ }}`, the `{% endraw +%}` whitespace gotcha, and the snapshot-test pattern (`tests/fixtures/<case>.nix` plus `tests/expected/<case>/`). End with a checklist for adding a pack: directory, `flake.nix`, `pack.nix`, `VERSION`, a fixture, an expected tree, an entry in the hub's CI and release matrices, and a docs page.

- [ ] **Step 5: engine.md**

For someone changing the engine. The two rules that keep it team-agnostic. The `filesDrv` / `plan` split. That every guard needs a binding a real output forces plus a nix-unit case that goes red when the guard is removed — with the concrete example of removing `planChecksum` from `filesDrv` and watching nothing fail.

- [ ] **Step 6: renovate-app.md**

The manual runbook, written so it can be followed without this context: create a GitHub App on the `Fomiller` account, the exact permissions it needs (Contents: read/write, Pull requests: read/write, Metadata: read, Workflows: read/write), install it on the repos, download the private key, put the App ID and key into Doppler under the names the External Secret expects. This is a prerequisite for plan 5 — say so at the top of the page.

- [ ] **Step 7: Build and commit**

Run: `nix run nixpkgs#mdbook -- build docs`
Expected: no warnings.

```bash
git add docs/src
git commit -m "docs(FOM-51): add concept, authoring and runbook pages

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Publish

**Files:**
- Modify: `flake-hub/.github/workflows/ci.yaml`
- Create: `flake-hub/.github/workflows/docs.yaml`

- [ ] **Step 1: Add the docs workflow**

```yaml
name: Docs

on:
  push:
    branches: [main]
    paths: ['docs/**', '.github/workflows/docs.yaml']

concurrency:
  group: pages
  cancel-in-progress: false

jobs:
  docs:
    uses: Fomiller/gh-actions/.github/workflows/mdbook.yaml@main
    permissions:
      contents: read
      pages: write
      id-token: write
    with:
      book-path: docs
```

- [ ] **Step 2: Add the PR build and the reference drift check to ci.yaml**

Add a `docs` entry to the `flake-dirs` matrix so `checks.reference-is-current` runs on every PR, and a build-only docs job:

```yaml
  docs-build:
    uses: Fomiller/gh-actions/.github/workflows/mdbook.yaml@main
    with:
      book-path: docs
      deploy: false
```

- [ ] **Step 3: Enable Pages**

Run: `gh api -X POST repos/Fomiller/flake-hub/pages -f build_type=workflow` (or enable it in Settings → Pages → Source: GitHub Actions if the API call reports it is already configured).

- [ ] **Step 4: Merge and verify**

Expected: the `Docs` run succeeds and `https://fomiller.github.io/flake-hub/` serves the book. Fix any broken relative links the deployed site reveals — mdbook does not catch every one locally.

- [ ] **Step 5: Link it from the READMEs**

Add the docs URL to the top of `README.md`, and to each flake's `README.md`, pointing at that flake's page.

- [ ] **Step 6: Commit**

```bash
git add .github README.md golden-*/README.md
git commit -m "ci(FOM-51): publish the docs to Pages and check the reference for drift

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Deferred

- Renovate in the homelab cluster — plan 5. `runbooks/renovate-app.md` is its prerequisite and lands here.
- A custom mdbook theme. Default `ayu` is fine.
