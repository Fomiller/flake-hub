{
  name = "golden-github";
  templates = ./templates;
  partials = ./partials;
  defaults = {
    ci = {
      security = true;
      release = false;
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
    "ci.security" = { type = "bool"; };
    "ci.jobs" = { type = "list"; };
    "ci.release" = { type = "bool"; };
    "ci.extraSteps.pre" = { type = "list"; };
    "ci.extraSteps.post" = { type = "list"; };
  };
}
