# golden-github + CI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The propagation loop, working end to end without Renovate: a tagged pack release, a consumer repo that regenerates from its pin, and CI that fails on drift.

**Architecture:** `golden-github` is the second pack — GitHub-interpreted files only (`.github/workflows/*`, `CODEOWNERS`, `renovate.json`). Four reusable workflows go into `Fomiller/gh-actions`: one consumer-side (`nix-generate.yaml`), three hub-side (`nix-flake-check.yaml`, `release-flake.yaml`, and the `VERSION` bump check inside it). `Fomiller/flake-hub-example` is a real repo consuming `base + github`, and it is where the loop is proven by hand before Renovate ever touches it.

**Tech Stack:** Nix flakes, makejinja, GitHub Actions, actionlint, `DeterminateSystems/nix-installer-action`, attic.

## Global Constraints

- Prerequisite: plan `2026-08-15-golden-engine-and-base.md` is complete and merged.
- Repos: `/Users/forrest/dev/personal/flake-hub`, `/Users/forrest/dev/personal/gh-actions`, and a new `Fomiller/flake-hub-example`.
- `gh-actions` default branch: resolve it, do not assume. `wt -C ~/dev/personal/gh-actions config state default-branch`.
- Every workflow added to `gh-actions` is a `workflow_call` reusable workflow. None of them run on their own triggers.
- Consumer generation workflows push with `GITHUB_TOKEN` only. A `GITHUB_TOKEN` push does not retrigger workflows, and that is the loop prevention. Never swap in a PAT to "make CI rerun".
- All workflow YAML must pass `actionlint`.
- Action pins: `actions/checkout@v4`, `DeterminateSystems/nix-installer-action@main`, `peter-evans/create-pull-request` is **not** used — the generate workflow commits directly to the PR branch.
- Tag format is `<dir>-<semver>`, e.g. `golden-github-0.1.0`. Nothing else parses.
- Commit messages: conventional prefix, scope `FOM-51`, `Co-Authored-By: Claude` trailer. No AI attribution in PR bodies.

---

### Task 1: golden-github pack with CODEOWNERS

**Files:**
- Create: `golden-github/flake.nix`
- Create: `golden-github/pack.nix`
- Create: `golden-github/templates/CODEOWNERS.jinja`
- Create: `golden-github/partials/_header.jinja`
- Create: `golden-github/tests/eval_units.nix`
- Create: `golden-github/tests/fixtures/repo.nix`
- Create: `golden-github/tests/expected/default/CODEOWNERS`
- Create: `golden-github/VERSION`

**Interfaces:**
- Consumes: `golden-engine.lib.mkGolden`, `golden-base.pack` from plan 1.
- Produces: `golden-github.pack` with schema keys `codeowners` (list, required), `ci.security` (bool), `ci.release` (bool), `ci.extraSteps.pre` (list), `ci.extraSteps.post` (list).

- [ ] **Step 1: Write the failing snapshot check**

`golden-github/tests/fixtures/repo.nix`:

```nix
{
  name = "snapshot-repo";
  codeowners = [ "@Fomiller" ];
}
```

`golden-github/tests/expected/default/CODEOWNERS`:

```
# GENERATED FILE — managed by flake-hub (golden-github).
# Do not edit manually: `nix run .#generate` overwrites it.
# To change it, edit repo.nix, or the template in the pack that owns it.

* @Fomiller
```

`golden-github/flake.nix`:

```nix
{
  description = "golden-github: the files GitHub itself interprets";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    golden-engine.url = "path:../golden-engine";
    golden-base.url = "path:../golden-base";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, golden-engine, golden-base, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        golden = golden-engine.lib.mkGolden {
          packs = [ golden-base.pack self.pack ];
        } pkgs (import ./tests/fixtures/repo.nix);
      in
      {
        # The snapshot covers only this pack's own paths. golden-base's files
        # are already covered by golden-base's snapshot; asserting them here
        # would mean two places to update for one change.
        checks.render-snapshot = pkgs.runCommand "github-render-snapshot" { } ''
          for f in $(cd ${./tests/expected/default} && find . -type f | sed 's|^\./||'); do
            diff -u "${./tests/expected/default}/$f" "${golden.filesDrv}/$f"
          done
          touch $out
        '';

        apps.test-eval = {
          type = "app";
          program = toString (pkgs.writeShellScript "test-eval" ''
            exec ${pkgs.nix-unit}/bin/nix-unit --eval-store auto ${./tests/eval_units.nix}
          '');
        };
      })
    // {
      pack = import ./pack.nix;
    };
}
```

`golden-github/tests/eval_units.nix` starts as `{ testPlaceholder = { expr = 1; expected = 1; }; }`.

- [ ] **Step 2: Run the check to verify it fails**

Run: `nix build ./golden-github#checks.aarch64-darwin.render-snapshot -L`
Expected: FAIL — `pack.nix does not exist`.

- [ ] **Step 3: Write the pack and template**

`golden-github/partials/_header.jinja` is identical to golden-base's. It is duplicated on purpose: a pack that reached into another pack's partials would make the two impossible to release independently.

`golden-github/templates/CODEOWNERS.jinja`:

```jinja
{% include "_header.jinja" %}

*{% for owner in codeowners %} {{ owner }}{% endfor %}
```

`golden-github/pack.nix`:

```nix
{
  name = "golden-github";
  templates = ./templates;
  partials = ./partials;
  defaults = {
    ci = {
      security = true;
      release = false;
      extraSteps = { pre = [ ]; post = [ ]; };
    };
  };
  registry = { };
  ownership = {
    managed = [ "CODEOWNERS" ];
    scaffold = [ ];
    retired = [ ];
  };
  overrides = [ ];
  schema = {
    "codeowners" = { type = "list"; required = true; };
    "ci.security" = { type = "bool"; };
    "ci.release" = { type = "bool"; };
    "ci.extraSteps.pre" = { type = "list"; };
    "ci.extraSteps.post" = { type = "list"; };
  };
}
```

`golden-github/VERSION` contains `0.1.0`.

- [ ] **Step 4: Run the check to verify it passes**

Run: `nix build ./golden-github#checks.aarch64-darwin.render-snapshot -L`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add golden-github
git commit -m "feat(FOM-51): add golden-github with CODEOWNERS

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: The renovate preset and the consumer renovate.json

The regex that bumps pack pins is written once, in the hub, as a Renovate preset. Consumers extend it. The cluster Renovate config in plan 5 extends the same file, so there is one copy, not two.

**Files:**
- Create: `renovate/default.json`
- Create: `renovate/README.md`
- Create: `golden-github/templates/renovate.json.jinja`
- Modify: `golden-github/pack.nix`
- Create: `golden-github/tests/expected/default/renovate.json`
- Create: `tests/renovate_preset_test.py`
- Create: `tests/flake.nix`

**Interfaces:**
- Produces: preset `github>Fomiller/flake-hub//renovate/default`, matching pack pins of the form `<pack>.url = "github:Fomiller/flake-hub?dir=<pack>&ref=refs/tags/<pack>-<semver>"`.

- [ ] **Step 1: Write the failing preset test**

`tests/renovate_preset_test.py`:

```python
"""The customManagers regex is the one piece of Renovate config that is easy
to get subtly wrong: a loose version group bumps golden-github pins to
golden-infra tags. These tests run the regex the same way Renovate does."""

import json
import re
from pathlib import Path

PRESET = json.loads((Path(__file__).parent.parent / "renovate" / "default.json").read_text())

FLAKE = """{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    golden-engine.url = "github:Fomiller/flake-hub?dir=golden-engine&ref=refs/tags/golden-engine-0.1.0";
    golden-github.url = "github:Fomiller/flake-hub?dir=golden-github&ref=refs/tags/golden-github-1.2.3";
  };
}
"""


def matches():
    manager = PRESET["customManagers"][0]
    out = []
    for pattern in manager["matchStrings"]:
        for m in re.finditer(pattern, FLAKE, re.MULTILINE):
            out.append(m.groupdict())
    return out


def test_every_pack_pin_is_matched():
    assert len(matches()) == 2


def test_current_value_is_the_full_prefixed_tag():
    tags = sorted(m["currentValue"] for m in matches())
    assert tags == ["golden-engine-0.1.0", "golden-github-1.2.3"]


def test_datasource_is_github_tags_on_the_hub():
    manager = PRESET["customManagers"][0]
    assert manager["datasourceTemplate"] == "github-tags"
    assert manager["depNameTemplate"] == "Fomiller/flake-hub"


def test_extract_version_is_anchored_to_the_pack_directory():
    """Without the per-pack anchor, a golden-infra tag is a candidate upgrade
    for a golden-github pin, because both are tags on the same repo."""
    manager = PRESET["customManagers"][0]
    for m in matches():
        pack = m["depName"] if "depName" in m else m["packageName"]
        assert manager["extractVersionTemplate"].replace("{{{depName}}}", pack).startswith(f"^{pack}-")


def test_nix_manager_is_disabled():
    """flake.lock is regenerated by the consumer's own workflow. Letting
    Renovate's nix manager also touch it produces two conflicting bumps."""
    assert PRESET["nix"]["enabled"] is False
```

- [ ] **Step 2: Add a test flake and run it to verify it fails**

`tests/flake.nix`:

```nix
{
  description = "Repo-level tests that belong to no single pack";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let pkgs = nixpkgs.legacyPackages.${system}; in {
        checks.renovate-preset = pkgs.runCommand "renovate-preset-tests"
          { nativeBuildInputs = [ pkgs.python3Packages.pytest ]; }
          ''
            cp -r ${../.} hub && chmod -R +w hub && cd hub
            pytest tests/renovate_preset_test.py -q
            touch $out
          '';
      });
}
```

Run: `nix build ./tests#checks.aarch64-darwin.renovate-preset -L`
Expected: FAIL — `renovate/default.json` not found.

- [ ] **Step 3: Write the preset**

`renovate/default.json`:

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "description": "Bumps flake-hub pack pins. Each pack is tagged <pack>-<semver> on one repo, so the version match must be anchored per pack.",
  "nix": {
    "enabled": false
  },
  "customManagers": [
    {
      "customType": "regex",
      "managerFilePatterns": ["/(^|/)flake\\.nix$/"],
      "matchStrings": [
        "(?<depName>golden-[a-z0-9-]+)\\.url\\s*=\\s*\"github:Fomiller/flake-hub\\?dir=\\k<depName>&ref=refs/tags/(?<currentValue>\\k<depName>-[0-9]+\\.[0-9]+\\.[0-9]+)\""
      ],
      "datasourceTemplate": "github-tags",
      "depNameTemplate": "Fomiller/flake-hub",
      "packageNameTemplate": "Fomiller/flake-hub",
      "extractVersionTemplate": "^{{{depName}}}-(?<version>.+)$",
      "versioningTemplate": "semver"
    }
  ]
}
```

`renovate/README.md` explains the anchoring: every pack is tagged on the same repo, so `github-tags` returns every pack's tags for every pin. `extractVersionTemplate` filters them down to the one pack, and the `\k<depName>` backreference in `matchStrings` makes sure the directory and the tag prefix agree before a pin is even considered.

- [ ] **Step 4: Run the test to verify it passes**

Run: `nix build ./tests#checks.aarch64-darwin.renovate-preset -L`
Expected: PASS, 5 tests.

- [ ] **Step 5: Add the consumer renovate.json template**

`golden-github/templates/renovate.json.jinja`:

```jinja
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": [
    "config:recommended",
    "github>Fomiller/flake-hub//renovate/default"
  ],
  "labels": ["dependencies"],
  "prConcurrentLimit": 3
}
```

JSON has no comment syntax, so this file carries no ownership header. Add a note in `golden-github/README.md` listing the header-less generated files and why.

Add `"renovate.json"` to `ownership.managed` in `golden-github/pack.nix`, and add the expected file at `golden-github/tests/expected/default/renovate.json`.

- [ ] **Step 6: Run the snapshot**

Run: `nix build ./golden-github#checks.aarch64-darwin.render-snapshot -L`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add renovate tests golden-github
git commit -m "feat(FOM-51): add the renovate preset that bumps pack pins

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: nix-generate.yaml in gh-actions

**Files:**
- Create: `~/dev/personal/gh-actions/.github/workflows/nix-generate.yaml`
- Create: `~/dev/personal/gh-actions/.github/workflows/actionlint.yaml`

**Interfaces:**
- Produces: reusable workflow with inputs `commit-back` (boolean, default `false`), `attic-cache` (string, default `""`), `working-directory` (string, default `.`). Secrets: `ATTIC_TOKEN` (optional).

- [ ] **Step 1: Create the branch**

```bash
cd ~/dev/personal/gh-actions
git fetch origin
wt -C ~/dev/personal/gh-actions switch --create FOM-51-nix-generate \
  --base origin/$(wt -C ~/dev/personal/gh-actions config state default-branch)
```

Work in the worktree path `wt` prints from here on.

- [ ] **Step 2: Add actionlint so the new workflows are checked**

`.github/workflows/actionlint.yaml`:

```yaml
name: actionlint

on:
  pull_request:
    paths: ['.github/workflows/**']

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: rhysd/actionlint@main
```

- [ ] **Step 3: Write nix-generate.yaml**

```yaml
# Regenerates a consuming repo's golden files and either fails on drift or
# commits the result back to the PR branch.
#
# commit-back pushes with GITHUB_TOKEN. That is deliberate: a GITHUB_TOKEN
# push does not trigger workflows, which is what stops a Renovate PR from
# regenerating itself forever. Do not replace it with a PAT.
name: nix-generate

on:
  workflow_call:
    inputs:
      commit-back:
        description: Commit regenerated files to the PR branch instead of failing on drift
        required: false
        type: boolean
        default: false
      attic-cache:
        description: attic cache name to pull from, e.g. homelab. Empty disables the cache
        required: false
        type: string
        default: ''
      attic-endpoint:
        required: false
        type: string
        default: ''
      working-directory:
        required: false
        type: string
        default: '.'
    secrets:
      ATTIC_TOKEN:
        required: false

jobs:
  generate:
    runs-on: ubuntu-latest
    permissions:
      contents: write
    defaults:
      run:
        working-directory: ${{ inputs.working-directory }}
    steps:
      - uses: actions/checkout@v4
        with:
          ref: ${{ github.head_ref }}

      - uses: DeterminateSystems/nix-installer-action@main

      - name: Configure attic
        if: inputs.attic-cache != ''
        env:
          ATTIC_TOKEN: ${{ secrets.ATTIC_TOKEN }}
        run: |
          nix profile install nixpkgs#attic-client
          attic login homelab "${{ inputs.attic-endpoint }}" "$ATTIC_TOKEN"
          attic use "${{ inputs.attic-cache }}"

      - name: Generate
        run: nix run .#generate

      - name: Check for drift
        id: drift
        run: |
          if git diff --quiet; then
            echo "changed=false" >> "$GITHUB_OUTPUT"
          else
            echo "changed=true" >> "$GITHUB_OUTPUT"
            git --no-pager diff --stat
          fi

      - name: Fail on drift
        if: steps.drift.outputs.changed == 'true' && !inputs.commit-back
        run: |
          echo "::error::Generated files are out of sync. Run 'nix run .#generate' and commit the result."
          git --no-pager diff
          exit 1

      - name: Commit regenerated files
        if: steps.drift.outputs.changed == 'true' && inputs.commit-back
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
          git add -A
          git commit -m "chore: regenerate golden files"
          git push
```

- [ ] **Step 4: Verify actionlint passes locally**

Run: `nix run nixpkgs#actionlint -- .github/workflows/nix-generate.yaml`
Expected: no output, exit 0.

- [ ] **Step 5: Commit and open the PR**

```bash
git add .github/workflows/nix-generate.yaml .github/workflows/actionlint.yaml
git commit -m "feat(FOM-51): add reusable nix-generate workflow

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
git push -u origin FOM-51-nix-generate
gh pr create --title "feat(FOM-51): add reusable nix-generate workflow" --body "$(cat <<'EOF'
Adds a reusable workflow that runs `nix run .#generate` in a consuming repo and either fails on drift or commits the result back to the PR branch.

`commit-back` pushes with `GITHUB_TOKEN` on purpose. That kind of push does not trigger workflows, which is what stops a Renovate PR from regenerating itself in a loop.

Also adds actionlint on workflow changes, since there was no linting here before.
EOF
)"
```

---

### Task 4: nix-flake-check.yaml and release-flake.yaml in gh-actions

**Files:**
- Create: `~/dev/personal/gh-actions/.github/workflows/nix-flake-check.yaml`
- Create: `~/dev/personal/gh-actions/.github/workflows/release-flake.yaml`

**Interfaces:**
- `nix-flake-check.yaml` inputs: `flake-dirs` (string, JSON array of directories). Runs `nix flake check` and any `test-eval` app in each.
- `release-flake.yaml` inputs: `flake-dirs` (string, JSON array), `versions-file` (string, default `golden-base/pack-versions.nix`). Cuts `<dir>-<version>` tags and rewrites the versions file.

- [ ] **Step 1: Write nix-flake-check.yaml**

```yaml
name: nix-flake-check

on:
  workflow_call:
    inputs:
      flake-dirs:
        description: JSON array of flake directories to check, e.g. '["golden-base","golden-github"]'
        required: true
        type: string

jobs:
  check:
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        dir: ${{ fromJSON(inputs.flake-dirs) }}
    steps:
      - uses: actions/checkout@v4
      - uses: DeterminateSystems/nix-installer-action@main

      - name: nix flake check
        run: nix flake check "./${{ matrix.dir }}" -L

      - name: Eval unit tests
        run: |
          if nix eval "./${{ matrix.dir }}#apps.$(nix eval --raw --impure --expr builtins.currentSystem).test-eval" \
               --apply 'x: "yes"' >/dev/null 2>&1; then
            nix run "./${{ matrix.dir }}#test-eval"
          else
            echo "no test-eval app in ${{ matrix.dir }}, skipping"
          fi
```

- [ ] **Step 2: Write release-flake.yaml**

```yaml
# Cuts a tag per flake directory whose VERSION changed, and regenerates the
# pack-versions file that golden-base's init app reads.
#
# Tag format is <dir>-<semver> and nothing else parses it: the renovate
# preset's extractVersionTemplate is anchored to that exact prefix.
name: release-flake

on:
  workflow_call:
    inputs:
      flake-dirs:
        required: true
        type: string
      versions-file:
        required: false
        type: string
        default: golden-base/pack-versions.nix

jobs:
  release:
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Tag each flake whose VERSION is not yet released
        id: tag
        env:
          DIRS: ${{ inputs.flake-dirs }}
        run: |
          set -euo pipefail
          released=()
          for dir in $(echo "$DIRS" | jq -r '.[]'); do
            [ -f "$dir/VERSION" ] || { echo "$dir has no VERSION file"; exit 1; }
            version=$(tr -d '[:space:]' < "$dir/VERSION")
            tag="$dir-$version"
            if git rev-parse "$tag" >/dev/null 2>&1; then
              echo "$tag already exists, skipping"
              continue
            fi
            git tag "$tag"
            released+=("$tag")
          done
          if [ ${#released[@]} -gt 0 ]; then
            git push origin "${released[@]}"
          fi
          printf 'released=%s\n' "${released[*]:-}" >> "$GITHUB_OUTPUT"

      - name: Create releases
        if: steps.tag.outputs.released != ''
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          for tag in ${{ steps.tag.outputs.released }}; do
            gh release create "$tag" --title "$tag" --generate-notes
          done

      - name: Regenerate the pack versions file
        if: steps.tag.outputs.released != ''
        env:
          DIRS: ${{ inputs.flake-dirs }}
          VERSIONS_FILE: ${{ inputs.versions-file }}
        run: |
          set -euo pipefail
          {
            echo "# GENERATED FILE — written by release-flake.yaml when any pack is released."
            echo "{"
            for dir in $(echo "$DIRS" | jq -r '.[]'); do
              printf '  %s = "%s";\n' "$dir" "$(tr -d '[:space:]' < "$dir/VERSION")"
            done
            echo "}"
          } > "$VERSIONS_FILE"

          if git diff --quiet -- "$VERSIONS_FILE"; then
            exit 0
          fi
          git config user.name "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
          git add "$VERSIONS_FILE"
          git commit -m "chore: refresh pack versions"
          git push
```

- [ ] **Step 3: Verify actionlint passes**

Run: `nix run nixpkgs#actionlint -- .github/workflows/nix-flake-check.yaml .github/workflows/release-flake.yaml`
Expected: no output, exit 0.

- [ ] **Step 4: Commit and PR**

```bash
git add .github/workflows/nix-flake-check.yaml .github/workflows/release-flake.yaml
git commit -m "feat(FOM-51): add hub-side flake check and release workflows

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
git push
```

Add to the existing PR rather than opening a second one.

---

### Task 5: The hub's own CI

**Files:**
- Create: `flake-hub/.github/workflows/ci.yaml`
- Create: `flake-hub/.github/workflows/release.yaml`
- Create: `flake-hub/.github/workflows/version-bump-check.yaml`

**Interfaces:**
- Consumes: the three reusable workflows from Tasks 3–4, referenced at `@main` until `gh-actions` starts tagging.

- [ ] **Step 1: Write ci.yaml**

```yaml
name: CI

on:
  pull_request:

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  check:
    uses: Fomiller/gh-actions/.github/workflows/nix-flake-check.yaml@main
    with:
      flake-dirs: '["golden-base","golden-github","tests"]'
```

`golden-engine` is absent on purpose: it has no inputs and therefore no `checks`. Its tests run from `golden-base`.

- [ ] **Step 2: Write version-bump-check.yaml**

```yaml
# A pack whose files changed without a VERSION bump ships nothing: consumers
# pin tags, so an untagged change is invisible to every repo downstream.
name: version-bump-check

on:
  pull_request:

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Every changed flake directory must bump its VERSION
        env:
          BASE: ${{ github.event.pull_request.base.sha }}
          HEAD: ${{ github.event.pull_request.head.sha }}
        run: |
          set -euo pipefail
          failed=0
          for dir in golden-*/; do
            dir=${dir%/}
            changed=$(git diff --name-only "$BASE" "$HEAD" -- "$dir" | grep -v "^$dir/VERSION$" || true)
            [ -n "$changed" ] || continue
            if git diff --quiet "$BASE" "$HEAD" -- "$dir/VERSION"; then
              echo "::error file=$dir/VERSION::$dir changed but VERSION did not"
              failed=1
            fi
          done
          exit $failed
```

- [ ] **Step 3: Write release.yaml**

```yaml
name: Release

on:
  push:
    branches: [main]

jobs:
  release:
    uses: Fomiller/gh-actions/.github/workflows/release-flake.yaml@main
    with:
      flake-dirs: '["golden-engine","golden-base","golden-github"]'
```

- [ ] **Step 4: Verify actionlint passes**

Run: `nix run nixpkgs#actionlint -- .github/workflows/*.yaml`
Expected: no output, exit 0.

- [ ] **Step 5: Push the hub and confirm CI is green**

```bash
cd /Users/forrest/dev/personal/flake-hub
gh repo create Fomiller/flake-hub --public --source=. --remote=origin --push
```

Then open a trivial PR (a README typo) and confirm `CI` and `version-bump-check` both run and pass.

- [ ] **Step 6: Commit**

```bash
git add .github
git commit -m "ci(FOM-51): wire the hub to its own flake check and release workflows

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: The generate workflow template

**Files:**
- Create: `golden-github/templates/.github/workflows/generate.yml.jinja`
- Modify: `golden-github/pack.nix`
- Create: `golden-github/tests/expected/default/.github/workflows/generate.yml`

**Interfaces:**
- Produces: a consumer workflow that calls `nix-generate.yaml` with `commit-back: true` on Renovate PRs and `false` otherwise.

- [ ] **Step 1: Write the expected snapshot**

`golden-github/tests/expected/default/.github/workflows/generate.yml`:

```yaml
# GENERATED FILE — managed by flake-hub (golden-github).
# Do not edit manually: `nix run .#generate` overwrites it.
# To change it, edit repo.nix, or the template in the pack that owns it.

name: Generate

on:
  pull_request:
    paths:
      - flake.nix
      - flake.lock
      - repo.nix

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  generate:
    uses: Fomiller/gh-actions/.github/workflows/nix-generate.yaml@main
    permissions:
      contents: write
    with:
      commit-back: ${{ github.actor == 'renovate[bot]' }}
    secrets: inherit
```

- [ ] **Step 2: Run the snapshot to verify it fails**

Run: `nix build ./golden-github#checks.aarch64-darwin.render-snapshot -L`
Expected: FAIL — `No such file or directory: .../generate.yml`.

- [ ] **Step 3: Write the template**

`golden-github/templates/.github/workflows/generate.yml.jinja`:

```jinja
{% include "_header.jinja" %}

name: Generate

on:
  pull_request:
    paths:
      - flake.nix
      - flake.lock
      - repo.nix

concurrency:
  group: {% raw %}${{ github.workflow }}-${{ github.ref }}{% endraw +%}
  cancel-in-progress: true

jobs:
  generate:
    uses: Fomiller/gh-actions/.github/workflows/nix-generate.yaml@main
    permissions:
      contents: write
    with:
      commit-back: {% raw %}${{ github.actor == 'renovate[bot]' }}{% endraw +%}
    secrets: inherit
```

Two Jinja details that will bite otherwise:

- GitHub's `${{ }}` collides with Jinja's `{{ }}`. Wrap those lines in `{% raw %}...{% endraw %}` rather than changing Jinja's delimiters — custom delimiters make the templates unreadable by any other Jinja tooling.
- makejinja runs with `trim_blocks` on, which eats the newline after a block tag and silently joins the next YAML line onto this one. `{% endraw +%}` disables the trim for that one tag. This is the single most common way a rendered workflow comes out subtly broken.

Add `".github/workflows/generate.yml"` to `ownership.managed`.

- [ ] **Step 4: Run the snapshot to verify it passes**

Run: `nix build ./golden-github#checks.aarch64-darwin.render-snapshot -L`
Expected: PASS.

- [ ] **Step 5: Assert the rendered workflow is valid YAML and valid Actions**

Add to `golden-github/flake.nix`:

```nix
        checks.rendered-workflows-lint = pkgs.runCommand "rendered-workflows-lint"
          { nativeBuildInputs = [ pkgs.actionlint ]; }
          ''
            mkdir -p repo && cd repo
            cp -r ${golden.filesDrv}/.github .
            chmod -R +w .github
            actionlint
            touch $out
          '';
```

Run: `nix build ./golden-github#checks.aarch64-darwin.rendered-workflows-lint -L`
Expected: PASS. If actionlint objects to the reusable-workflow reference resolving remotely, add `-shellcheck=` and a `actionlint.yaml` config that skips remote workflow resolution.

- [ ] **Step 6: Commit**

```bash
git add golden-github
git commit -m "feat(FOM-51): generate the consumer drift-check workflow

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: flake-hub-example and the first real loop

**Files:**
- Create: `Fomiller/flake-hub-example` (new repo)
- Modify: `flake-hub/.github/workflows/ci.yaml`

- [ ] **Step 1: Release the packs**

Merge everything so far to `main` and confirm `release.yaml` created `golden-engine-0.1.0`, `golden-base-0.1.0` and `golden-github-0.1.0`:

```bash
gh release list -R Fomiller/flake-hub
```

Expected: three releases.

- [ ] **Step 2: Bootstrap the example repo**

```bash
mkdir -p ~/dev/personal/flake-hub-example && cd ~/dev/personal/flake-hub-example
git init -q
nix run 'github:Fomiller/flake-hub?dir=golden-base#init' -- --name flake-hub-example --packs github
nix run .#generate
git add -A && git commit -m "feat: bootstrap from flake-hub

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
gh repo create Fomiller/flake-hub-example --public --source=. --remote=origin --push
```

Expected: the repo contains `flake.nix`, `flake.lock`, `repo.nix`, `.gitignore`, `.editorconfig`, `.envrc`, `justfile`, `README.md`, `CODEOWNERS`, `renovate.json`, `.github/workflows/generate.yml`.

- [ ] **Step 3: Prove the drift check fails on a hand edit**

```bash
cd ~/dev/personal/flake-hub-example
git checkout -b drift-test
echo "# hand edited" >> CODEOWNERS
# generate.yml only triggers on generator inputs, so touch one
touch repo.nix && git add -A && git commit -m "test: hand-edit a managed file"
git push -u origin drift-test
gh pr create --fill
gh pr checks --watch
```

Expected: the `generate` job fails with `Generated files are out of sync`. Close the PR without merging.

- [ ] **Step 4: Prove a pack bump regenerates**

Bump `golden-github/VERSION` to `0.2.0` in the hub with a visible template change (add a blank line to `CODEOWNERS.jinja`), merge, and confirm the tag. Then in the example repo:

```bash
cd ~/dev/personal/flake-hub-example
git checkout -b bump-test
sed -i '' 's/golden-github-0.1.0/golden-github-0.2.0/' flake.nix
nix flake lock --update-input golden-github
git add -A && git commit -m "chore: bump golden-github to 0.2.0"
git push -u origin bump-test
gh pr create --fill
gh pr checks --watch
```

Expected: the `generate` job fails on drift, because `commit-back` is false for a human actor. That is correct behavior — it proves the drift gate. Then run `nix run .#generate` locally, commit, push, and watch it go green.

- [ ] **Step 5: Record what the Renovate path will do**

Write `~/dev/personal/flake-hub-example/README.md`'s "How updates arrive" section by hand (it is `scaffold`, so it is yours to edit): a Renovate PR is authored by `renovate[bot]`, so `commit-back` evaluates true and the regenerated files land in the PR automatically. Plan 5 turns that on.

- [ ] **Step 6: Commit**

```bash
cd ~/dev/personal/flake-hub-example
git add README.md
git commit -m "docs: explain how golden file updates arrive

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
git push
```

---

## Deferred to later plans

- `golden-service`, `golden-infra`, `golden-argocd`, `helm-ecr.yaml` — plan 3.
- mdbook docs and the `mdbook.yaml` fix — plan 4.
- Renovate in the homelab cluster — plan 5.
- Tagging `gh-actions` itself so consumers can pin something other than `@main`. Worth doing, out of scope here.
