{
  description = "golden-github: the files GitHub itself interprets";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    golden-engine.url = "path:../golden-engine";
    golden-base.url = "path:../golden-base";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, golden-engine, golden-base, flake-utils }:
    flake-utils.lib.eachDefaultSystem
      (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          golden = golden-engine.lib.mkGolden
            {
              packs = [ golden-base.pack self.pack ];
            }
            pkgs
            (import ./tests/fixtures/repo.nix);
          ownJob = golden-engine.lib.mkGolden
            {
              packs = [ golden-base.pack self.pack ];
            }
            pkgs
            (import ./tests/fixtures/own-job.nix);
          emptyOwners = golden-engine.lib.mkGolden
            {
              packs = [ golden-base.pack self.pack ];
            }
            pkgs
            (import ./tests/fixtures/empty-owners.nix);
          gatesOff = golden-engine.lib.mkGolden
            {
              packs = [ golden-base.pack self.pack ];
            }
            pkgs
            (import ./tests/fixtures/gates-off.nix);
          publish = golden-engine.lib.mkGolden
            {
              packs = [ golden-base.pack self.pack ];
            }
            pkgs
            (import ./tests/fixtures/publish.nix);
          evalUnits = pkgs.writeText "eval_units.nix" ''
            import ${./tests/eval_units.nix} {
              pkgs = import ${nixpkgs} { system = "${system}"; };
              engineSrc = "${golden-engine.src}";
              basePack = import ${golden-base.outPath}/pack.nix;
              githubPack = import ${self.outPath}/pack.nix;
            }
          '';
        in
        {
          # Building this is how you refresh the snapshot after a template
          # change: `nix build .#files-default` and diff against tests/expected.
          packages.files-default = golden.filesDrv;

          # Also a check, not only an app: without this the cases run only when
          # someone remembers to, and `nix flake check` reports green regardless.
          checks.eval-units = pkgs.runCommand "eval-units"
            { nativeBuildInputs = [ pkgs.nix-unit ]; }
            ''
              # nix-unit starts an evaluator, which wants somewhere to put a
              # profile and a cache. Inside the sandbox /nix/var is read-only.
              export HOME=$TMPDIR
              export NIX_STATE_DIR=$TMPDIR/nix/var/nix
              export XDG_CACHE_HOME=$TMPDIR/cache
              nix-unit ${evalUnits}
              touch $out
            '';

          # The snapshot covers only this pack's own paths. golden-base's files
          # are already covered by golden-base's snapshot; asserting them here
          # would mean two places to update for one change.
          checks.render-snapshot = pkgs.runCommand "github-render-snapshot" { } ''
            # The loop only visits files the expected tree already has, so an
            # emptied expected tree would pass silently. The count is the guard.
            found=$(cd ${./tests/expected/default} && find . -type f | wc -l)
            if [ "$found" -ne 4 ]; then
              echo "expected tree holds $found files, not 4" >&2
              exit 1
            fi
            for f in $(cd ${./tests/expected/default} && find . -type f | sed 's|^\./||'); do
              diff -u "${./tests/expected/default}/$f" "${golden.filesDrv}/$f"
            done
            touch $out
          '';

          # golden-base's header names golden-base. If both packs ever shipped
          # the partial under one name this would render the wrong pack name.
          checks.each-pack-stamps-its-own-header = pkgs.runCommand "each-pack-stamps-its-own-header" { } ''
            grep -q 'managed by flake-hub (golden-base)' ${golden.filesDrv}/.gitignore
            grep -q 'managed by flake-hub (golden-github)' ${golden.filesDrv}/.github/CODEOWNERS
            touch $out
          '';

          # `jobs:` with no children is invalid YAML, so a repo that contributes
          # no jobs gets no ci.yml at all. The fixture selects no service pack,
          # so ci.jobs is empty here.
          checks.no-jobs-means-no-ci-workflow = pkgs.runCommand "no-jobs-means-no-ci-workflow" { } ''
            if [ -e ${golden.filesDrv}/.github/workflows/ci.yml ]; then
              echo "ci.jobs is empty but ci.yml was still rendered" >&2
              exit 1
            fi
            touch $out
          '';

          # `stepsFrom` is how golden-service asks for language steps. A repo
          # writing its own job has no reason to set it, and under
          # --undefined strict a bare comparison against it raises.
          checks.a-job-without-stepsFrom-renders = pkgs.runCommand "a-job-without-stepsFrom-renders"
            { nativeBuildInputs = [ pkgs.actionlint ]; }
            ''
              mkdir -p repo && cd repo
              cp -r ${ownJob.filesDrv}/.github .
              chmod -R +w .github
              grep -q 'make docs' .github/workflows/ci.yml
              actionlint .github/workflows/*.yml
              touch $out
            '';

          # A rule with a pattern and no owners means "no review required for
          # anything" — the opposite of what this pack is for. Emit no rule.
          checks.empty-codeowners-emits-no-rule = pkgs.runCommand "empty-codeowners-emits-no-rule" { } ''
            if grep -q '^\*' ${emptyOwners.filesDrv}/.github/CODEOWNERS; then
              echo "codeowners is empty but CODEOWNERS still carries a rule" >&2
              exit 1
            fi
            touch $out
          '';

          # Each gate has to remove its own file and nothing else, so the same
          # fixture proves all three at once.
          checks.gates-off-remove-their-files = pkgs.runCommand "gates-off-remove-their-files" { } ''
            for f in renovate.json AGENTS.md .github/workflows/ci.yml; do
              if [ -e ${gatesOff.filesDrv}/$f ]; then
                echo "$f was rendered with its gate off" >&2
                exit 1
              fi
            done
            # CODEOWNERS has no gate, so it is the control: the fixture is not
            # simply rendering nothing.
            test -e ${gatesOff.filesDrv}/.github/CODEOWNERS
            touch $out
          '';

          # Both publish workflows are off unless a repo asks for them. A repo
          # that ships no image has no ECR repository to push to, so a workflow
          # that ran would fail on every push to main.
          checks.publish-is-off-by-default = pkgs.runCommand "publish-is-off-by-default" { } ''
            for f in publish-image.yml publish-chart.yml; do
              if [ -e ${golden.filesDrv}/.github/workflows/$f ]; then
                echo "$f was rendered without github.publish* set" >&2
                exit 1
              fi
            done
            touch $out
          '';

          # The workflows are only useful if the repo's own values reach the
          # reusable workflow's inputs, and actionlint is what catches a
          # rendered file GitHub would reject.
          checks.publish-workflows-render = pkgs.runCommand "publish-workflows-render"
            { nativeBuildInputs = [ pkgs.actionlint ]; }
            ''
              mkdir -p repo && cd repo
              cp -r ${publish.filesDrv}/.github .
              chmod -R +w .github
              grep -q 'repository: publish-repo' .github/workflows/publish-image.yml
              grep -q 'platforms: linux/amd64,linux/arm64' .github/workflows/publish-image.yml
              # Neither workflow names a role or a region. The reusable workflow
              # reads AWS_OIDC_ROLE_ARN and defaults the region, so a rendered
              # file that passes either has put the account back in every repo.
              for f in publish-image.yml publish-chart.yml; do
                if grep -q 'role-to-assume\|aws-region' ".github/workflows/$f"; then
                  echo "$f names a role or region; both belong to the reusable workflow" >&2
                  exit 1
                fi
              done
              # The tag prefix is what separates the image's release stream from
              # the chart's. Rendering the bare name would make the image claim
              # the chart's tags.
              grep -q 'release-tag-prefix: publish-repo-v' .github/workflows/publish-image.yml
              grep -q 'release-versioning: true' .github/workflows/publish-chart.yml
              # A moving tag cannot be pushed twice to an immutable repository.
              if grep -q ':latest' .github/workflows/publish-image.yml; then
                echo "publish-image.yml publishes a moving tag" >&2
                exit 1
              fi
              # A manual run off a feature branch cuts a candidate; off the
              # default branch it cuts the stable release. Losing either half
              # would publish a stable version from an unmerged branch.
              for f in publish-image.yml publish-chart.yml; do
                grep -q 'workflow_dispatch' ".github/workflows/$f"
                grep -q 'release-rc:.*ref_name != .*default_branch' ".github/workflows/$f"
              done
              actionlint .github/workflows/*.yml
              touch $out
            '';

          checks.rendered-workflows-lint = pkgs.runCommand "rendered-workflows-lint"
            { nativeBuildInputs = [ pkgs.actionlint ]; }
            ''
              mkdir -p repo && cd repo
              cp -r ${golden.filesDrv}/.github .
              chmod -R +w .github
              # Bare `actionlint` walks up looking for a git repo. There isn't
              # one in a build sandbox, so name the files.
              actionlint .github/workflows/*.yml
              touch $out
            '';

          apps.test-eval = {
            type = "app";
            program = toString (pkgs.writeShellScript "test-eval" ''
              exec ${pkgs.nix-unit}/bin/nix-unit \
                --eval-store auto \
                ${evalUnits}
            '');
          };
        })
    // {
      pack = import ./pack.nix;
    };
}
