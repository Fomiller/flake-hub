# renovate-config Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A new repo, `Fomiller/renovate-config`, where Kargo records the promoted version of each flake-hub pack and Renovate bumps consumer pins only to those versions.

**Architecture:** One version file per pack under `versions/nix-flakes/`. A Kargo project in the same repo has one warehouse per pack and one hand-promoted `release` stage that writes those files. One Renovate preset reads them through a custom datasource whose URL is built from the pack name. `default.json` turns every other Renovate manager off.

**Tech Stack:** Renovate 44.171.8 (custom datasource, regex manager, regex versioning), RE2, Kargo v1.11 through `kargo-project-chart` 0.5.0, Argo CD ApplicationSet, Nix flake checks, pytest with `google-re2`.

**Spec:** `docs/superpowers/specs/2026-10-20-renovate-config-design.md` in flake-hub.

## Global Constraints

- No file, commit message, PR title or PR body in any repo touched here mentions any organisation other than `Fomiller`.
- Ticket scope `FOM-51` on every commit and PR title. Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. PR bodies carry no AI attribution.
- Every repo's trunk is `main`. Each repo's work happens in a `wt` worktree, never in the real checkout.
- Renovate is pinned at `44.171.8` everywhere: CI, local dry runs, the homelab chart.
- The repo is **public**. The custom datasource fetches `raw.githubusercontent.com` without a token. Confirm with the user before creating it.
- Packs: `golden-engine golden-base golden-github golden-service golden-infra golden-argocd golden-docs`. Seed versions (newest tags on 2026-10-20): `golden-engine-0.5.0 golden-base-0.6.0 golden-github-0.9.0 golden-service-0.6.0 golden-infra-0.6.0 golden-argocd-0.20.0 golden-docs-0.2.0`.
- The self-hosted bot's login is `fomiller-renovate-bot[bot]`. The generate workflow commits as `41898282+github-actions[bot]@users.noreply.github.com`.
- Kargo promotes by hand. No `autoPromotion` anywhere.
- Kargo writes as the `fomiller-kargo-bot` App. It is installed on every Fomiller repo with contents write, so the new repo needs no credential work.

## Review Focus

1. **A pack with a warehouse but no version file, or the reverse.** Kargo's promotion fails writing a missing file, or a version file is never updated. Test: Task 3, `test_every_warehouse_has_a_version_file_and_back`.
2. **A version file whose `version` names another pack.** A typo like `golden-base.yaml` holding `golden-infra-0.6.0` would offer a cross-pack "upgrade". Test: Task 2, `test_version_file_tag_matches_its_file_name`.
3. **Kargo's `NewestTag` ordering at a digit boundary.** `golden-argocd` already has `0.9.0` and `0.20.0`. Expected: freight is `golden-argocd-0.20.0`. Check: Task 4, Step 4.
4. **A consumer pinning a pack with no version file.** Expected: one lookup failure for that dependency, every other pin still processed. Check: Task 5, Step 3.
5. **A hand edit to a version file.** Expected: a header in every file says Kargo owns `version`. Test: Task 2, `test_every_version_file_says_kargo_owns_it`.

---

### Task 1: Create the repo and its test harness

**Files:**
- Create: `renovate-config/flake.nix`
- Create: `renovate-config/tests/conftest.py`
- Create: `renovate-config/.gitignore`

**Interfaces:**
- Produces: `nix flake check` runs `pytest tests -q` with `pytest`, `google-re2` and `pyyaml`. `tests/conftest.py` exposes `ROOT: Path` (repo root).

- [ ] **Step 1: Confirm with the user, then create the repo**

Ask: "Create `Fomiller/renovate-config` as a public repo?" On yes:

```bash
gh repo create Fomiller/renovate-config --public --description "Renovate presets and the promoted versions they read"
gh repo clone Fomiller/renovate-config ~/dev/personal/renovate-config
```

- [ ] **Step 2: Seed main with an empty commit, then make the worktree**

```bash
git -C ~/dev/personal/renovate-config commit --allow-empty -m "chore(FOM-51): initial commit

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git -C ~/dev/personal/renovate-config push -u origin main
wt -C ~/dev/personal/renovate-config switch --create FOM-51-renovate-config --no-cd --format=json
```

Work in the `path` the last command prints. Below it is `$RC`.

- [ ] **Step 3: Write `flake.nix`**

```nix
{
  description = "renovate-config: Renovate presets and the promoted versions they read";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem
      (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          python = pkgs.python3.withPackages (p: [ p.pytest p.google-re2 p.pyyaml ]);
        in
        {
          checks.tests = pkgs.runCommand "renovate-config-tests"
            { nativeBuildInputs = [ python ]; }
            ''
              cp -r ${./.} src && chmod -R +w src && cd src
              pytest tests -q
              touch $out
            '';

          devShells.default = pkgs.mkShell { packages = [ python ]; };
        });
}
```

- [ ] **Step 4: Write `tests/conftest.py` and `.gitignore`**

```python
from pathlib import Path

ROOT = Path(__file__).parent.parent
```

`.gitignore`:

```
result
argocd/overlays/*/charts/
```

- [ ] **Step 5: Lock and check**

```bash
cd $RC && nix flake lock && git add -A && nix flake check -L
```

Expected: fails with `no tests ran`, exit code 5. That is the harness working with nothing to run yet.

- [ ] **Step 6: Commit**

```bash
git -C $RC add -A
git -C $RC commit -m "chore(FOM-51): add the nix test harness

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Version files, the preset and default.json

**Files:**
- Create: `$RC/versions/nix-flakes/<pack>.yaml`, one per pack, 7 files
- Create: `$RC/presets/nix-flakes/packs.json`
- Create: `$RC/default.json`
- Test: `$RC/tests/test_preset.py`, `$RC/tests/test_versions.py`

**Interfaces:**
- Consumes: `ROOT` from `tests/conftest.py`.
- Produces: `versions/nix-flakes/<pack>.yaml` with keys `repo`, `dir`, `sourceUrl`, `version`. Kargo writes the `version` key (Task 3). Datasource name `custom.flake-hub-pack`. Preset path `github>Fomiller/renovate-config//presets/nix-flakes/packs`.

- [ ] **Step 1: Write the failing tests**

`tests/test_preset.py`:

```python
"""Renovate runs these patterns through RE2. Python's re accepts things RE2
rejects, and that gap already shipped one broken preset."""

import json

import re2

from conftest import ROOT

DEFAULT = json.loads((ROOT / "default.json").read_text())
PRESET = json.loads((ROOT / "presets/nix-flakes/packs.json").read_text())
MANAGER = PRESET["customManagers"][0]
DATASOURCE = PRESET["customDatasources"]["flake-hub-pack"]
VERSIONING = MANAGER["versioningTemplate"].removeprefix("regex:")

FLAKE = """{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    golden-engine.url = "github:Fomiller/flake-hub?dir=golden-engine&ref=refs/tags/golden-engine-0.1.0";
    golden-argocd.url = "github:Fomiller/flake-hub?dir=golden-argocd&ref=refs/tags/golden-argocd-0.20.0";
  };
}
"""


def deps():
    """Named groups first, then each *Template overwrites its field, the way
    Renovate builds a dep."""
    out = []
    for pattern in MANAGER["matchStrings"]:
        for m in re2.finditer(pattern, FLAKE):
            dep = dict(m.groupdict())
            for field in ("packageName", "datasource", "versioning"):
                template = MANAGER.get(f"{field}Template")
                if template is not None:
                    dep[field] = template.replace("{{{depName}}}", dep["depName"])
            out.append(dep)
    return out


def test_every_pattern_compiles_under_re2():
    for pattern in MANAGER["matchStrings"] + [VERSIONING]:
        re2.compile(pattern)


def test_every_pin_is_matched_with_its_full_tag():
    assert sorted((d["depName"], d["currentValue"]) for d in deps()) == [
        ("golden-argocd", "golden-argocd-0.20.0"),
        ("golden-engine", "golden-engine-0.1.0"),
    ]


def test_package_name_is_the_pack_so_the_url_is_per_pack():
    for dep in deps():
        assert dep["packageName"] == dep["depName"]
        url = DATASOURCE["defaultRegistryUrlTemplate"].replace("{{packageName}}", dep["packageName"])
        assert url == f"https://raw.githubusercontent.com/Fomiller/renovate-config/main/versions/nix-flakes/{dep['depName']}.yaml"


def test_datasource_reads_the_version_file_fields():
    assert MANAGER["datasourceTemplate"] == "custom.flake-hub-pack"
    assert DATASOURCE["format"] == "yaml"
    transform = DATASOURCE["transformTemplates"][0]
    for field in ("sourceUrl", "dir", "version"):
        assert field in transform


def test_another_packs_tag_is_never_compatible():
    compat = lambda tag: re2.match(VERSIONING, tag).group("compatibility")
    assert compat("golden-argocd-0.20.0") == "golden-argocd"
    assert compat("golden-infra-9.9.9") != compat("golden-github-1.2.3")


def test_only_the_custom_regex_manager_runs():
    """Any other manager edits files the generator owns and fails drift."""
    assert DEFAULT["enabledManagers"] == ["custom.regex"]
    assert DEFAULT["nix"]["enabled"] is False


def test_default_extends_the_preset_by_full_path():
    """Renovate has no directory default: //presets/nix-flakes would look for
    presets/nix-flakes.json."""
    assert DEFAULT["extends"] == ["github>Fomiller/renovate-config//presets/nix-flakes/packs"]


def test_regenerate_commits_do_not_stop_renovate_updating_its_pr():
    assert DEFAULT["gitIgnoredAuthors"] == ["41898282+github-actions[bot]@users.noreply.github.com"]
```

`tests/test_versions.py`:

```python
import json

import re2
import yaml

from conftest import ROOT

PACKS = sorted(p.stem for p in (ROOT / "versions/nix-flakes").glob("*.yaml"))
PRESET = json.loads((ROOT / "presets/nix-flakes/packs.json").read_text())
VERSIONING = PRESET["customManagers"][0]["versioningTemplate"].removeprefix("regex:")


def load(pack):
    return yaml.safe_load((ROOT / f"versions/nix-flakes/{pack}.yaml").read_text())


def test_every_pack_has_a_version_file():
    assert PACKS == [
        "golden-argocd", "golden-base", "golden-docs", "golden-engine",
        "golden-github", "golden-infra", "golden-service",
    ]


def test_every_version_file_has_the_fields_the_transform_reads():
    for pack in PACKS:
        assert load(pack) == {
            "repo": "github.com/Fomiller/flake-hub",
            "dir": pack,
            "sourceUrl": "https://github.com/Fomiller/flake-hub",
            "version": load(pack)["version"],
        }


def test_version_file_tag_matches_its_file_name():
    for pack in PACKS:
        m = re2.match(VERSIONING, load(pack)["version"])
        assert m is not None, pack
        assert m.group("compatibility") == pack


def test_every_version_file_says_kargo_owns_it():
    for pack in PACKS:
        text = (ROOT / f"versions/nix-flakes/{pack}.yaml").read_text()
        assert "Kargo writes `version`" in text.splitlines()[0]
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd $RC && git add -A && nix flake check -L`
Expected: FAIL. `FileNotFoundError` on `default.json`, and `test_every_pack_has_a_version_file` gets `[]`.

- [ ] **Step 3: Write the version files**

One per pack. `versions/nix-flakes/golden-base.yaml`:

```yaml
# Kargo writes `version` when golden-base is promoted to the release stage. Do not edit it by hand.
#
# Renovate reads this file to decide which golden-base tag consumer repos pin.
# `sourceUrl` and `dir` let it pull release notes into the PR body.
repo: github.com/Fomiller/flake-hub
dir: golden-base
sourceUrl: https://github.com/Fomiller/flake-hub
version: golden-base-0.6.0
```

Write the other six with the same body, replacing `golden-base` with the pack name and `version` with the seed from Global Constraints:

```bash
cd $RC/versions/nix-flakes
for pv in golden-engine:0.5.0 golden-github:0.9.0 golden-service:0.6.0 golden-infra:0.6.0 golden-argocd:0.20.0 golden-docs:0.2.0; do
  p=${pv%%:*}; v=${pv##*:}
  sed -e "s/golden-base/$p/g" -e "s/$p-0.6.0/$p-$v/" golden-base.yaml > $p.yaml
done
grep -H '^version' *.yaml
```

Expected: 7 lines, each with its own pack's seed tag.

- [ ] **Step 4: Write `presets/nix-flakes/packs.json`**

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "description": "Bumps flake-hub pack pins in flake.nix to the version Kargo promoted into versions/nix-flakes/<pack>.yaml. A pin moves only after a promotion, never on a bare tag.",
  "customDatasources": {
    "flake-hub-pack": {
      "defaultRegistryUrlTemplate": "https://raw.githubusercontent.com/Fomiller/renovate-config/main/versions/nix-flakes/{{packageName}}.yaml",
      "format": "yaml",
      "transformTemplates": [
        "{ \"sourceUrl\": sourceUrl, \"sourceDirectory\": dir, \"releases\": [ { \"version\": version } ] }"
      ]
    }
  },
  "customManagers": [
    {
      "customType": "regex",
      "description": "flake-hub pack pins",
      "managerFilePatterns": ["/(^|/)flake\\.nix$/"],
      "matchStrings": [
        "(?<depName>golden-[a-z0-9-]+)\\.url\\s*=\\s*\"github:Fomiller/flake-hub\\?dir=golden-[a-z0-9-]+&ref=refs/tags/(?<currentValue>golden-[a-z0-9-]+-[0-9]+\\.[0-9]+\\.[0-9]+)\""
      ],
      "packageNameTemplate": "{{{depName}}}",
      "datasourceTemplate": "custom.flake-hub-pack",
      "versioningTemplate": "regex:^(?<compatibility>golden-[a-z0-9-]+)-(?<major>\\d+)\\.(?<minor>\\d+)\\.(?<patch>\\d+)$"
    }
  ],
  "packageRules": [
    {
      "matchDatasources": ["custom.flake-hub-pack"],
      "commitMessageTopic": "{{depName}}",
      "commitMessageExtra": "to {{{newValue}}}"
    }
  ]
}
```

- [ ] **Step 5: Write `default.json`**

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "description": "What every Fomiller repo extends. Only the custom pack-pin manager runs: any other manager would edit files the generator owns and fail the drift check.",
  "extends": ["github>Fomiller/renovate-config//presets/nix-flakes/packs"],
  "enabledManagers": ["custom.regex"],
  "nix": { "enabled": false },
  "semanticCommits": "enabled",
  "semanticCommitType": "chore",
  "semanticCommitScope": "deps",
  "labels": ["dependencies"],
  "prConcurrentLimit": 3,
  "prHourlyLimit": 2,
  "rebaseWhen": "behind-base-branch",
  "gitIgnoredAuthors": ["41898282+github-actions[bot]@users.noreply.github.com"]
}
```

`gitIgnoredAuthors` is the identity `Fomiller/gh-actions`' `nix-generate.yaml` commits regenerated files as. Without it, Renovate treats its own branch as edited by a human and stops updating it.

- [ ] **Step 6: Run the tests**

Run: `cd $RC && git add -A && nix flake check -L`
Expected: `12 passed`.

- [ ] **Step 7: Validate with Renovate itself**

```bash
cd $RC && npx --yes --package renovate@44.171.8 -- renovate-config-validator --strict default.json presets/nix-flakes/packs.json
```

Expected: `Config validated successfully` for both files.

- [ ] **Step 8: Commit**

```bash
git -C $RC add -A
git -C $RC commit -m "feat(FOM-51): add the pack-pin preset and its version files

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: The Kargo project and CI

**Files:**
- Create: `$RC/argocd.yaml`
- Create: `$RC/argocd/overlays/prod/kustomization.yaml`
- Create: `$RC/argocd/overlays/prod/values.kargo.yaml`
- Create: `$RC/.github/workflows/ci.yaml`
- Test: `$RC/tests/test_kargo.py`

**Interfaces:**
- Consumes: `versions/nix-flakes/<pack>.yaml` and its `version` key (Task 2).
- Produces: Argo CD app `renovate-config` in namespace `renovate-config`, env `prod`. Kargo project `renovate-config` with warehouses named after each pack and a stage `release`.

- [ ] **Step 1: Write the failing test**

`tests/test_kargo.py`:

```python
import yaml

from conftest import ROOT

VALUES = yaml.safe_load((ROOT / "argocd/overlays/prod/values.kargo.yaml").read_text())
PACKS = sorted(p.stem for p in (ROOT / "versions/nix-flakes").glob("*.yaml"))


def test_every_warehouse_has_a_version_file_and_back():
    assert sorted(w["name"] for w in VALUES["warehouses"]) == PACKS


def test_each_warehouse_writes_only_its_own_file():
    for w in VALUES["warehouses"]:
        assert w["gitRepos"] == [w["name"]]
        assert w["updatePaths"] == [{
            "path": f"versions/nix-flakes/{w['name']}.yaml",
            "rootRelative": True,
            "updates": [{"key": "version", "source": w["name"]}],
        }]


def test_each_git_source_sees_only_its_own_tags():
    """Every pack is tagged on one repo. Without the anchor a warehouse would
    see every pack's tags."""
    for g in VALUES["gitRepos"]:
        assert g["git"]["repoURL"] == "https://github.com/Fomiller/flake-hub.git"
        assert g["git"]["allowTags"] == f"^{g['name']}-"
        assert g["git"]["commitSelectionStrategy"] == "NewestTag"


def test_one_release_stage_promoted_by_hand():
    (stage,) = VALUES["stages"]
    assert stage["name"] == "release"
    assert sorted(stage["warehouses"]) == PACKS
    assert "autoPromotion" not in stage
    assert "argocd" not in stage
```

- [ ] **Step 2: Run it to see it fail**

Run: `cd $RC && git add -A && nix flake check -L`
Expected: FAIL with `FileNotFoundError` on `values.kargo.yaml`.

- [ ] **Step 3: Write `argocd.yaml`**

```yaml
# What homelab's services ApplicationSet reads to build this repo's Argo CD
# Application. Nothing is deployed from here except the Kargo project.
name: renovate-config
env: prod
namespace: renovate-config
notifications: ""
```

- [ ] **Step 4: Write `argocd/overlays/prod/kustomization.yaml`**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

helmCharts:
  - name: kargo-project-chart
    repo: oci://695434033664.dkr.ecr.us-east-1.amazonaws.com
    version: 0.5.0
    releaseName: renovate-config
    # Kargo requires a project's name and namespace to match.
    namespace: renovate-config
    valuesFile: values.kargo.yaml
```

- [ ] **Step 5: Write `argocd/overlays/prod/values.kargo.yaml`**

```yaml
# The pack promotion pipeline, rendered by kargo-project-chart. Promoting a
# pack writes its tag into versions/nix-flakes/<pack>.yaml, and Renovate reads
# that file. Nothing reaches a consumer repo until someone promotes it.

project:
  name: renovate-config
  repoURL: https://github.com/Fomiller/renovate-config.git

# One source per pack. They all read flake-hub, so each is anchored to its own
# tag prefix. NewestTag, not SemVer: a name-prefixed tag does not parse as
# semver.
gitRepos:
  - { name: golden-engine,  git: { repoURL: https://github.com/Fomiller/flake-hub.git, commitSelectionStrategy: NewestTag, allowTags: '^golden-engine-' } }
  - { name: golden-base,    git: { repoURL: https://github.com/Fomiller/flake-hub.git, commitSelectionStrategy: NewestTag, allowTags: '^golden-base-' } }
  - { name: golden-github,  git: { repoURL: https://github.com/Fomiller/flake-hub.git, commitSelectionStrategy: NewestTag, allowTags: '^golden-github-' } }
  - { name: golden-service, git: { repoURL: https://github.com/Fomiller/flake-hub.git, commitSelectionStrategy: NewestTag, allowTags: '^golden-service-' } }
  - { name: golden-infra,   git: { repoURL: https://github.com/Fomiller/flake-hub.git, commitSelectionStrategy: NewestTag, allowTags: '^golden-infra-' } }
  - { name: golden-argocd,  git: { repoURL: https://github.com/Fomiller/flake-hub.git, commitSelectionStrategy: NewestTag, allowTags: '^golden-argocd-' } }
  - { name: golden-docs,    git: { repoURL: https://github.com/Fomiller/flake-hub.git, commitSelectionStrategy: NewestTag, allowTags: '^golden-docs-' } }

warehouses:
  - { name: golden-engine,  interval: 5m0s, gitRepos: [golden-engine],  updatePaths: [{ path: versions/nix-flakes/golden-engine.yaml,  rootRelative: true, updates: [{ key: version, source: golden-engine }] }] }
  - { name: golden-base,    interval: 5m0s, gitRepos: [golden-base],    updatePaths: [{ path: versions/nix-flakes/golden-base.yaml,    rootRelative: true, updates: [{ key: version, source: golden-base }] }] }
  - { name: golden-github,  interval: 5m0s, gitRepos: [golden-github],  updatePaths: [{ path: versions/nix-flakes/golden-github.yaml,  rootRelative: true, updates: [{ key: version, source: golden-github }] }] }
  - { name: golden-service, interval: 5m0s, gitRepos: [golden-service], updatePaths: [{ path: versions/nix-flakes/golden-service.yaml, rootRelative: true, updates: [{ key: version, source: golden-service }] }] }
  - { name: golden-infra,   interval: 5m0s, gitRepos: [golden-infra],   updatePaths: [{ path: versions/nix-flakes/golden-infra.yaml,   rootRelative: true, updates: [{ key: version, source: golden-infra }] }] }
  - { name: golden-argocd,  interval: 5m0s, gitRepos: [golden-argocd],  updatePaths: [{ path: versions/nix-flakes/golden-argocd.yaml,  rootRelative: true, updates: [{ key: version, source: golden-argocd }] }] }
  - { name: golden-docs,    interval: 5m0s, gitRepos: [golden-docs],    updatePaths: [{ path: versions/nix-flakes/golden-docs.yaml,    rootRelative: true, updates: [{ key: version, source: golden-docs }] }] }

stages:
  # Promoted by hand: the click is the gate. No argocd block, because nothing
  # deploys from these files; the commit is the whole promotion.
  - name: release
    color: green
    warehouses: [golden-engine, golden-base, golden-github, golden-service, golden-infra, golden-argocd, golden-docs]
    env: prod
    git:
      repoURL: https://github.com/Fomiller/renovate-config.git
      branch: main

# Git sources only. No image or chart subscriptions, so no registry credential.
credentials:
  ecr-image:
    enabled: false
  ecr-chart:
    enabled: false
```

- [ ] **Step 6: Run the tests**

Run: `cd $RC && git add -A && nix flake check -L`
Expected: `16 passed`.

- [ ] **Step 7: Render the overlay**

```bash
cd $RC && kustomize build --enable-helm argocd/overlays/prod > /tmp/rc-rendered.yaml
grep '^kind:' /tmp/rc-rendered.yaml | sort | uniq -c
```

Expected: 1 `Project`, 1 `Namespace`, 7 `Warehouse`, 1 `Stage`, and 1 `ExternalSecret` (git credential only). If the ECR login for the chart fails, run `aws ecr get-login-password --region us-east-1 | helm registry login --username AWS --password-stdin 695434033664.dkr.ecr.us-east-1.amazonaws.com` first.

Check the stage's promotion steps by eye: one `yaml-update` per warehouse, each guarded by `ctx.targetFreight.origin.name == '<pack>'`, writing `version`.

- [ ] **Step 8: Write `.github/workflows/ci.yaml`**

```yaml
name: CI

on:
  pull_request:
  push:
    branches: [main]

jobs:
  check:
    uses: Fomiller/gh-actions/.github/workflows/nix-flake-check.yaml@main
    with:
      flake-dirs: '["."]'

  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 22
      # Pinned to the version the cluster runs, so CI and the bot agree.
      - run: |
          shopt -s globstar
          npx --yes --package renovate@44.171.8 -- renovate-config-validator --strict default.json presets/**/*.json
```

Check `nix-flake-check.yaml`'s `flake-dirs` input accepts `"."` by reading it: `gh api repos/Fomiller/gh-actions/contents/.github/workflows/nix-flake-check.yaml -H "Accept: application/vnd.github.raw"`. If it builds paths as `./<dir>`, `"."` works.

- [ ] **Step 9: Write `README.md`**

Cover, in this order and briefly: what the repo is; how a release flows (tag, freight, promote, version file, Renovate PR); how to promote (`kargo promote --project renovate-config --stage release --freight <id>`, or the UI); how to add a pack (version file plus `gitRepos`, `warehouses` and stage entries, all named after the pack); why only `custom.regex` runs; why `version` is the full tag; how to validate locally (`nix flake check`, the validator command from Task 2).

- [ ] **Step 10: Check for other org names, then commit**

```bash
cd $RC && git grep -n -i -E 'flock|aviation' || echo clean
git add -A && git commit -m "feat(FOM-51): add the Kargo project that promotes pack versions

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

Expected: `clean`.

---

### Task 4: Ship renovate-config and register it with Argo CD

**Files:**
- Modify: `homelab/k8s/projects/services.yaml` (the `list.elements` of the `services` ApplicationSet), in a new homelab worktree

**Interfaces:**
- Consumes: `argocd.yaml` and `argocd/overlays/prod/` (Task 3).
- Produces: a running Kargo project `renovate-config` and the version files on `main`, which Task 5's Renovate run reads.

- [ ] **Step 1: Push and open the renovate-config PR**

Use the `create-pr` agent for `$RC`, branch `FOM-51-renovate-config`. Wait for CI to pass, then ask the user to merge it.

- [ ] **Step 2: Add the repo to the ApplicationSet, in its own PR**

Not in PR #65: Task 5 needs this running before #65 merges. Applying it by hand
does not work either, because Argo self-heals the ApplicationSet back to `main`.

```bash
H=~/dev/personal/homelab; git -C $H fetch -q origin
wt -C $H switch --create FOM-51-renovate-config-app --base origin/main --no-cd --format=json
```

In that worktree, add to `list.elements` in `k8s/projects/services.yaml`:

```yaml
                - repoURL: https://github.com/Fomiller/renovate-config.git
                  targetRevision: main
```

Commit with `feat(FOM-51): run the renovate-config Kargo project`, open the PR
with the `create-pr` agent, and ask the user to merge it.

- [ ] **Step 3: Check the app and the project**

```bash
kubectl -n argocd get application renovate-config
kubectl get project renovate-config
kubectl -n renovate-config get warehouses,stages
```

Expected: the app is `Synced` and `Healthy`, and there are 7 warehouses plus a `release` stage.

- [ ] **Step 4: Check freight, including the digit boundary**

```bash
kubectl -n renovate-config get freight -o custom-columns=ORIGIN:.origin.name,TAG:.commits[0].tag --sort-by=.metadata.creationTimestamp
```

Expected: the newest `golden-argocd` freight is `golden-argocd-0.20.0`, not `golden-argocd-0.9.0`. If `0.9.0` wins, `NewestTag` sorts by name on this Kargo: stop, and switch every source to `commitSelectionStrategy: SemVer` with a `strictSemvers: false` check before going further. Report it either way.

- [ ] **Step 5: Promote one pack to prove the write path**

Promote the newest `golden-docs` freight (its version file already holds that tag, so the commit is a no-op diff or absent):

```bash
kargo promote --project renovate-config --stage release --freight <golden-docs freight name>
kubectl -n renovate-config get promotions -w
```

Expected: the promotion `Succeeded`. `git -C ~/dev/personal/renovate-config pull && git log -1 -- versions/nix-flakes/golden-docs.yaml` shows either a Kargo commit or no change. A failed promotion that names the file path is a Task 3 `updatePaths` bug.

---

### Task 5: Point the homelab Renovate at renovate-config

**Files:**
- Modify: `homelab/k8s/apps/renovate/renovate-config.json`

**Interfaces:**
- Consumes: preset `github>Fomiller/renovate-config` on `main` (Task 4).
- Produces: a Renovate CronJob that reads promoted versions only.

- [ ] **Step 1: Rewrite `renovate-config.json`**

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["github>Fomiller/renovate-config"],
  "ignorePresets": ["github>Fomiller/flake-hub//renovate/default"],
  "platform": "github",
  "username": "fomiller-renovate-bot[bot]",
  "gitAuthor": "fomiller-renovate-bot <345368954+fomiller-renovate-bot[bot]@users.noreply.github.com>",
  "autodiscover": true,
  "autodiscoverFilter": [
    "Fomiller/flake-hub-example",
    "Fomiller/flake-hub-example-service"
  ],
  "onboarding": false,
  "requireConfig": "optional"
}
```

`ignorePresets` stays until both example repos merge the `golden-github` bump in Task 7. Their `renovate.json` still extends the old flake-hub preset, which is invalid under RE2.

- [ ] **Step 2: Dry run in the real image**

Mint a token and run the exact CronJob script against the merged `main` of renovate-config:

```bash
cd ~/dev/worktrees/homelab/FOM-51-renovate/k8s/apps/renovate
S=$(mktemp -d); cp renovate-config.json $S/config.json; cp mint-token.js $S/
doppler run -p renovate -c dev -- bash -c 'docker run --rm \
  -e GITHUB_APP_CLIENT_ID="$RENOVATE_CLIENT_ID" -e GITHUB_APP_INSTALLATION_ID="$RENOVATE_INSTALLATION_ID" -e GITHUB_APP_PRIVATE_KEY="$RENOVATE_PRIVATE_KEY" \
  -e RENOVATE_CONFIG_FILE=/opt/renovate/config.json -e RENOVATE_DRY_RUN=full -e LOG_LEVEL=info \
  -v '"$S"':/opt/renovate:ro --entrypoint /bin/bash ghcr.io/renovatebot/renovate:44.171.8 \
  -c "set -e; RENOVATE_TOKEN=\$(node /opt/renovate/mint-token.js); export RENOVATE_TOKEN; renovate"' 2>&1 | tee $S/run.log | grep -E "WARN|ERROR|Would commit"
```

Expected for `flake-hub-example`: `Would commit` for `golden-engine`, `golden-base` and `golden-github` branches, and no `invalid config` warning. Expected for `flake-hub-example-service`: no branches, since its pins equal the seeds. No `golang`, `actions-*` or other non-pack branches anywhere.

- [ ] **Step 3: Check one unknown pack does not stop the rest**

Add a pin for a pack with no version file to a scratch flake and run the extractor against it. Simplest form: point the dry run at a fork-free local check with `--platform=local`:

```bash
D=$(mktemp -d) && cd $D && git init -q && cat > flake.nix <<'EOF'
{ inputs = {
    golden-base.url = "github:Fomiller/flake-hub?dir=golden-base&ref=refs/tags/golden-base-0.5.0";
    golden-nope.url = "github:Fomiller/flake-hub?dir=golden-nope&ref=refs/tags/golden-nope-0.1.0";
}; }
EOF
echo '{"extends":["github>Fomiller/renovate-config"]}' > renovate.json && git add -A && git commit -qm init
GITHUB_COM_TOKEN=$(gh auth token) LOG_LEVEL=debug npx --yes renovate@44.171.8 --platform=local --dry-run=lookup 2>&1 | grep -E "golden-(base|nope)|Failed to look up"
```

Expected: `golden-nope` logs a failed lookup, and `golden-base` still shows `newValue` `golden-base-0.6.0`.

- [ ] **Step 4: Commit and update PR #65**

```bash
git -C ~/dev/worktrees/homelab/FOM-51-renovate add k8s/apps/renovate/renovate-config.json
git -C ~/dev/worktrees/homelab/FOM-51-renovate commit -m "feat(FOM-51): read promoted pack versions from renovate-config

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git -C ~/dev/worktrees/homelab/FOM-51-renovate push
```

Update PR #65's body with the `create-pr` agent: it now depends on renovate-config, not on flake-hub #41. Ask the user to merge #65.

- [ ] **Step 5: First real run**

```bash
kubectl -n renovate get externalsecret
kubectl -n renovate create job --from=cronjob/renovate renovate-manual-1
kubectl -n renovate logs -f job/renovate-manual-1 | grep -E "WARN|ERROR|PR created|Branch created"
```

Expected: both ExternalSecrets `SecretSynced`. Three PRs on `flake-hub-example` (`golden-engine`, `golden-base`, `golden-github`). Each one's `Generate` check fails on drift, because the old `generate.yml` does not recognise the self-hosted bot. That is fixed in Task 6; leave these PRs open.

---

### Task 6: Fix golden-github for the self-hosted bot

**Files:**
- Modify: `flake-hub/golden-github/templates/renovate.json.jinja`
- Modify: `flake-hub/golden-github/templates/.github/workflows/generate.yml.jinja:22`
- Modify: `flake-hub/golden-github/tests/expected/default/renovate.json`
- Modify: `flake-hub/golden-github/tests/expected/default/.github/workflows/generate.yml:26`
- Modify: `flake-hub/golden-github/VERSION` (`0.9.0` to `0.10.0`)
- Modify: `flake-hub/docs/src/flakes/golden-github.md` if it describes either file

**Interfaces:**
- Produces: tag `golden-github-0.10.0` once merged. The release workflow cuts it.

Work in the worktree `~/dev/worktrees/flake-hub/FOM-51-renovate-config` (it already holds the spec and this plan).

- [ ] **Step 1: Update the expected output first**

`golden-github/tests/expected/default/renovate.json`:

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["github>Fomiller/renovate-config"]
}
```

In `golden-github/tests/expected/default/.github/workflows/generate.yml`, line 26:

```yaml
      commit-back: ${{ github.actor == 'fomiller-renovate-bot[bot]' }}
```

- [ ] **Step 2: Run the pack's check to see it fail**

Run: `nix build ./golden-github#checks.aarch64-darwin.default -L --no-link` (list the check names with `nix flake show ./golden-github` if `default` is not one).
Expected: FAIL, with a diff on both files.

- [ ] **Step 3: Change the templates**

`golden-github/templates/renovate.json.jinja`:

```
{% if github.renovate %}
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["github>Fomiller/renovate-config"]
}
{% endif %}
```

Labels, limits and the manager list now come from renovate-config's `default.json`, so the repo file only says where to look.

`golden-github/templates/.github/workflows/generate.yml.jinja`, line 22:

```
      commit-back: {% raw %}${{ github.actor == 'fomiller-renovate-bot[bot]' }}{% endraw +%}
```

- [ ] **Step 4: Bump VERSION, regenerate the reference, run the check**

```bash
echo 0.10.0 > golden-github/VERSION
nix build ./golden-github#checks.aarch64-darwin.default -L --no-link
```

Expected: PASS. If the docs reference page is generated (`docs/gen-reference.nix`), regenerate it the way FOM-157 did (`docs(FOM-157): regenerate the golden-service reference`) and check the diff touches only `golden-github` text.

- [ ] **Step 5: Commit, PR, merge, confirm the tag**

```bash
git add golden-github docs/src/flakes/golden-github.md
git commit -m "feat(FOM-51): point golden-github at renovate-config and the self-hosted bot

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

Open the PR with the `create-pr` agent. The PR also carries the spec and this plan. Ask the user to merge. Then:

```bash
git ls-remote --tags origin 'refs/tags/golden-github-0.10.0'
```

Expected: one line.

---

### Task 7: Promote golden-github-0.10.0 end to end

**Interfaces:**
- Consumes: tag `golden-github-0.10.0` (Task 6), the Kargo project (Task 4), the Renovate CronJob (Task 5).

- [ ] **Step 1: Confirm the gate holds**

Wait for the `golden-github` warehouse to pick up the tag (5 minute interval). Then:

```bash
kubectl -n renovate-config get freight -o custom-columns=ORIGIN:.origin.name,TAG:.commits[0].tag | grep golden-github
kubectl -n renovate create job --from=cronjob/renovate renovate-manual-2
kubectl -n renovate logs -f job/renovate-manual-2 | grep golden-github
```

Expected: freight for `golden-github-0.10.0` exists. Renovate still proposes `golden-github-0.9.0` at most. No PR for `0.10.0` exists yet. This is the gate working.

- [ ] **Step 2: Promote**

Ask the user to promote it, or with their go-ahead:

```bash
kargo promote --project renovate-config --stage release --freight <golden-github-0.10.0 freight name>
```

Expected: `versions/nix-flakes/golden-github.yaml` on renovate-config `main` reads `version: golden-github-0.10.0`, committed by the Kargo bot.

- [ ] **Step 3: Renovate picks it up**

Wait 5 minutes for the raw.githubusercontent.com cache, then:

```bash
kubectl -n renovate create job --from=cronjob/renovate renovate-manual-3
kubectl -n renovate logs -f job/renovate-manual-3 | grep -E "golden-github|PR (created|updated)"
```

Expected: the `golden-github` PR on `flake-hub-example` now targets `golden-github-0.10.0`, and a new one exists on `flake-hub-example-service`.

- [ ] **Step 4: Regenerate those two PRs by hand, once**

They still run the old `generate.yml`. For each of the two repos:

```bash
gh pr checkout <pr> -R Fomiller/<repo> && nix run .#generate && git add -A && git commit -m "chore(FOM-51): regenerate for golden-github-0.10.0

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" && git push
```

Expected: `Generate` passes. The diff includes the new `renovate.json` and the new actor check. Ask the user to merge both.

- [ ] **Step 5: The next PR regenerates on its own**

After both merge, the open `golden-engine` and `golden-base` PRs on `flake-hub-example` rebase (`rebaseWhen: behind-base-branch`) and their `Generate` runs now see `fomiller-renovate-bot[bot]`.

Expected: a `github-actions[bot]` commit with regenerated files on each, and Renovate keeps updating the PR afterwards (`gitIgnoredAuthors`).

---

### Task 8: Remove the old preset

**Files:**
- Delete: `flake-hub/renovate/`
- Modify: `flake-hub/.github/workflows/ci.yaml:14` (drop `"renovate"` from `flake-dirs`)
- Modify: `flake-hub/justfile` (drop `renovate` from `fmt`)
- Modify: `flake-hub/README.md` (the `renovate` row in the flakes table points at `Fomiller/renovate-config`)
- Modify: `flake-hub/docs/src/introduction.md:29`, `flake-hub/docs/src/concepts/propagation.md:19`, `flake-hub/docs/src/runbooks/renovate-app.md`
- Modify: `homelab/k8s/apps/renovate/renovate-config.json` (drop `ignorePresets`)

- [ ] **Step 1: Confirm nothing still extends the old preset**

```bash
for r in flake-hub-example flake-hub-example-service; do gh api repos/Fomiller/$r/contents/renovate.json -H "Accept: application/vnd.github.raw" | grep -c 'flake-hub//renovate' ; done
```

Expected: `0` twice. If not, Task 7 is not finished.

- [ ] **Step 2: Remove it from flake-hub**

New worktree `FOM-51-drop-renovate-preset` off `origin/main`. Delete `renovate/`, apply the edits above. In `docs/src/runbooks/renovate-app.md`, fix the App name to `fomiller-renovate-bot`, add the Doppler project `renovate` and the `RENOVATE_CLIENT_ID` secret, and add an operations section: logs (`kubectl -n renovate logs job/<name>`), a manual run, suspending (`kubectl -n renovate patch cronjob renovate -p '{"spec":{"suspend":true}}'`), and promoting (`kargo promote --project renovate-config --stage release`).

Run: `nix build ./docs#checks.aarch64-darwin.default -L --no-link` (or the docs flake's check name), then `git grep -n 'flake-hub//renovate' -- ':!docs/superpowers'`.
Expected: the build passes, and the grep prints nothing.

- [ ] **Step 3: Drop `ignorePresets` in homelab**

New homelab worktree `FOM-51-drop-ignore-presets`. Remove the `ignorePresets` line from `k8s/apps/renovate/renovate-config.json`.

- [ ] **Step 4: Commit, PR, close #41**

Commit each repo with `chore(FOM-51): drop the flake-hub renovate preset` and `chore(FOM-51): stop ignoring the old flake-hub preset`. Open both PRs with the `create-pr` agent. Close flake-hub #41 with a comment linking renovate-config:

```bash
gh pr close 41 -R Fomiller/flake-hub --comment "Replaced by Fomiller/renovate-config, which reads Kargo-promoted versions instead of bare tags."
```
