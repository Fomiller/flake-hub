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
          # The snapshot covers only this pack's own paths. golden-base's files
          # are already covered by golden-base's snapshot; asserting them here
          # would mean two places to update for one change.
          checks.render-snapshot = pkgs.runCommand "github-render-snapshot" { } ''
            for f in $(cd ${./tests/expected/default} && find . -type f | sed 's|^\./||'); do
              diff -u "${./tests/expected/default}/$f" "${golden.filesDrv}/$f"
            done
            touch $out
          '';

          # golden-base's header names golden-base. If both packs ever shipped
          # the partial under one name this would render the wrong pack name.
          checks.each-pack-stamps-its-own-header = pkgs.runCommand "each-pack-stamps-its-own-header" { } ''
            grep -q 'managed by flake-hub (golden-base)' ${golden.filesDrv}/.gitignore
            grep -q 'managed by flake-hub (golden-github)' ${golden.filesDrv}/CODEOWNERS
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
