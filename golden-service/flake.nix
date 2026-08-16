{
  description = "golden-service: the files a compiled service needs";

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

          # Covers only this pack's own paths. golden-base and golden-github
          # already snapshot theirs; asserting them here would mean two places
          # to update for one change.
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
          # change: `nix build .#files-go` and diff against tests/expected.
          packages.files-go = (render ./tests/fixtures/go.nix).filesDrv;
          packages.files-rust = (render ./tests/fixtures/rust.nix).filesDrv;
          packages.files-binary = (render ./tests/fixtures/binary.nix).filesDrv;
          packages.files-library = (render ./tests/fixtures/library.nix).filesDrv;

          checks.render-go = snapshot "go" 3 ./tests/expected/go ./tests/fixtures/go.nix;
          checks.render-rust = snapshot "rust" 3 ./tests/expected/rust ./tests/fixtures/rust.nix;

          # service.binary has no pack default: it falls back to the repo name,
          # which packs cannot see. This covers the case where it is set.
          checks.render-named-binary = snapshot "named-binary" 3 ./tests/expected/binary ./tests/fixtures/binary.nix;

          # A library still builds, tests and lints. Only the Dockerfile is gated.
          checks.render-library = snapshot "library" 2 ./tests/expected/library ./tests/fixtures/library.nix;

          # golden-github's own lint check never sees ci.yml, because a repo with
          # no service pack contributes no jobs and gets no workflow.
          checks.rendered-ci-lint = pkgs.runCommand "rendered-ci-lint"
            { nativeBuildInputs = [ pkgs.actionlint ]; }
            ''
              mkdir -p repo && cd repo
              cp -r ${(render ./tests/fixtures/go.nix).filesDrv}/.github .
              chmod -R +w .github
              # Bare `actionlint` walks up looking for a git repo. There isn't
              # one in a build sandbox, so name the files.
              actionlint .github/workflows/*.yml
              touch $out
            '';

          # Recipe bodies are assembled from pack defaults and the language
          # registry, so a bad one is only visible once `just` parses the result.
          checks.rendered-justfile-parses = pkgs.runCommand "rendered-justfile-parses"
            { nativeBuildInputs = [ pkgs.just ]; }
            ''
              mkdir -p repo && cd repo
              cp ${(render ./tests/fixtures/go.nix).filesDrv}/justfile .
              chmod +w justfile
              just --list
              just --evaluate >/dev/null
              touch $out
            '';

          checks.library-has-no-dockerfile =
            pkgs.runCommand "library-has-no-dockerfile" { } ''
              if [ -e ${(render ./tests/fixtures/library.nix).filesDrv}/Dockerfile ]; then
                echo "service.container = false still produced a Dockerfile" >&2
                exit 1
              fi
              touch $out
            '';
        })
    // {
      pack = import ./pack.nix;
    };
}
