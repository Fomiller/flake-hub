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
    managed = [ "CODEOWNERS" "renovate.json" ".github/workflows/generate.yml" ".github/workflows/ci.yml" ];
    scaffold = [ ];
    retired = [ ];
  };
  overrides = [ ];
  executable = [ ];
  schema = {
    "codeowners" = { type = "list"; required = true; };
    "ci.jobs" = { type = "list"; };
    "ci.extraSteps.pre" = { type = "list"; };
    "ci.extraSteps.post" = { type = "list"; };
  };
}
