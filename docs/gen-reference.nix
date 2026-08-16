{ lib }:
pack:
let
  row = key:
    let
      e = pack.schema.${key};
      values = lib.optionalString (e ? values)
        " (${lib.concatStringsSep ", " (map (v: "`${v}`") e.values)})";
    in
    "| `${key}` | ${e.type}${values} | ${if e.required or false then "yes" else "no"} |";

  schemaTable =
    if pack.schema == { } then "This pack takes no configuration."
    else
      lib.concatStringsSep "\n" ([
        "| Key | Type | Required |"
        "|---|---|---|"
      ] ++ map row (builtins.attrNames pack.schema));

  fileList = cls:
    let paths = pack.ownership.${cls}; in
    if paths == [ ] then "_none_"
    else lib.concatStringsSep ", " (map (p: "`${p}`") paths);
in
''
  ## Configuration

  ${schemaTable}

  ## Files

  | Class | Paths |
  |---|---|
  | managed | ${fileList "managed"} |
  | scaffold | ${fileList "scaffold"} |
  | retired | ${fileList "retired"} |
''
