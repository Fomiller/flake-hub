{
  name = "golden-base";
  templates = ./templates;
  partials = ./partials;
  defaults = {
    description = "";
    namePrefix = "";
    slug = "";
    # Packs concatenate list defaults, so a pack adds its build output here
    # rather than shipping its own .gitignore.
    gitignore = [ "result" "result-*" ".direnv/" ".DS_Store" ];
    just = {
      enabled = true;
      recipes = [ ];
    };
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
    "name" = {
      type = "string";
      required = true;
      description = "Repo name. Reaches the README, the chart directory, and the image repository.";
    };
    "namePrefix" = {
      type = "string";
      description = "Prefix stripped from name to get the slug. Only read when slug is empty.";
    };
    "slug" = {
      type = "string";
      description = "Short name for display. Empty means name with namePrefix removed.";
    };
    "just.enabled" = {
      type = "bool";
      description = "Whether to write the justfile. False leaves the repo with no recipes at all.";
    };
    "description" = {
      type = "string";
      description = "One line about the repo. Shown in the generated README.";
    };
    "gitignore" = {
      type = "list";
      description = "Lines written to .gitignore, one per entry. Packs append to this.";
    };
    "just.recipes" = {
      type = "list";
      description = "Recipes written to the justfile. Packs append to this.";
    };
    "unmanaged" = {
      type = "list";
      description = "Paths the engine leaves alone even though a pack owns them.";
    };
  };
}
