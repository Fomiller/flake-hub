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
    managed = [ ".gitignore" "justfile" ];
    scaffold = [ "README.md" ];
    # Editor and shell setup is the developer's, not the repo's. Listed here so
    # a repo that already has the generated copies gets them removed.
    retired = [ ".editorconfig" ".envrc" ];
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
