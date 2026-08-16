{
  name = "golden-github";
  templates = ./templates;
  partials = ./partials;
  defaults = {
    ci = {
      security = true;
      release = false;
      extraSteps = { pre = [ ]; post = [ ]; };
    };
  };
  registry = { };
  ownership = {
    managed = [ "CODEOWNERS" "renovate.json" ".github/workflows/generate.yml" ];
    scaffold = [ ];
    retired = [ ];
  };
  overrides = [ ];
  schema = {
    "codeowners" = { type = "list"; required = true; };
    "ci.security" = { type = "bool"; };
    "ci.release" = { type = "bool"; };
    "ci.extraSteps.pre" = { type = "list"; };
    "ci.extraSteps.post" = { type = "list"; };
  };
}
