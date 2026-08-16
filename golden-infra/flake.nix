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

          checks.render-dev-only = snapshot "dev-only" 6 ./tests/expected/dev-only ./tests/fixtures/dev-only.nix;
          checks.render-all-envs = snapshot "all-envs" 10 ./tests/expected/all-envs ./tests/fixtures/all-envs.nix;

          # Each environment is a separate gated template, so a repo that does
          # not select an environment must not get its directory at all.
          checks.unselected-envs-are-absent = pkgs.runCommand "unselected-envs-are-absent" { } ''
            for env in staging prod; do
              for f in account.hcl README.md; do
                if [ -e ${(render ./tests/fixtures/dev-only.nix).filesDrv}/infra/live/$env/$f ]; then
                  echo "infra.envs excludes $env but infra/live/$env/$f was rendered" >&2
                  exit 1
                fi
              done
            done
            touch $out
          '';

          # {{env}} is just syntax that has to survive Jinja untouched.
          checks.just-recipes-keep-their-braces = pkgs.runCommand "just-recipes-keep-their-braces" { } ''
            grep -q 'cd infra/live/{{env}} && terragrunt run-all plan' ${(render ./tests/fixtures/dev-only.nix).filesDrv}/justfile
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
