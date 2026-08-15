{ lib }:
let
  # Everything except `*` is escaped, so a pack glob containing a regex
  # metacharacter matches it literally instead of crashing builtins.match.
  escapeRe = builtins.replaceStrings
    [ "\\" "." "+" "?" "(" ")" "[" "]" "{" "}" "|" "^" "$" ]
    [ "\\\\" "\\." "\\+" "\\?" "\\(" "\\)" "\\[" "\\]" "\\{" "\\}" "\\|" "\\^" "\\$" ];

  toRegex = pattern: lib.replaceStrings [ "*" ] [ "[^/]*" ] (escapeRe pattern);

  # Glob match supporting a trailing `**` and a single `*` per segment.
  # Deliberately small: pack globs are directory prefixes and filenames.
  matches = pattern: path:
    if pattern == "**" then true
    else if lib.hasSuffix "/**" pattern
    then lib.hasPrefix (lib.removeSuffix "**" pattern) path
    else builtins.match (toRegex pattern) path != null;

  classOf = ownership: path:
    if lib.any (p: matches p path) ownership.managed then "managed"
    else if lib.any (p: matches p path) ownership.scaffold then "scaffold"
    else null;
in
{
  mkPlan = merged: config:
    let
      emitted = builtins.attrNames merged.owners;
      unmanaged = config.unmanaged or [ ];
      live = builtins.filter (p: !(builtins.elem p unmanaged)) emitted;

      stale = map (u: "unmanaged entry '${u}' in repo.nix matches no generated path")
        (builtins.filter (u: !(builtins.elem u emitted)) unmanaged);

      unclassified = map (p: "'${p}' is rendered by ${merged.owners.${p}} but matches no ownership glob")
        (builtins.filter (p: classOf merged.ownership p == null) live);

      retiredButEmitted = map (p: "'${p}' is listed as retired but is still emitted by ${merged.owners.${p}}")
        (builtins.filter (p: builtins.elem p emitted) merged.ownership.retired);

      bothClasses = map (p: "'${p}' matches both a managed and a scaffold glob; make the globs disjoint")
        (builtins.filter
          (p: lib.any (g: matches g p) merged.ownership.managed
            && lib.any (g: matches g p) merged.ownership.scaffold)
          live);

      errors = stale ++ unclassified ++ retiredButEmitted ++ bothClasses;

      byClass = cls: builtins.filter (p: classOf merged.ownership p == cls) live;

      guard = value:
        if errors == [ ]
        then value
        else throw "mkGolden: plan is not valid:\n  ${lib.concatStringsSep "\n  " errors}";
    in
    guard {
      repo = config.name;
      managed = byClass "managed";
      scaffold = byClass "scaffold";
      retired = merged.ownership.retired;
      inherit unmanaged;
    };
}
