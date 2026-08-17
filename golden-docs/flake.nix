{
  description = "golden-docs: an mdbook site and the workflow that publishes it";

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
          render = fixture: golden-engine.lib.mkGolden
            {
              packs = [ golden-base.pack self.pack ];
            }
            pkgs
            (import fixture);

          golden = render ./tests/fixtures/repo.nix;
          minimal = render ./tests/fixtures/minimal.nix;
          disabled = render ./tests/fixtures/disabled.nix;
        in
        {
          # The vendored stylesheet is the trap here: it is a plain file copy,
          # so without a gate it would be written straight back after reconcile
          # deletes the tree.
          checks.disabled-renders-nothing = pkgs.runCommand "docs-disabled-renders-nothing" { } ''
            drv=${disabled.filesDrv}
            found=$(find "$drv" -path "$drv/docs/*" -type f | wc -l)
            if [ -e "$drv/.github/workflows/docs.yml" ]; then
              found=$((found + 1))
            fi
            if [ "$found" -ne 0 ]; then
              echo "docs.enabled = false still rendered $found file(s)" >&2
              find "$drv" -path "$drv/docs/*" -type f >&2
              exit 1
            fi
            grep -q '"retiredTrees":\["docs"\]' ${disabled.plan}
            touch $out
          '';

          # Building this is how you refresh the snapshot after a template
          # change: `nix build .#files-default` and diff against tests/expected.
          packages.files-default = golden.filesDrv;

          # The snapshot covers only this pack's own paths. golden-base's files
          # are already covered by golden-base's snapshot.
          checks.render-snapshot = pkgs.runCommand "docs-render-snapshot" { } ''
            # The loop only visits files the expected tree already has, so an
            # emptied expected tree would pass silently. The count is the guard.
            found=$(cd ${./tests/expected/default} && find . -type f | wc -l)
            if [ "$found" -ne 5 ]; then
              echo "expected tree holds $found files, not 5" >&2
              exit 1
            fi
            for f in $(cd ${./tests/expected/default} && find . -type f | sed 's|^\./||'); do
              diff -u "${./tests/expected/default}/$f" "${golden.filesDrv}/$f"
            done
            touch $out
          '';

          # The point of the pack is a book that builds. A template change that
          # writes a book.toml mdbook rejects has to fail here, not in the
          # consumer's first deploy.
          checks.seeded-book-builds = pkgs.runCommand "seeded-book-builds"
            { nativeBuildInputs = [ pkgs.mdbook ]; }
            ''
              cp -r ${golden.filesDrv}/docs . && chmod -R +w docs
              mdbook build docs
              test -f docs/book/index.html
              grep -q 'docs-repo' docs/book/index.html
              # The flavour is a class on <html>, and the colours come from the
              # vendored stylesheet. Either one missing means an unstyled book.
              grep -q 'class="frappe' docs/book/index.html
              test -f docs/book/theme/catppuccin.css
              touch $out
            '';

          # The flavour is a knob, so a repo that picks another one has to get
          # it. The default is easy to hardcode by accident.
          checks.minimal-book-builds = pkgs.runCommand "minimal-book-builds"
            { nativeBuildInputs = [ pkgs.mdbook ]; }
            ''
              cp -r ${minimal.filesDrv}/docs . && chmod -R +w docs
              mdbook build docs
              test -f docs/book/index.html
              grep -q 'class="mocha' docs/book/index.html
              touch $out
            '';

          # Publishing is opt-out, so the gate is the only thing standing
          # between a private repo and a Pages deployment it never asked for.
          checks.publish-off-emits-no-workflow = pkgs.runCommand "publish-off-emits-no-workflow" { } ''
            if [ -e ${minimal.filesDrv}/.github/workflows/docs.yml ]; then
              echo "docs.publish is false but docs.yml was still rendered" >&2
              exit 1
            fi
            touch $out
          '';

          # An empty repoUrl must drop both lines rather than emit a link to
          # nowhere. mdbook renders an edit button from the template as-is.
          checks.no-repo-url-omits-links = pkgs.runCommand "no-repo-url-omits-links" { } ''
            if grep -q 'edit-url-template\|git-repository-url' ${minimal.filesDrv}/docs/book.toml; then
              echo "docs.repoUrl is empty but book.toml still carries a link" >&2
              exit 1
            fi
            touch $out
          '';

          checks.rendered-justfile-parses = pkgs.runCommand "rendered-justfile-parses"
            { nativeBuildInputs = [ pkgs.just ]; }
            ''
              mkdir -p repo && cd repo
              cp ${golden.filesDrv}/justfile .
              chmod +w justfile
              just --list
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
        })
    // {
      pack = import ./pack.nix;
    };
}
