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
    # Build output for both languages. Defaults are static data and cannot
    # branch on `language`, and an unused line costs nothing.
    gitignore = [ "bin/" "target/" ];
    just.recipes = [
      { name = "build"; cmdFrom = "buildCmd"; }
      { name = "test"; cmdFrom = "testCmd"; }
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
    "language" = {
      type = "enum";
      values = [ "go" "rust" ];
      required = true;
      description = "Picks the CI steps, the just recipes, and the Dockerfile base images.";
    };
    "service.container" = {
      type = "bool";
      description = "Whether to write a Dockerfile. Off for a library.";
    };
    "service.port" = {
      type = "int";
      description = "Port the service listens on. Reaches the Dockerfile and the chart.";
    };
    "service.binary" = {
      type = "string";
      description = "Binary name, if it is not the repo name.";
    };
  };
}
