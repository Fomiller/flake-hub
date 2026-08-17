{
  name = "golden-github";
  templates = ./templates;
  partials = ./partials;
  defaults = {
    ci = {
      jobs = [ ];
      extraSteps = { pre = [ ]; post = [ ]; };
    };
  };
  registry = { };
  ownership = {
    managed = [ ".github/CODEOWNERS" "renovate.json" ".github/workflows/generate.yml" ".github/workflows/ci.yml" ];
    scaffold = [ ];
    retired = [ "CODEOWNERS" ];
  };
  overrides = [ ];
  executable = [ ];
  schema = {
    "codeowners" = {
      type = "list";
      required = true;
      description = "GitHub handles or teams that own every path. Written to .github/CODEOWNERS.";
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
