{ lib }:
let
  # Glob match supporting a trailing `**` and a single `*` per segment.
  # Deliberately small: pack globs are directory prefixes and filenames.
  matches = pattern: path:
    if pattern == "**" then true
    else if lib.hasSuffix "/**" pattern
    then lib.hasPrefix (lib.removeSuffix "**" pattern) path
    else builtins.match (lib.replaceStrings [ "." "*" ] [ "\\." "[^/]*" ] pattern) path != null;

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

      stale = map (u: "unmanaged entry '${u}' in repo.nix matches no generated path")
        (builtins.filter (u: !(builtins.elem u emitted)) unmanaged);

      unclassified = map (p: "'${p}' is rendered by ${merged.owners.${p}} but matches no ownership glob")
        (builtins.filter (p: classOf merged.ownership p == null) emitted);

      errors = stale ++ unclassified;

      live = builtins.filter (p: !(builtins.elem p unmanaged)) emitted;
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
