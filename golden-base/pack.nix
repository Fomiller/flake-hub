{
  name = "golden-base";
  templates = ./templates;
  partials = ./partials;
  defaults = {
    description = "";
    just.recipes = [ ];
    unmanaged = [ ];
  };
  registry = { };
  ownership = {
    managed = [ ".gitignore" ".editorconfig" ".envrc" "justfile" ];
    scaffold = [ "README.md" ];
    retired = [ ];
  };
  overrides = [ ];
  executable = [ ];
  schema = {
    "name" = { type = "string"; required = true; };
    "description" = { type = "string"; };
    "just.recipes" = { type = "list"; };
    "unmanaged" = { type = "list"; };
  };
}
