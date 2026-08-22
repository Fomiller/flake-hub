{
  description = "golden-infra: terragrunt scaffolding and the deploy workflow";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    golden-engine.url = "path:../golden-engine";
    golden-base.url = "path:../golden-base";
    golden-github.url = "path:../golden-github";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, golden-engine, golden-base, golden-github, flake-utils }:
    flake-utils.lib.eachDefaultSystem
      (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          render = fixture: golden-engine.lib.mkGolden
            {
              packs = [ golden-base.pack golden-github.pack self.pack ];
            }
            pkgs
            (import fixture);

          # The loop only visits files the expected tree already has, so an
          # emptied expected tree would pass silently. The count is the guard.
          snapshot = name: count: expected: fixture:
            pkgs.runCommand "render-${name}" { } ''
              found=$(cd ${expected} && find . -type f | wc -l)
              if [ "$found" -ne ${toString count} ]; then
                echo "expected tree for ${name} holds $found files, not ${toString count}" >&2
                exit 1
              fi
              for f in $(cd ${expected} && find . -type f | sed 's|^\./||'); do
                diff -u "${expected}/$f" "${(render fixture).filesDrv}/$f"
              done
              touch $out
            '';
        in
        {
          # Building these is how you refresh the snapshots after a template
          # change: `nix build .#files-dev-only` and diff against tests/expected.
          packages.files-dev-only = (render ./tests/fixtures/dev-only.nix).filesDrv;
          packages.files-all-envs = (render ./tests/fixtures/all-envs.nix).filesDrv;

          checks.render-dev-only = snapshot "dev-only" 9 ./tests/expected/dev-only ./tests/fixtures/dev-only.nix;
          checks.render-all-envs = snapshot "all-envs" 15 ./tests/expected/all-envs ./tests/fixtures/all-envs.nix;

          # infra.enabled = false has to render nothing at all: reconcile
          # deletes infra/ first and writes managed files after, so a template
          # that still produced output would put the tree straight back.
          checks.disabled-renders-nothing = pkgs.runCommand "disabled-renders-nothing" { } ''
            drv=${(render ./tests/fixtures/disabled.nix).filesDrv}
            # Rooted at $drv, not $drv/infra: with pipefail on, a find over a
            # missing directory fails the whole check for the wrong reason.
            found=$(find "$drv" -path "$drv/infra/*" -type f | wc -l)
            if [ -e "$drv/.github/workflows/deploy-infra.yml" ]; then
              found=$((found + 1))
            fi
            if [ "$found" -ne 0 ]; then
              echo "infra.enabled = false still rendered $found file(s):" >&2
              find "$drv" -path "$drv/infra/*" -type f >&2
              exit 1
            fi
            touch $out
          '';

          checks.disabled-plan-retires-the-tree = pkgs.runCommand "disabled-plan-retires-the-tree" { } ''
            grep -q '"retiredTrees":\["infra"\]' ${(render ./tests/fixtures/disabled.nix).plan}
            grep -q '"retiredTrees":\[\]' ${(render ./tests/fixtures/dev-only.nix).plan}
            touch $out
          '';

          # Each environment is a separate gated template, so a repo that does
          # not select an environment must not get its directory at all.
          checks.unselected-envs-are-absent = pkgs.runCommand "unselected-envs-are-absent" { } ''
            for env in staging prod; do
              for f in account.hcl README.md terragrunt.stack.hcl; do
                if [ -e ${(render ./tests/fixtures/dev-only.nix).filesDrv}/infra/live/$env/$f ]; then
                  echo "infra.envs excludes $env but infra/live/$env/$f was rendered" >&2
                  exit 1
                fi
              done
            done
            touch $out
          '';

          # {{infraDir}} is just syntax that has to survive Jinja untouched.
          checks.just-recipes-keep-their-braces = pkgs.runCommand "just-recipes-keep-their-braces" { } ''
            grep -q 'terragrunt stack run --tf-path terraform --working-dir {{infraDir}} plan' ${(render ./tests/fixtures/dev-only.nix).filesDrv}/justfile
            touch $out
          '';

          # The state bucket and the owner tag are three-deep: variables.hcl,
          # then repo.nix, then a derived name. Only terragrunt can tell us the
          # chain actually resolves that way.
          checks.variables-hcl-overrides-win = pkgs.runCommand "variables-hcl-overrides-win"
            { nativeBuildInputs = [ pkgs.terragrunt ]; }
            ''
              export HOME=$TMPDIR
              cp -r ${(render ./tests/fixtures/dev-only.nix).filesDrv}/infra .
              chmod -R +w infra
              unit=infra/live/dev/aws/common/ecr
              mkdir -p $unit
              cat > $unit/terragrunt.hcl <<'EOF'
              include "root" {
                path = find_in_parent_folders("root.hcl")
              }
              inputs = { asset_name = "ecr" }
              EOF

              rendered() { (cd $unit && terragrunt render --json --out -); }

              # No variables.hcl: the fixture sets no infra.stateBucket either,
              # so both fall through to the derived name and the repo.nix email.
              rendered | grep -q '"bucket":"fomiller-dev-terraform-state"'
              rendered | grep -q 'forrestmillerj@gmail.com'

              cat > infra/live/variables.hcl <<'EOF'
              locals {
                bucket      = "override-bucket"
                owner_email = "someone@else"
              }
              EOF
              rendered | grep -q '"bucket":"override-bucket"'
              rendered | grep -q 'someone@else'
              ! rendered | grep -q 'forrestmillerj@gmail.com'

              # Nearest file wins, and a file may set only one of the keys.
              cat > infra/live/dev/variables.hcl <<'EOF'
              locals {
                bucket = "per-env-bucket"
              }
              EOF
              rendered | grep -q '"bucket":"per-env-bucket"'
              rendered | grep -q 'forrestmillerj@gmail.com'

              touch $out
            '';

          checks.rendered-justfile-parses = pkgs.runCommand "rendered-justfile-parses"
            { nativeBuildInputs = [ pkgs.just ]; }
            ''
              mkdir -p repo && cd repo
              cp ${(render ./tests/fixtures/dev-only.nix).filesDrv}/justfile .
              chmod +w justfile
              just --list
              just --evaluate >/dev/null

              # The exact shape gh-actions calls. An undeclared infraDir fails
              # here with "overridden on the command line but not present in
              # justfile", which is how this shipped broken. --dry-run resolves
              # the recipe without needing doppler or terragrunt on PATH.
              just --dry-run infraDir=infra/live/prod plan-all 2>&1 \
                | grep -q -- '--working-dir infra/live/prod plan'
              just --dry-run infraDir=infra/live/prod apply-all >/dev/null
              touch $out
            '';

          checks.rendered-workflows-lint = pkgs.runCommand "rendered-workflows-lint"
            { nativeBuildInputs = [ pkgs.actionlint ]; }
            ''
              mkdir -p repo && cd repo
              cp -r ${(render ./tests/fixtures/all-envs.nix).filesDrv}/.github .
              chmod -R +w .github
              # Bare `actionlint` walks up looking for a git repo. There isn't
              # one in a build sandbox, so name the files.
              actionlint .github/workflows/*.yml
              touch $out
            '';
        })
    // {
      pack = import ./pack.nix;
    };
}
