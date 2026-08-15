{
  description = "golden-base: files every repo gets, whatever it is";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    golden-engine.url = "path:../golden-engine";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, golden-engine, flake-utils }:
    flake-utils.lib.eachDefaultSystem
      (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          evalUnits = pkgs.writeText "eval_units.nix" ''
            import ${./tests/eval_units.nix} {
              pkgs = import ${nixpkgs} { system = "${system}"; };
              engineSrc = "${golden-engine.src}";
              fixtures = "${./tests/fixtures}";
            }
          '';
        in
        {
          apps.test-eval = {
            type = "app";
            program = toString (pkgs.writeShellScript "test-eval" ''
              exec ${pkgs.nix-unit}/bin/nix-unit \
                --eval-store auto \
                ${evalUnits}
            '');
          };

          checks.render-snapshot =
            let
              golden = golden-engine.lib.mkGolden { packs = [ self.pack ]; } pkgs (import ./tests/fixtures/repo.nix);
            in
            pkgs.runCommand "render-snapshot" { } ''
              diff -ru ${./tests/expected/gitignore-default} ${golden.filesDrv}
              touch $out
            '';

          checks.engine-python = pkgs.runCommand "engine-python-tests"
            { nativeBuildInputs = [ pkgs.python3Packages.pytest ]; }
            ''
              cp -r ${golden-engine.src} engine
              chmod -R +w engine
              cd engine
              pytest tests -q
              touch $out
            '';

          checks.generate-is-idempotent =
            let
              golden = golden-engine.lib.mkGolden { packs = [ self.pack ]; } pkgs (import ./tests/fixtures/repo.nix);
            in
            pkgs.runCommand "generate-is-idempotent" { nativeBuildInputs = [ pkgs.python3 ]; } ''
              mkdir -p repo && cd repo
              python3 ${golden-engine.src}/lib/reconcile.py \
                --files ${golden.filesDrv} --plan ${golden.plan} --root .
              find . -type f | sort > ../first
              sha256sum $(find . -type f | sort) > ../first-sums

              python3 ${golden-engine.src}/lib/reconcile.py \
                --files ${golden.filesDrv} --plan ${golden.plan} --root . | tee ../second-log
              sha256sum $(find . -type f | sort) > ../second-sums

              diff ../first-sums ../second-sums
              grep -q '0 change(s)' ../second-log
              touch $out
            '';
        })
    // {
      pack = import ./pack.nix;
    };
}
