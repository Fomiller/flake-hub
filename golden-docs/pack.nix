{
  name = "golden-docs";
  templates = ./templates;
  partials = ./partials;
  defaults = {
    docs = {
      title = "";
      authors = [ ];
      theme = "frappe";
      repoUrl = "";
      deploy = true;
    };
    gitignore = [ "docs/book/" ];
    just.recipes = [
      "docs:\n    mdbook serve docs --open"
      "docs-build:\n    mdbook build docs"
    ];
  };
  registry = { };
  ownership = {
    managed = [ "docs/book.toml" "docs/theme/catppuccin.css" ".github/workflows/docs.yml" ];
    # The pages are the repo's own writing. The pack seeds a first chapter and
    # a table of contents, then stays out of the way.
    scaffold = [ "docs/src/SUMMARY.md" "docs/src/introduction.md" ];
    retired = [ ];
  };
  overrides = [ ];
  executable = [ ];
  schema = {
    "docs.title" = {
      type = "string";
      description = "Book title. Falls back to the repo name when empty.";
    };
    "docs.authors" = {
      type = "list";
      description = "Names written to book.toml's authors list.";
    };
    "docs.theme" = {
      type = "enum";
      values = [ "latte" "frappe" "macchiato" "mocha" ];
      description = "Catppuccin flavour the book is themed with.";
    };
    "docs.repoUrl" = {
      type = "string";
      description = "Repo URL. When set, the book gets a source link and per-page edit links.";
    };
    "docs.deploy" = {
      type = "bool";
      description = "Whether to write the workflow that publishes the book to GitHub Pages.";
    };
  };
}
