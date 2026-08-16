{
  name = "golden-service";
  templates = ./templates;
  partials = ./partials;
  defaults = {
    service = {
      container = true;
      port = 8080;
    };
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
