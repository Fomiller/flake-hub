{
  description = "renovate: the shared preset that bumps flake-hub pack pins";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem
      (system:
        let pkgs = nixpkgs.legacyPackages.${system}; in
        {
          checks.renovate-preset = pkgs.runCommand "renovate-preset-tests"
            { nativeBuildInputs = [ pkgs.python3Packages.pytest ]; }
            ''
              cp -r ${./.} renovate && chmod -R +w renovate && cd renovate
              pytest tests/preset_test.py -q
              touch $out
            '';
        });
}
