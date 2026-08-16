{ lib }:
{
  # A template path may carry {{ key }} components, for any top-level string in
  # the merged config. makejinja renders file contents but copies path names
  # through untouched, so the substitution happens here for the plan and in
  # render_paths.py for the rendered tree. Both use this same rule.
  substitute = config: path:
    let
      keys = builtins.filter (k: builtins.isString config.${k}) (builtins.attrNames config);
    in
    builtins.replaceStrings
      (map (k: "{{ ${k} }}") keys)
      (map (k: config.${k}) keys)
      path;
}
