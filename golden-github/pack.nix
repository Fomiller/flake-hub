{
  name = "golden-github";
  templates = ./templates;
  partials = ./partials;
  defaults = {
    github = {
      roleToAssume = "";
      renovate = true;
      buildAndTest = true;
      agents = true;
    };
    ci = {
      jobs = [ ];
      extraSteps = { pre = [ ]; post = [ ]; };
    };
  };
  registry = { };
  ownership = {
    managed = [ ".github/CODEOWNERS" "renovate.json" ".github/workflows/generate.yml" ".github/workflows/ci.yml" ];
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
    "github.roleToAssume" = {
      type = "string";
      description = "IAM role ARN the publish workflows assume through OIDC.";
    };
    "github.renovate" = {
      type = "bool";
      description = "Whether to write renovate.json.";
    };
    "github.buildAndTest" = {
      type = "bool";
      description = "Whether to write ci.yml. False leaves the repo with no build or test workflow.";
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
