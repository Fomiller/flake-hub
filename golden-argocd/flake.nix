{
  description = "golden-argocd: the chart a service ships and the workflows that publish it";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    golden-engine.url = "path:../golden-engine";
    golden-base.url = "path:../golden-base";
    golden-github.url = "path:../golden-github";
    golden-service.url = "path:../golden-service";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, golden-engine, golden-base, golden-github, golden-service, flake-utils }:
    flake-utils.lib.eachDefaultSystem
      (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          golden = golden-engine.lib.mkGolden
            {
              packs = [ golden-base.pack golden-github.pack golden-service.pack self.pack ];
            }
            pkgs
            (import ./tests/fixtures/svc.nix);

          # The same repo without golden-service. Nothing then supplies
          # service.port, and this pack's required-key check must catch it.
          # `language` is dropped because it is golden-service's key too, and an
          # unknown-key error would mask the one under test.
          withoutService = golden-engine.lib.mkGolden
            {
              packs = [ golden-base.pack golden-github.pack self.pack ];
            }
            pkgs
            (builtins.removeAttrs (import ./tests/fixtures/svc.nix) [ "language" ]);
        in
        {
          packages.files = golden.filesDrv;

          checks.render-svc = pkgs.runCommand "render-svc" { } ''
            # The loop only visits files the expected tree already has, so an
            # emptied expected tree would pass silently. The count is the guard.
            found=$(cd ${./tests/expected/svc} && find . -type f | wc -l)
            if [ "$found" -ne 12 ]; then
              echo "expected tree holds $found files, not 12" >&2
              exit 1
            fi
            for f in $(cd ${./tests/expected/svc} && find . -type f | sed 's|^\./||'); do
              diff -u "${./tests/expected/svc}/$f" "${golden.filesDrv}/$f"
            done
            touch $out
          '';

          # A text snapshot can be satisfied by a chart Helm rejects.
          checks.chart-renders = pkgs.runCommand "chart-renders"
            { nativeBuildInputs = [ pkgs.kubernetes-helm ]; }
            ''
              cp -r ${golden.filesDrv}/helm/svc-go chart && chmod -R +w chart
              helm template test ./chart > rendered.yaml
              helm lint ./chart
              grep -q 'containerPort: 8080' rendered.yaml
              grep -q 'name: test-svc-go-chart' rendered.yaml

              # The chart is svc-go-chart, but no resource should say so. The
              # suffix names the artifact, not the workload. Helm's own
              # `# Source:` comments carry the chart directory and are exempt.
              if grep -v '^#' rendered.yaml | grep -q -- '-chart'; then
                grep -v '^#' rendered.yaml | grep -n -- '-chart' >&2
                echo "the chart's -chart suffix leaked into the rendered resources" >&2
                exit 1
              fi

              # The overlay base values set fullnameOverride. A helper that
              # ignores it makes that file a lie, and renders fine either way.
              helm template test ./chart --set fullnameOverride=pinned > override.yaml
              grep -q 'name: pinned' override.yaml
              touch $out
            '';

          # An overlay that names a values file which is not there fails only
          # when Argo CD tries to sync it, which is a long way from here.
          checks.overlay-values-files-exist = pkgs.runCommand "overlay-values-files-exist"
            { nativeBuildInputs = [ pkgs.yq-go ]; }
            ''
              cd ${golden.filesDrv}/argocd/overlays
              for k in */kustomization.yaml; do
                dir=$(dirname "$k")
                for f in $(yq -r '.helmCharts[].valuesFile, .helmCharts[].additionalValuesFiles[]' "$k"); do
                  if [ ! -e "$dir/$f" ]; then
                    echo "$k names $f, which does not exist" >&2
                    exit 1
                  fi
                done
              done
              touch $out
            '';

          # The publish workflow takes the ECR repository name from Chart.yaml,
          # and the overlay pulls that name back out of the registry. If the two
          # drift, Argo CD asks for a chart nobody published.
          checks.overlay-chart-name-matches = pkgs.runCommand "overlay-chart-name-matches"
            { nativeBuildInputs = [ pkgs.yq-go ]; }
            ''
              cd ${golden.filesDrv}
              chart=$(yq -r '.name' helm/*/Chart.yaml)
              case "$chart" in
                *-chart) ;;
                *) echo "chart is named '$chart'; it must end in -chart" >&2; exit 1 ;;
              esac
              for k in argocd/overlays/*/kustomization.yaml; do
                for n in $(yq -r '.helmCharts[].name' "$k"); do
                  if [ "$n" != "$chart" ]; then
                    echo "$k asks for chart '$n' but the chart is named '$chart'" >&2
                    exit 1
                  fi
                done
              done
              touch $out
            '';

          # An overlay for an unselected environment must not land at all.
          checks.unselected-env-has-no-overlay = pkgs.runCommand "unselected-env-has-no-overlay" { } ''
            if [ -e ${golden.filesDrv}/argocd/overlays/staging ]; then
              echo "staging is not in deploy.envs but its overlay was rendered" >&2
              exit 1
            fi
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

          checks.without-service-pack-fails = pkgs.runCommand "without-service-pack-fails" { } ''
            ${pkgs.lib.optionalString
              (builtins.tryEval (builtins.deepSeq withoutService.mergedConfig null)).success
              "echo 'golden-argocd evaluated without golden-service; service.port went unchecked' >&2; exit 1"}
            touch $out
          '';
        })
    // {
      pack = import ./pack.nix;
    };
}
