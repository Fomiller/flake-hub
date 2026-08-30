{
  name = "golden-github";
  templates = ./templates;
  partials = ./partials;
  defaults = {
    github = {
      renovate = true;
      buildAndTest = true;
      agents = true;
      publishImage = false;
      publishChart = false;
      platforms = [ "linux/amd64" ];
    };
    ci = {
      jobs = [ ];
      extraSteps = { pre = [ ]; post = [ ]; };
    };
  };
  registry = { };
  ownership = {
    managed = [
      ".github/CODEOWNERS"
      "renovate.json"
      ".github/workflows/generate.yml"
      ".github/workflows/ci.yml"
      ".github/workflows/publish-image.yml"
      ".github/workflows/publish-chart.yml"
    ];
    # AGENTS.md is written once and is then the repo's own instructions.
    scaffold = [ "AGENTS.md" ];
    retired = [ "CODEOWNERS" ];
  };
  overrides = [ ];
  executable = [ ];
  schema = {
    "github.codeowners" = {
      type = "list";
      required = true;
      description = "GitHub handles or teams that own every path. Written to .github/CODEOWNERS.";
    };
    "github.renovate" = {
      type = "bool";
      description = "Whether to write renovate.json.";
    };
    "github.buildAndTest" = {
      type = "bool";
      description = "Whether to write ci.yml. False leaves the repo with no build or test workflow.";
    };
    "github.publishImage" = {
      type = "bool";
      description = "Whether to write publish-image.yml, which builds the repo's container image and pushes it to ECR.";
    };
    "github.publishChart" = {
      type = "bool";
      description = "Whether to write publish-chart.yml, which packages every helm/*/Chart.yaml and pushes it to ECR.";
    };
    "github.platforms" = {
      type = "list";
      description = "Platforms the image is built for, passed to buildx.";
    };
    "github.agents" = {
      type = "bool";
      description = "Whether to seed AGENTS.md. It is written once; turning this off later leaves the file alone.";
    };
    "ci.jobs" = {
      type = "list";
      description = "Jobs added to ci.yml. Packs append to this.";
    };
    "ci.extraSteps.pre" = {
      type = "list";
      description = "Steps run before every CI job's own steps.";
    };
    "ci.extraSteps.post" = {
      type = "list";
      description = "Steps run after every CI job's own steps.";
    };
  };
}
