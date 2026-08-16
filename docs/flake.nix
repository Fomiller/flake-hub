{
  description = "flake-hub docs: the mdbook, and the generated config reference";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    golden-base.url = "path:../golden-base";
    golden-github.url = "path:../golden-github";
    golden-service.url = "path:../golden-service";
    golden-infra.url = "path:../golden-infra";
    golden-argocd.url = "path:../golden-argocd";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, golden-base, golden-github, golden-service, golden-infra, golden-argocd, flake-utils }:
    flake-utils.lib.eachDefaultSystem
      (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          genReference = import ./gen-reference.nix { inherit (pkgs) lib; };

          packs = [
            golden-base.pack
            golden-github.pack
            golden-service.pack
            golden-infra.pack
            golden-argocd.pack
          ];

          # golden-engine has no schema and no files, so it has no generated
          # region. Its page is prose only.
          tables = pkgs.writeText "reference-tables.json"
            (builtins.toJSON (builtins.listToAttrs
              (map (p: { name = p.name; value = genReference p; }) packs)));

          runGenerator = ''
            ${pkgs.python3}/bin/python3 ${./gen_reference.py} \
              --tables ${tables} \
              --pages-dir "$1"
          '';
        in
        {
          apps.gen-reference = {
            type = "app";
            program = toString (pkgs.writeShellScript "gen-reference" ''
              set -euo pipefail
              if [ ! -d docs/src/flakes ]; then
                echo "gen-reference: run this from the repo root" >&2
                exit 1
              fi
              set -- docs/src/flakes
              ${runGenerator}
            '');
          };

          checks.gen-reference-tests = pkgs.runCommand "gen-reference-tests"
            { nativeBuildInputs = [ pkgs.python3Packages.pytest ]; }
            ''
              cp -r ${./.} docs && chmod -R +w docs && cd docs
              pytest tests -q
              touch $out
            '';

          checks.reference-is-current = pkgs.runCommand "reference-is-current" { } ''
            cp -r ${./src/flakes} pages && chmod -R +w pages
            set -- pages
            ${runGenerator}
            if ! diff -r ${./src/flakes} pages; then
              echo "" >&2
              echo "The generated reference is stale." >&2
              echo "Run 'nix run ./docs#gen-reference' and commit the result." >&2
              exit 1
            fi
            touch $out
          '';

          checks.book-builds = pkgs.runCommand "book-builds"
            { nativeBuildInputs = [ pkgs.mdbook ]; }
            ''
              cp -r ${./.} docs && chmod -R +w docs
              mdbook build docs
              test -f docs/book/index.html
              touch $out
            '';
        });
}
