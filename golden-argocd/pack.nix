{
  name = "golden-argocd";
  templates = ./templates;
  partials = ./partials;
  defaults = {
    argocd = {
      enabled = true;
      environment = "dev";
      kargo = true;
      namespace = "";
      notifications = "";
    };
    # `kustomize build --enable-helm` pulls each chart into a charts/ directory
    # beside the kustomization. Argo CD does that in a throwaway workspace, but
    # anyone running the same build locally gets a whole vendored chart tree in
    # their working copy.
    gitignore = [ "argocd/overlays/*/charts/" ];
  };
  registry = { };
  ownership = {
    # The one managed file, and only because homelab reads it: an ApplicationSet
    # asks each repo for argocd.yaml to build its Application. Every field in it
    # comes from repo.nix, so regenerating it can only ever agree with repo.nix.
    managed = [ "argocd.yaml" ];
    # Everything a repo deploys is scaffold. What a service deploys is the
    # service's decision, and it changes for reasons repo.nix never sees: a
    # chart version Kargo promoted, an env var, a probe path. A managed file
    # would revert those on whatever `nix run .#generate` runs next.
    scaffold = [
      # The chart directory is named after the repo. The engine substitutes
      # {{ name }} in the template path, so the globs match one segment.
      "helm/*/Chart.yaml"
      "helm/*/values.yaml"
      "helm/*/templates/*"
      "argocd/overlays/values.app.base.yaml"
      "argocd/overlays/*/values.app.yaml"
      "argocd/overlays/*/values.kargo.yaml"
      "argocd/overlays/*/kustomization.yaml"
    ];
    # deploy/chart was the layout before the chart moved under helm/<chart>/.
    #
    # kargo/values.yaml is newer: the promotion pipeline used to be its own
    # top-level directory, installed by a second Application. It now renders
    # from the same overlay as the workload, so the directory has nothing left
    # in it.
    retired = [
      "deploy/chart/Chart.yaml"
      "deploy/chart/values.yaml"
      "deploy/chart/templates/deployment.yaml"
      "deploy/chart/templates/service.yaml"
      "deploy/chart/templates/helpers.tpl"
      "kargo/values.yaml"
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
    "argocd.environment" = {
      type = "string";
      description = "Which environment this repo deploys to. One of dev, staging, prod.";
    };
    "argocd.kargo" = {
      type = "bool";
      description = "Whether the overlay also installs a Kargo promotion pipeline.";
    };
    "argocd.namespace" = {
      type = "string";
      description = "Namespace the workload deploys into. Empty means the repo name.";
    };
    "argocd.notifications" = {
      type = "string";
      description = "Where Argo CD sends sync notifications. Empty means none.";
    };
  };
}
