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
          snapshot = name: expected: fixture:
            pkgs.runCommand "render-${name}" { } ''
              for f in $(cd ${expected} && find . -type f | sed 's|^\./||'); do
                diff -u "${expected}/$f" "${(render fixture).filesDrv}/$f"
              done
              touch $out
            '';
        in
        {
          checks.render-go = snapshot "go" ./tests/expected/go ./tests/fixtures/go.nix;
          checks.render-rust = snapshot "rust" ./tests/expected/rust ./tests/fixtures/rust.nix;

          # service.binary has no pack default: it falls back to the repo name,
          # which packs cannot see. This covers the case where it is set.
          checks.render-named-binary = snapshot "named-binary" ./tests/expected/binary ./tests/fixtures/binary.nix;

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
