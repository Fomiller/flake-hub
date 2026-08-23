{
  description = "golden-argocd: the chart and overlays a service is bootstrapped with";

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
          disabled = golden-engine.lib.mkGolden
            {
              packs = [ golden-base.pack golden-github.pack golden-service.pack self.pack ];
            }
            pkgs
            (import ./tests/fixtures/disabled.nix);
        in
        {
          packages.files = golden.filesDrv;

          # A glob in `retired` deletes nothing and reports nothing, because
          # retired paths are unlinked literally while managed and scaffold are
          # matched against what the templates emit. This pack shipped one and
          # the file it was meant to remove simply stayed.
          checks.retired-glob-is-rejected =
            let
              globbed = self.pack // {
                ownership = self.pack.ownership // {
                  retired = self.pack.ownership.retired ++ [ "argocd/overlays/*/kustomization.yaml" ];
                };
              };
              golden = golden-engine.lib.mkGolden
                { packs = [ golden-base.pack golden-github.pack golden-service.pack globbed ]; }
                pkgs
                (import ./tests/fixtures/svc.nix);
              attempt = builtins.tryEval (builtins.seq golden.filesDrv.drvPath true);
            in
            if attempt.success
            then throw "retired-glob: a glob in `retired` was accepted; it would delete nothing"
            else pkgs.runCommand "retired-glob-is-rejected" { } "touch $out";

          # This pack owns nothing managed, and that is the whole point of it.
          # A path added back to `managed` would start reverting a repo's chart
          # on the next generate, which is the failure this change removed.
          checks.nothing-is-managed = pkgs.runCommand "nothing-is-managed" { } ''
            ${pkgs.lib.optionalString (self.pack.ownership.managed != [ ])
              "echo 'golden-argocd declares managed paths; it bootstraps only' >&2; exit 1"}
            touch $out
          '';

          # reconcile deletes argocd/ and helm/ before it writes anything, so a
          # template that still rendered would put the tree straight back.
          checks.disabled-renders-nothing = pkgs.runCommand "argocd-disabled-renders-nothing" { } ''
            drv=${disabled.filesDrv}
            found=$(find "$drv" \( -path "$drv/argocd/*" -o -path "$drv/helm/*" \) -type f | wc -l)
            if [ "$found" -ne 0 ]; then
              echo "argocd.enabled = false still rendered $found file(s)" >&2
              find "$drv" \( -path "$drv/argocd/*" -o -path "$drv/helm/*" \) -type f >&2
              exit 1
            fi
            grep -q '"retiredTrees":\["argocd","helm"\]' ${disabled.plan}
            touch $out
          '';

          checks.render-svc = pkgs.runCommand "render-svc" { } ''
            # The loop only visits files the expected tree already has, so an
            # emptied expected tree would pass silently. The count is the guard.
            found=$(cd ${./tests/expected/svc} && find . -type f | wc -l)
            if [ "$found" -ne 8 ]; then
              echo "expected tree holds $found files, not 8" >&2
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
              # A bare `grep -q` that fails says nothing at all, which turns a
              # red check into a guessing game. Every assertion names itself.
              assert_grep() {
                if ! grep -q -- "$1" "$2"; then
                  echo "expected '$1' in $2, and it is not there:" >&2
                  cat "$2" >&2
                  exit 1
                fi
              }

              cp -r ${golden.filesDrv}/helm/svc-go chart && chmod -R +w chart
              helm template test ./chart > rendered.yaml
              helm lint ./chart
              assert_grep 'containerPort: 8080' rendered.yaml
              assert_grep 'name: test-svc-go' rendered.yaml

              # The bootstrap chart has to deploy on its own, before the repo
              # has ever built an image. A default that pointed at the repo's
              # own ECR repository would render fine and never pull.
              assert_grep 'hashicorp/http-echo' rendered.yaml
              assert_grep 'listen=:8080' rendered.yaml

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
              assert_grep 'name: pinned' override.yaml

              # imagePullSecrets, both ways round.
              #
              # Empty must emit no key at all, not an empty list: a chart
              # rendered against a public registry should carry no reference to
              # a Secret that is not there. rendered.yaml above used the chart's
              # own values, where the list is empty.
              if grep -q 'imagePullSecrets' rendered.yaml; then
                grep -n 'imagePullSecrets' rendered.yaml >&2
                echo "imagePullSecrets is empty but the key was still rendered" >&2
                exit 1
              fi

              # Set must reach the pod spec. This is the half that decides
              # whether a private-registry pull works at all.
              helm template test ./chart --set 'imagePullSecrets[0].name=ecr-image-pull' > pull.yaml
              assert_grep 'imagePullSecrets:' pull.yaml
              assert_grep 'name: ecr-image-pull' pull.yaml

              # The overlays are what actually deploy, so the name they carry is
              # the one that has to match the Secret external-secrets creates.
              assert_grep 'name: ecr-image-pull' ${golden.filesDrv}/argocd/overlays/values.app.base.yaml
              touch $out
            '';

          # The base overlay must not pin an image. The chart's hello-world is
          # what makes a freshly bootstrapped repo deploy at all, and a base
          # value would override it with a tag nobody has pushed.
          checks.base-overlay-pins-no-image = pkgs.runCommand "base-overlay-pins-no-image" { } ''
            base=${golden.filesDrv}/argocd/overlays/values.app.base.yaml
            if grep -vE '^[[:space:]]*#' "$base" | grep -q '^[[:space:]]*image:'; then
              echo "values.app.base.yaml pins an image; the bootstrap chart can no longer deploy itself" >&2
              exit 1
            fi
            touch $out
          '';

          # Nothing in this repo names these files any more: the Application is
          # assembled in homelab, and it asks for
          # $values/argocd/overlays/values.app.base.yaml plus the environment's
          # own values.app.yaml. A missing one fails at sync time, which is a
          # long way from here, so the paths are asserted literally.
          checks.overlay-values-files-exist = pkgs.runCommand "overlay-values-files-exist" { } ''
            cd ${golden.filesDrv}/argocd/overlays
            if [ ! -e values.app.base.yaml ]; then
              echo "argocd/overlays/values.app.base.yaml is missing; every Application reads it" >&2
              exit 1
            fi
            for dir in */; do
              env="''${dir%/}"
              if [ ! -e "$env/values.app.yaml" ]; then
                echo "argocd/overlays/$env has no values.app.yaml" >&2
                exit 1
              fi
            done
            touch $out
          '';

          # The publish workflow takes the ECR repository name from Chart.yaml,
          # and homelab's ApplicationSet asks the registry for `<service>-chart`.
          # If the suffix goes missing, Argo CD asks for a chart nobody
          # published.
          checks.chart-name-has-the-suffix = pkgs.runCommand "chart-name-has-the-suffix"
            { nativeBuildInputs = [ pkgs.yq-go ]; }
            ''
              cd ${golden.filesDrv}
              chart=$(yq -r '.name' helm/*/Chart.yaml)
              case "$chart" in
                *-chart) ;;
                *) echo "chart is named '$chart'; it must end in -chart" >&2; exit 1 ;;
              esac
              touch $out
            '';

          # An overlay for an unselected environment must not land at all.
          checks.unselected-env-has-no-overlay = pkgs.runCommand "unselected-env-has-no-overlay" { } ''
            if [ -e ${golden.filesDrv}/argocd/overlays/staging ]; then
              echo "staging is not in argocd.environments but its overlay was rendered" >&2
              exit 1
            fi
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
