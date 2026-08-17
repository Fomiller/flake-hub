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

  # Schema keys are dotted paths. Rebuild the nesting so the example looks like
  # a repo.nix and not a list of strings. __key marks a leaf and holds the
  # dotted name, which is how the schema and defaults are indexed.
  tree = lib.foldl'
    (acc: key: lib.recursiveUpdate acc
      (lib.setAttrByPath (lib.splitString "." key) { __key = key; }))
    { }
    (builtins.attrNames pack.schema);

  fmt = v:
    if builtins.isString v then ''"${v}"''
    else if builtins.isBool v then (if v then "true" else "false")
    else if builtins.isInt v then toString v
    else if builtins.isList v then
      (if v == [ ] then "[ ]" else "[ ${lib.concatMapStringsSep " " fmt v} ]")
    else builtins.toJSON v;

  # A required key with no default needs something in the slot. An enum can
  # show a real member; everything else gets a fill-me marker.
  placeholder = e:
    if e ? values then ''"${builtins.head e.values}"''
    else if e.type == "string" then ''"…"''
    else if e.type == "int" then "0"
    else if e.type == "bool" then "true"
    else if e.type == "list" then "[ ]"
    else "null";

  typeName = e:
    if e ? values then "enum: ${lib.concatStringsSep " | " e.values}" else e.type;

  leaf = indent: name: key:
    let
      e = pack.schema.${key};
      default = lib.attrByPath (lib.splitString "." key) null pack.defaults;
      required = e.required or false;
      value = if default != null then fmt default else placeholder e;
      note =
        if required then "required, ${typeName e}"
        else if default != null then "${typeName e}, default"
        else "${typeName e}, no default";
    in
    "${indent}${name} = ${value};  # ${note}";

  entry = indent: name: node:
    if node ? __key
    then leaf indent name node.__key
    else "${indent}${name} = {\n${attrs (indent + "  ") node}\n${indent}};";

  hasRequired = node:
    if node ? __key
    then pack.schema.${node.__key}.required or false
    else lib.any (n: hasRequired node.${n}) (builtins.attrNames node);

  # Required keys first, so the lines a reader has to fill in are at the top.
  attrs = indent: node:
    let
      rank = n: (if hasRequired node.${n} then "0" else "1") + n;
      names = lib.sort (a: b: rank a < rank b) (builtins.attrNames node);
    in
    lib.concatStringsSep "\n" (map (n: entry indent n node.${n}) names);

  example = ''
    ## repo.nix

    Every knob this pack adds. Optional keys show the default they fall back
    to, so deleting a line changes nothing. Required keys need a real value.

    ```nix
    {
    ${attrs "  " tree}
    }
    ```
  '';
in
''
  ${lib.optionalString (pack.schema != { }) example}
  ## Configuration

  ${schemaTable}

  ## Files

  | Class | Paths |
  |---|---|
  | managed | ${fileList "managed"} |
  | scaffold | ${fileList "scaffold"} |
  | retired | ${fileList "retired"} |
''
