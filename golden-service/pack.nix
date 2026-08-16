{
  name = "golden-service";
  templates = ./templates;
  partials = ./partials;
  defaults = {
    service = {
      container = true;
      port = 8080;
    };
    # `stepsFrom` is opaque to golden-github, which owns ci.yml. The lookup
    # happens in the template, where `language` and the registry are in scope.
    ci.jobs = [{ name = "build-test"; stepsFrom = "language"; }];
    just.recipes = [
      "build:\n    just _lang-build"
      "test:\n    just _lang-test"
    ];
  };
  registry = import ./registry.nix;
  ownership = {
    managed = [ "Dockerfile" ];
    scaffold = [ ];
    retired = [ ];
  };
  overrides = [ ];
  executable = [ ];
  schema = {
    "language" = { type = "enum"; values = [ "go" "rust" ]; required = true; };
    "service.container" = { type = "bool"; };
    "service.port" = { type = "int"; };
    "service.binary" = { type = "string"; };
  };
}
