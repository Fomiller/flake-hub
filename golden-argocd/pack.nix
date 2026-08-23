{
  name = "golden-argocd";
  templates = ./templates;
  partials = ./partials;
  defaults = {
    argocd = {
      enabled = true;
      environments = [ "dev" ];
      replicas = 1;
      chartVersion = "0.1.0";
      healthPath = "/healthz";
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
      "argocd/overlays/*/kustomization.yaml"
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
    "argocd.awsRegion" = {
      type = "string";
      description = "Region the publish workflows log in to ECR against.";
    };
    "argocd.enabled" = {
      type = "bool";
      description = "Whether this repo ships a chart and overlays. False deletes argocd/ and helm/.";
    };
    "argocd.environments" = {
      type = "list";
      description = "Which environments get an overlay. Only dev, staging and prod exist.";
    };
    "argocd.replicas" = {
      type = "int";
      description = "Replica count in the shared overlay values, before per-environment overrides.";
    };
    "argocd.chartVersion" = {
      type = "string";
      description = "Chart version in Chart.yaml. Also seeds the version each overlay pulls, on the first generate only — after that the overlay is the promotion tool's to rewrite.";
    };
    "argocd.healthPath" = {
      type = "string";
      description = "HTTP path the readiness and liveness probes call, on service.port. Empty writes no probes, for a service with no health endpoint.";
    };
    "argocd.platforms" = {
      type = "list";
      description = "Platforms the image is built for, passed to buildx.";
    };
  };
}
