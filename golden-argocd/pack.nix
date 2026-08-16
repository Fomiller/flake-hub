{
  name = "golden-argocd";
  templates = ./templates;
  partials = ./partials;
  defaults = {
    deploy = {
      envs = [ "dev" ];
      replicas = 1;
      chartVersion = "0.1.0";
    };
  };
  registry = { };
  ownership = {
    # The chart directory is named after the repo. The engine substitutes
    # {{ name }} in the template path, so the globs match one segment.
    managed = [
      "helm/*/Chart.yaml"
      "helm/*/templates/*"
      "argocd/overlays/*/kustomization.yaml"
      ".github/workflows/publish-chart.yml"
    ];
    # The chart's values and the overlay values are the service's own
    # configuration surface, so they are written once and then left alone.
    scaffold = [
      "helm/*/values.yaml"
      "argocd/overlays/values.app.base.yaml"
      "argocd/overlays/*/values.app.yaml"
    ];
    # Was deploy/chart before the chart moved under helm/<chart>/. Listed so a
    # repo on the old layout has them removed rather than left as a second,
    # stale copy.
    retired = [
      "deploy/chart/Chart.yaml"
      "deploy/chart/values.yaml"
      "deploy/chart/templates/deployment.yaml"
      "deploy/chart/templates/service.yaml"
      "deploy/chart/templates/helpers.tpl"
    ];
  };
  overrides = [ ];
  executable = [ ];
  schema = {
    # Declared here, not just consumed: the chart templates need a port, and a
    # repo that takes this pack without golden-service should fail at eval
    # rather than at render time.
    "service.port" = { type = "int"; required = true; };
    "deploy.registry" = { type = "string"; required = true; };
    "deploy.ecrRepo" = { type = "string"; required = true; };
    "deploy.roleToAssume" = { type = "string"; required = true; };
    "deploy.envs" = { type = "list"; };
    "deploy.replicas" = { type = "int"; };
    "deploy.chartVersion" = { type = "string"; };
  };
}
