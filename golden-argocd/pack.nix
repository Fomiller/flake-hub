{
  name = "golden-argocd";
  templates = ./templates;
  partials = ./partials;
  defaults = {
    argocd = {
      envs = [ "dev" ];
      replicas = 1;
      chartVersion = "0.1.0";
      awsRegion = "us-east-1";
      platforms = [ "linux/amd64" ];
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
      ".github/workflows/publish-image.yml"
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
    "service.port" = {
      type = "int";
      required = true;
      description = "Port the chart's Service and Deployment expose.";
    };
    "argocd.registry" = {
      type = "string";
      required = true;
      description = "OCI registry host. Both the image and the chart sit at its root.";
    };
    "argocd.roleToAssume" = {
      type = "string";
      required = true;
      description = "IAM role the publish workflows assume over OIDC.";
    };
    "argocd.awsRegion" = {
      type = "string";
      description = "Region the publish workflows log in to ECR against.";
    };
    "argocd.envs" = {
      type = "list";
      description = "Which environments get an overlay. Only dev, staging and prod exist.";
    };
    "argocd.replicas" = {
      type = "int";
      description = "Replica count in the shared overlay values, before per-environment overrides.";
    };
    "argocd.chartVersion" = {
      type = "string";
      description = "Chart version in Chart.yaml, and the version the overlays pull.";
    };
    "argocd.platforms" = {
      type = "list";
      description = "Platforms the image is built for, passed to buildx.";
    };
  };
}
