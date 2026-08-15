# Helm-chart-to-ECR repo: findings to fold into `golden-service`

Source: the `Fomiller/kargo-project-chart` repo, scaffolded by hand in 2026-08
because `flake-hub` was not ready. It is the reference implementation for a
repo whose product is a Helm chart published to ECR as an OCI artifact. Plan 3
(`golden-service`, `helm-ecr.yaml`) should lift from it rather than invent.

## Published coordinates

- Registry: `695434033664.dkr.ecr.us-east-1.amazonaws.com`
- Repo path: `charts/kargo-project`, region `us-east-1`
- ECR repo is created in Terraform inside the chart repo at
  `infra/units/aws/global/ecr`, Terragrunt layout copied from `homelab`,
  state in `fomiller-terraform-state-dev` namespaced by `repo_name`.
  PRs plan, pushes to main apply.

## The push-path trap

`helm push` appends the chart's own name to the registry path it is given. So
the ECR repo must be `<prefix>/<chart-name>` and the push target is
`oci://<registry>/<prefix>` — without the chart name. Getting this wrong does
not error; it silently creates a second repo. The `charts/` prefix leaves room
for more charts beside it.

Any `helm-ecr.yaml` the pack emits must template the prefix, not the full path.

## Versioning

The chart repo did not reuse `Fomiller/gh-actions`. Release is a plain in-repo
workflow driven by `scripts/next-version.sh`:

- Next semver comes from conventional-commit subjects since the last tag.
- Merge to main cuts a stable version. `workflow_dispatch` off a branch cuts
  `-rc.N`, numbered per target version.
- `Chart.yaml` holds a placeholder that CI overwrites before packaging, so the
  committed tree never disagrees with what was published.
- Pre-1.0, a breaking change bumps MINOR. Reaching 1.0.0 is a deliberate
  decision, not a side effect of a `!` in a commit subject.

The ECR repo is IMMUTABLE — a wrong bump cannot be withdrawn. That is why the
version logic carries its own suite at `scripts/tests/next-version.test.sh`
(10 cases). Lift the tests along with the script if the pack ships it.

The pre-1.0 MINOR rule is a choice, not a general truth. Surface it as a pack
option rather than baking it in: a repo already past 1.0 wants normal semver,
and the script handles both.

## The executable bit — build this before shipping next-version.sh

`reconcile.py` hardcodes `dst.chmod(0o644)`, so today no generated file can be
executable. The plan JSON has no vocabulary for file mode at all. That blocks
`next-version.sh`, which has to be runnable.

Decision: a per-pack `executable` glob list, resolved the same way the
ownership globs are. Not file mode carried per path in the plan JSON. The globs
match how a pack already declares `managed` / `scaffold` / `retired`, and they
keep the plan describing classification rather than filesystem detail.

Build it in plan 3, before `golden-service` ships. Work involved:

- `pack.nix` gains an `executable` list of globs.
- `merge.nix` unions it across packs like the other ownership lists.
- `plan.nix` resolves the globs to concrete paths and emits them in the plan.
- `reconcile.py` stops hardcoding `0o644` and reads the mode from the plan.
- A test proving a matched path lands `0o755` and an unmatched one `0o644`.

Retrofitting after packs are tagged means a coordinated re-release across every
pack, so do it while nothing is tagged.

## Terraform ECR unit — take it as-is

`infra/units/aws/global/ecr` plus the four `infra/live/*.hcl` files. About 50
lines of `aws_ecr_repository` and a lifecycle policy. Only `chart_prefix` and
`chart_name` are chart-specific; everything else is generic. Two parts are
load-bearing and easy to get subtly wrong, so pack them deliberately instead of
regenerating:

- `image_tag_mutability = "IMMUTABLE"` — this is what makes a wrong version bump
  fail at the registry instead of quietly replacing a chart someone already
  pulled. It is also why the version tests exist.
- The state key is `${repo_name}/${path_relative_to_include()}`, with
  `repo_name` from `service.hcl`. That is what lets many repos share homelab's
  `fomiller-terraform-state-dev` bucket without colliding. A pack that
  hardcodes the key collides the first time two generated repos both have an
  `ecr` unit.

## Reusable vs. chart-specific

- Reusable for any OCI-artifact repo: the ECR unit, `deploy-infra.yaml`,
  `next-version.sh` and its tests, `renovate.json`, the `dev`-environment and
  OIDC wiring.
- Chart-specific: the snapshot test harness (`tests/run.sh`) and the
  lint-every-fixture loop.
- In between: the release workflow. Its shape is generic, but `helm package` /
  `helm push` and the `Chart.yaml` stamping are helm-only.

A precise file-level breakdown is available from that repo's owner when
`golden-service` is ready to regenerate it; the split may shift with use.

## Two things that will otherwise be rediscovered

1. `helm lint` fails with `invalid Yaml document separator` when a template
   emits `---` after each document in a `range`. Emit it before instead.
2. Helm 4.2.4 emits a blank line before `---` where 4.2.3 does not, which
   breaks snapshot tests on a patch bump. Pin helm in CI and ignore blank
   lines when diffing.

## Values schema shape

Four deliberately separate lists, worth matching if the pack grows a Kargo
archetype:

- `services[]`, `charts[]`, `gitRepos[]` — freight sources. Name plus artifact
  location, nothing more. Names must be unique across all three, because
  `updates[].source` resolves against all three by name; the chart fails the
  render otherwise.
- `warehouses[]` — subscribe to sources (`"all"` or an explicit list per kind)
  and carry `updatePaths`. Path mappings live here, not on the stage.
- `stages[]` — thin environment bindings: warehouses, `overlayPath`, `env`, git
  branch, optional Argo CD app. Stays about five lines however many files the
  warehouse touches.
- `channels{}`, `prereleasePattern`, `rbac{}`.

`project.name` doubles as the namespace, because Kargo requires them to match.
