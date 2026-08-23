{
  name = "golden-argocd";
  templates = ./templates;
  partials = ./partials;
  defaults = {
    argocd = {
      enabled = true;
      environments = [ "dev" ];
    };
  };
  registry = { };
  # Nothing here is managed. The pack bootstraps a repo's chart and overlays
  # and then gets out of the way: what a service deploys is the service's
  # decision, and a managed file would revert it on whatever `nix run
  # .#generate` happens to run next.
  ownership = {
    managed = [ ];
    scaffold = [
      # The chart directory is named after the repo. The engine substitutes
      # {{ name }} in the template path, so the globs match one segment.
      "helm/*/Chart.yaml"
      "helm/*/values.yaml"
      "helm/*/templates/*"
      "argocd/overlays/values.app.base.yaml"
      "argocd/overlays/*/values.app.yaml"
    ];
    # deploy/chart was the layout before the chart moved under helm/<chart>/.
    #
    # The overlay kustomization is newer than that and was retired for a
    # different reason: nothing renders it. Argo CD cannot authenticate
    # kustomize against a private OCI registry, so a service is deployed from a
    # native Helm source that reads only the values files beside it. The
    # kustomization was left behind looking load-bearing.
    retired = [
      "deploy/chart/Chart.yaml"
      "deploy/chart/values.yaml"
      "deploy/chart/templates/deployment.yaml"
      "deploy/chart/templates/service.yaml"
      "deploy/chart/templates/helpers.tpl"
      #
      # One entry per environment, not a glob: retired paths are unlinked
      # literally, so a `*` here would match nothing and quietly leave the file
      # in place.
      "argocd/overlays/dev/kustomization.yaml"
      "argocd/overlays/staging/kustomization.yaml"
      "argocd/overlays/prod/kustomization.yaml"
    ];
  };
  # helm/ and argocd/ are this pack's whole surface, and both hold files the
  # repo edits, so turning the pack off has to take them wholesale.
  retireTrees = [
    { unless = "argocd.enabled"; trees = [ "argocd" "helm" ]; }
  ];
  overrides = [ ];
  executable = [ ];
  schema = {
    # Declared here, not just consumed: the bootstrap chart needs a port, and a
    # repo that takes this pack without golden-service should fail at eval
    # rather than at render time.
    "service.port" = {
      type = "int";
      required = true;
      description = "Port the chart's Service and Deployment expose.";
    };
    "argocd.enabled" = {
      type = "bool";
      description = "Whether this repo ships a chart and overlays. False deletes argocd/ and helm/.";
    };
    "argocd.environments" = {
      type = "list";
      description = "Which environments get an overlay. Only dev, staging and prod exist.";
    };
  };
}
