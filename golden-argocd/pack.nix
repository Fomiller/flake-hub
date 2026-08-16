{
  name = "golden-argocd";
  templates = ./templates;
  partials = ./partials;
  defaults = {
    deploy = {
      replicas = 1;
      chartVersion = "0.1.0";
    };
  };
  registry = { };
  ownership = {
    # values.yaml is the service's own configuration surface, so it is written
    # once and then left alone. Everything else is regenerated.
    managed = [
      "deploy/chart/Chart.yaml"
      "deploy/chart/templates/*"
      ".github/workflows/publish-chart.yml"
    ];
    scaffold = [ "deploy/chart/values.yaml" ];
    retired = [ ];
  };
  overrides = [ ];
  executable = [ ];
  schema = {
    # Declared here, not just consumed: the chart templates need a port, and a
    # repo that takes this pack without golden-service should fail at eval
    # rather than at render time.
    "service.port" = { type = "int"; required = true; };
    "deploy.ecrRepo" = { type = "string"; required = true; };
    "deploy.roleToAssume" = { type = "string"; required = true; };
    "deploy.replicas" = { type = "int"; };
    "deploy.chartVersion" = { type = "string"; };
  };
}
