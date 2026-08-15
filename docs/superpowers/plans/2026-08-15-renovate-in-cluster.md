# Renovate in the Homelab Cluster Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Renovate runs as an Argo CD app in the homelab cluster, discovers the `Fomiller` repos, and opens PRs that bump flake-hub pack pins — which the consumer's own generate workflow then fills in with regenerated files.

**Architecture:** A new `k8s/apps/renovate/` directory in `homelab`, following the argocd-autopilot layout already used by every other app there: `config.json`, `namespace.yaml`, `kustomization.yaml` with a `helmCharts` entry, `values.yaml`, and `external-secrets.yaml` pulling credentials from Doppler. The chart deploys a CronJob. Renovate's own config is the preset already committed at `renovate/default.json` in flake-hub, extended by both the cluster config and every consumer repo, so there is one copy of the pack-pin regex.

**Tech Stack:** Argo CD, argocd-autopilot, Kustomize, Helm (`renovatebot/renovate` chart), External Secrets, Doppler, GitHub App.

## Global Constraints

- Prerequisites: plans 1–4 complete. `renovate/default.json` exists in flake-hub and its tests pass. `docs/src/runbooks/renovate-app.md` exists.
- Repo: `~/dev/personal/homelab`. Default branch is **not** `main` for every repo — resolve it: `wt -C ~/dev/personal/homelab config state default-branch`.
- Work in a worktree: `/wt-switch-create FOM-51-renovate ~/dev/personal/homelab`.
- Follow the existing app layout exactly. Read `k8s/apps/homepage/` and `k8s/apps/descheduler/` before writing anything. Do not invent a second convention.
- Secrets come from Doppler through External Secrets, using the `doppler-token-sa` bootstrap credential pattern already in the cluster. No secret values in git, ever.
- Renovate must not run `nix run .#generate` itself. `allowedPostUpgradeCommands` stays unset. Generation happens in each consumer's workflow.
- Egress to github.com only. No Ingress, no IngressRoute, no Tailscale exposure.
- Blast radius: start with `autodiscoverFilter` scoped to the two example repos. Widen only after a real PR looks right.
- Commit messages: conventional prefix, scope `FOM-51`, `Co-Authored-By: Claude` trailer.

---

### Task 1: Decide and document the auth mechanism

Renovate's self-hosted GitHub App support has changed across versions, and getting this wrong means a CronJob that authenticates as the wrong identity or not at all. Settle it before writing manifests.

**Files:**
- Modify: `flake-hub/docs/src/runbooks/renovate-app.md`

- [ ] **Step 1: Check the current documented mechanism**

Read <https://docs.renovatebot.com/modules/platform/github/> and <https://docs.renovatebot.com/self-hosted-configuration/> for the version of the chart being deployed. Determine which of these the running version supports:

- Native GitHub App auth via app ID plus private key set in the environment.
- An installation token minted before each run and passed as `RENOVATE_TOKEN`.
- A fine-grained PAT as `RENOVATE_TOKEN`.

- [ ] **Step 2: Pick one and write it down**

Preference order: native App auth, then minted installation token, then PAT. A PAT is acceptable as a starting point but is tied to your personal account and expires — if that is the choice, note the expiry date in the runbook and treat replacing it as follow-up work.

Update `docs/src/runbooks/renovate-app.md` with the mechanism actually chosen, the exact Doppler secret names, and the App permissions:

- Contents: read/write
- Pull requests: read/write
- Metadata: read
- Workflows: read/write (Renovate edits `.github/workflows` when a workflow pin changes)

- [ ] **Step 3: Create the App and store the credentials**

This is yours to do by hand — an agent cannot create a GitHub App on your account:

1. github.com → Settings → Developer settings → GitHub Apps → New GitHub App.
2. Name it `fomiller-renovate`. Homepage URL can be the flake-hub repo.
3. Uncheck Webhook active.
4. Set the permissions above.
5. Create, note the App ID, generate a private key, download the `.pem`.
6. Install the App on `Fomiller/flake-hub-example` and `Fomiller/flake-hub-example-service` only, to start.
7. Put the App ID and the private key into Doppler, project `homelab`, config `dev`, under the names written in the runbook.

- [ ] **Step 4: Verify the credentials work before deploying anything**

Run Renovate locally in dry-run mode against one repo using the same credentials:

```bash
nix run nixpkgs#renovate -- --dry-run=full --platform=github \
  --autodiscover=false Fomiller/flake-hub-example
```

Expected: it authenticates, reads the repo, and logs the pack-pin dependencies it found without opening a PR. If it reports zero dependencies, the preset regex is not matching — fix that before deploying, because the cluster gives no faster feedback loop than this.

- [ ] **Step 5: Commit the runbook update**

```bash
cd ~/dev/personal/flake-hub
git add docs/src/runbooks/renovate-app.md
git commit -m "docs(FOM-51): record the Renovate auth mechanism and app permissions

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: The Renovate config

Written and validated before it is mounted into anything.

**Files:**
- Create: `homelab/k8s/apps/renovate/renovate-config.json`

**Interfaces:**
- Consumes: preset `github>Fomiller/flake-hub//renovate/default`.
- Produces: the config file the CronJob mounts, referenced by `RENOVATE_CONFIG_FILE`.

- [ ] **Step 1: Create the worktree**

```
/wt-switch-create FOM-51-renovate ~/dev/personal/homelab
```

Run every command below against the worktree path `wt` prints.

- [ ] **Step 2: Write the config**

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": [
    "config:recommended",
    "github>Fomiller/flake-hub//renovate/default"
  ],
  "platform": "github",
  "autodiscover": true,
  "autodiscoverFilter": [
    "Fomiller/flake-hub-example",
    "Fomiller/flake-hub-example-service"
  ],
  "onboarding": false,
  "requireConfig": "optional",
  "prConcurrentLimit": 3,
  "prHourlyLimit": 2,
  "labels": ["dependencies"],
  "packageRules": [
    {
      "description": "Pack pins move one at a time so a broken pack is easy to attribute.",
      "matchDepNames": ["Fomiller/flake-hub"],
      "groupName": null,
      "separateMinorPatch": false
    }
  ]
}
```

`onboarding: false` with `requireConfig: "optional"` matters: consumer repos already ship a generated `renovate.json`, and onboarding PRs would fight the generator over that file.

- [ ] **Step 3: Validate it**

Run: `nix run nixpkgs#renovate -- --platform=github --dry-run=full` with `RENOVATE_CONFIG_FILE` pointing at the file.
Expected: it parses the config, resolves the remote preset, and lists the two repos. A preset resolution failure here is the single most likely deployment bug — catch it now, not in a CronJob log.

Also run the validator directly:

```bash
nix run nixpkgs#renovate -- --help >/dev/null   # confirms the package exists
npx --yes renovate-config-validator k8s/apps/renovate/renovate-config.json
```

Expected: `Config validated successfully`.

- [ ] **Step 4: Commit**

```bash
git add k8s/apps/renovate/renovate-config.json
git commit -m "feat(FOM-51): add the cluster Renovate config

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: The Argo CD app manifests

**Files:**
- Create: `homelab/k8s/apps/renovate/config.json`
- Create: `homelab/k8s/apps/renovate/namespace.yaml`
- Create: `homelab/k8s/apps/renovate/kustomization.yaml`
- Create: `homelab/k8s/apps/renovate/values.yaml`
- Create: `homelab/k8s/apps/renovate/external-secrets.yaml`

- [ ] **Step 1: Read the reference apps**

Read `k8s/apps/descheduler/` for the minimal shape and `k8s/apps/homepage/external-secrets.yaml` for the Doppler pattern: an ExternalSecret materializing `doppler-token-sa` from `aws-clustersecretstore`, a namespaced `SecretStore` pointing at a Doppler project and config, then app secrets pulled through that store.

- [ ] **Step 2: Write config.json**

```json
{
  "appName": "renovate",
  "userGivenName": "renovate",
  "destNamespace": "default",
  "destServer": "https://kubernetes.default.svc",
  "srcPath": "k8s/apps/renovate",
  "srcRepoURL": "https://github.com/Fomiller/homelab.git",
  "srcTargetRevision": "main",
  "labels": null,
  "annotations": null
}
```

Set `srcTargetRevision` to the repo's real default branch, not `main`, if they differ.

- [ ] **Step 3: Write namespace.yaml**

```yaml
apiVersion: v1
kind: Namespace
metadata:
  annotations:
    argocd.argoproj.io/sync-options: Prune=false
  name: renovate
```

- [ ] **Step 4: Write external-secrets.yaml**

Mirror the homepage pattern exactly: the `doppler-token-sa` ExternalSecret from `aws-clustersecretstore`, a `doppler-renovate` SecretStore on project `homelab` config `dev`, and one ExternalSecret pulling the Renovate credentials into a `renovate-credentials` Secret. Use the secret names the runbook recorded in Task 1.

Add a comment above the credentials ExternalSecret naming what the App can do and where it is installed. The next person to read this file needs to know its blast radius without going to GitHub.

- [ ] **Step 5: Check the chart's real value names**

```bash
helm repo add renovate https://docs.renovatebot.com/helm-charts
helm repo update
helm show values renovate/renovate | head -100
```

Write `values.yaml` against what that prints, not from memory. The shape to aim for:

- CronJob schedule: hourly.
- `renovate.config` left unset — the config comes from the mounted file, not from chart values, so the JSON stays reviewable as JSON.
- The `renovate-credentials` Secret wired in via `envFrom` or `existingSecret`, whichever the chart supports.
- `RENOVATE_CONFIG_FILE` pointing at the mounted config path.
- Resource requests and limits set. An unbounded CronJob on a homelab node is how a cluster falls over at 3am.
- `successfulJobsHistoryLimit: 3`, `failedJobsHistoryLimit: 3`.

- [ ] **Step 6: Write kustomization.yaml**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: renovate

resources:
- namespace.yaml
- external-secrets.yaml

configMapGenerator:
- name: renovate-config
  files:
  - config.json=renovate-config.json
  options:
    disableNameSuffixHash: true

helmCharts:
- name: renovate
  repo: https://docs.renovatebot.com/helm-charts
  releaseName: renovate
  version: <pin the version helm search returns>
  namespace: renovate
  valuesFile: values.yaml
```

- [ ] **Step 7: Render it locally before letting Argo near it**

```bash
kustomize build --enable-helm k8s/apps/renovate | tee /tmp/renovate-rendered.yaml
```

Expected: a Namespace, a ConfigMap, two ExternalSecrets, a SecretStore and a CronJob. Check by eye:

- The CronJob mounts the ConfigMap and sets `RENOVATE_CONFIG_FILE`.
- No Service, no Ingress, no IngressRoute.
- No secret literal anywhere in the output.

```bash
grep -iE 'ingress|LoadBalancer' /tmp/renovate-rendered.yaml || echo "no ingress, good"
```

- [ ] **Step 8: Commit**

```bash
git add k8s/apps/renovate
git commit -m "feat(FOM-51): deploy Renovate as an Argo CD app

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Deploy and watch the first run

- [ ] **Step 1: Open the PR**

```bash
git push -u origin FOM-51-renovate
gh pr create --title "feat(FOM-51): run Renovate in the cluster" --body "$(cat <<'EOF'
Adds Renovate as an Argo CD app. It runs hourly as a CronJob and opens PRs that bump flake-hub pack pins in consumer repos.

Scoped to the two flake-hub example repos to start, via autodiscoverFilter. Widening that is a one-line change once a real PR looks right.

Renovate does not run any repo code. `allowedPostUpgradeCommands` is unset on purpose — regenerating golden files happens in each consumer's own workflow, so Renovate never executes anything from a repo it is updating.

Credentials come from Doppler through External Secrets, same bootstrap pattern as homepage. Egress only, no ingress.
EOF
)"
```

- [ ] **Step 2: Merge and confirm the sync**

```bash
kubectl -n renovate get cronjob,configmap,externalsecret
kubectl -n renovate get externalsecret -o wide
```

Expected: the CronJob exists and both ExternalSecrets report `SecretSynced`. An ExternalSecret stuck on `SecretSyncedError` means the Doppler names in the manifest and in Doppler disagree — fix the manifest, not Doppler.

- [ ] **Step 3: Trigger a run by hand instead of waiting an hour**

```bash
kubectl -n renovate create job --from=cronjob/renovate renovate-manual-1
kubectl -n renovate logs -f job/renovate-manual-1
```

Expected in the log: authentication succeeds, both repos are discovered, and the pack-pin dependency is found. If it finds no dependencies, the preset is not resolving — check the log for the preset fetch, since a private-preset 404 is reported as a warning and Renovate keeps going with an incomplete config.

- [ ] **Step 4: Confirm the PR and the loop**

Bump a pack `VERSION` in flake-hub, merge, and confirm the tag. Then trigger another manual run.

Expected:
1. Renovate opens a PR on `flake-hub-example` bumping the pin in `flake.nix`.
2. That PR's `Generate` workflow runs, sees `github.actor == 'renovate[bot]'`, and commits the regenerated files into the PR.
3. The pushed commit does **not** retrigger the workflow, because it was pushed with `GITHUB_TOKEN`.
4. The PR diff contains both the pin bump and the regenerated files.

If step 3 loops instead, stop the CronJob (`kubectl -n renovate patch cronjob renovate -p '{"spec":{"suspend":true}}'`) before debugging.

- [ ] **Step 5: Widen the scope**

Once a PR has landed cleanly, replace `autodiscoverFilter` with `["Fomiller/*"]`, or an explicit list if you would rather add repos deliberately. Commit that as its own change so it is easy to revert.

- [ ] **Step 6: Record what to check when it misbehaves**

Add a short operations section to `flake-hub/docs/src/runbooks/renovate-app.md`: where the logs are, how to trigger a manual run, how to suspend the CronJob, and the three failure modes seen so far (preset 404, Doppler name mismatch, and a `commit-back` loop if someone swaps the token).

```bash
cd ~/dev/personal/flake-hub
git add docs/src/runbooks/renovate-app.md
git commit -m "docs(FOM-51): add Renovate operations notes

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Done means

- A tag on flake-hub produces a Renovate PR on a consumer repo within the hour.
- That PR contains the regenerated files, committed by the consumer's own workflow.
- A hand-edited generated file fails CI on any PR that touches a generator input.
- No credential is in git, and Renovate executes no repo code.

## Deferred

- Migrating `homelab` itself to consume `golden-base + golden-github + golden-infra`. It is the reference for the infra layout, so it should eventually eat its own output, but it is live infrastructure and deserves its own plan.
- `allowedPostUpgradeCommands`. Available now that Renovate is self-hosted, deliberately unused.
- Kargo-style promotion controls over pack releases.
