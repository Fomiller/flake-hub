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

          # Also a check, not only an app: the eval units are the whole proof
          # that the engine's guards fire, so `nix flake check` has to run them.
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

          # Building these is how you refresh the snapshots after a template
          # change: `nix build .#files-default` and diff against tests/expected.
          packages.files-default = (golden-engine.lib.mkGolden { packs = [ self.pack ]; } pkgs (import ./tests/fixtures/repo.nix)).filesDrv;
          packages.files-customized = (golden-engine.lib.mkGolden { packs = [ self.pack ]; } pkgs (import ./tests/fixtures/repo-customized.nix)).filesDrv;

          checks.render-snapshot =
            let
              golden = golden-engine.lib.mkGolden { packs = [ self.pack ]; } pkgs (import ./tests/fixtures/repo.nix);
            in
            pkgs.runCommand "render-snapshot" { } ''
              diff -ru ${./tests/expected/default} ${golden.filesDrv}
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

          checks.render-customized =
            let
              golden = golden-engine.lib.mkGolden { packs = [ self.pack ]; } pkgs (import ./tests/fixtures/repo-customized.nix);
            in
            pkgs.runCommand "render-customized" { nativeBuildInputs = [ pkgs.python3 ]; } ''
              mkdir -p scratch && cd scratch
              python3 ${golden-engine.src}/lib/reconcile.py \
                --files ${golden.filesDrv} --plan ${golden.plan} --root .
              cd ..
              diff -ru ${./tests/expected/customized} scratch
              touch $out
            '';

          # Builds nothing but filesDrv, against a repo.nix whose plan is
          # invalid. If instantiating filesDrv succeeds, planChecksum has
          # stopped forcing the plan guards and this check throws.
          checks.plan-guard-forces-on-files-drv =
            let
              golden = golden-engine.lib.mkGolden { packs = [ self.pack ]; } pkgs (import ./tests/fixtures/repo-invalid.nix);
              attempt = builtins.tryEval (builtins.seq golden.filesDrv.drvPath true);
            in
            if attempt.success
            then throw "plan-guard: building filesDrv alone did not force the plan guard (planChecksum missing from mkGolden.nix?)"
            else pkgs.runCommand "plan-guard-forces-on-files-drv" { } "touch $out";

          apps.init = {
            type = "app";
            program = toString (pkgs.writeShellScript "golden-init" ''
              exec ${pkgs.python3}/bin/python3 ${./init.py} \
                --versions ${./pack-versions.nix} "$@"
            '');
          };

          checks.init = pkgs.runCommand "init-tests"
            { nativeBuildInputs = [ pkgs.python3Packages.pytest ]; }
            ''
              cp -r ${./.} base && chmod -R +w base && cd base
              pytest tests/init_test.py -q
              touch $out
            '';

          checks.generate-app =
            let
              golden = golden-engine.lib.mkGolden { packs = [ self.pack ]; } pkgs (import ./tests/fixtures/repo.nix);
            in
            pkgs.runCommand "generate-app" { } ''
              mkdir -p happy && cd happy
              cp ${./tests/fixtures/repo.nix} repo.nix
              ${golden.generateApp.program}
              test -f .gitignore
              grep -q 'GENERATED FILE' .gitignore
              cd ..

              mkdir -p noguard && cd noguard
              set +e
              ${golden.generateApp.program} 2>stderr.log
              status=$?
              set -e
              if [ "$status" -eq 0 ]; then
                echo "expected generateApp to fail without repo.nix" >&2
                exit 1
              fi
              grep -q 'run this from the repo root' stderr.log

              touch $out
            '';
        })
    // {
      pack = import ./pack.nix;
    };
}
