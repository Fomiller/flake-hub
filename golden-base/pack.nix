{
  name = "golden-base";
  templates = ./templates;
  partials = ./partials;
  defaults = {
    description = "";
    # Packs concatenate list defaults, so a pack adds its build output here
    # rather than shipping its own .gitignore.
    gitignore = [ "result" "result-*" ".direnv/" ".DS_Store" ];
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
    "gitignore" = { type = "list"; };
    "just.recipes" = { type = "list"; };
    "unmanaged" = { type = "list"; };
  };
}
