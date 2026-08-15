{
  name = "custom-repo";
  description = "A repo that exercises the knobs.";
  just.recipes = [ "smoke:\n    ./scripts/smoke.sh" ];
  unmanaged = [ ".editorconfig" ];
}
