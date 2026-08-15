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
        in
        {
          apps.test-eval = {
            type = "app";
            program = toString (pkgs.writeShellScript "test-eval" ''
              exec ${pkgs.nix-unit}/bin/nix-unit \
                --eval-store auto \
                ${./tests/eval_units.nix}
            '');
          };
        })
    // {
      pack = import ./pack.nix;
    };
}
