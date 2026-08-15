{
  name = "golden-base";
  templates = ./templates;
  partials = ./partials;
  defaults = { };
  registry = { };
  ownership = { managed = [ "**" ]; scaffold = [ ]; retired = [ ]; };
  overrides = [ ];
  schema = {
    "name" = { type = "string"; required = true; };
  };
}
