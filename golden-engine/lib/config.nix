{ lib }:
let
  flatten = prefix: value:
    if builtins.isAttrs value
    then lib.concatLists (lib.mapAttrsToList
      (k: v: flatten (if prefix == "" then k else "${prefix}.${k}") v)
      value)
    else [{ key = prefix; inherit value; }];

  typeOk = entry: value:
    if entry.type == "string" then builtins.isString value
    else if entry.type == "bool" then builtins.isBool value
    else if entry.type == "list" then builtins.isList value
    else if entry.type == "attrs" then builtins.isAttrs value
    else if entry.type == "enum" then builtins.elem value entry.values
    else throw "mkGolden: schema for '${entry.name or "?"}' has unknown type '${entry.type}'";
in
{
  mergeConfig = merged: repoConfig:
    let
      resolved = lib.recursiveUpdate (lib.recursiveUpdate merged.defaults merged.registry) repoConfig;
      flat = flatten "" repoConfig;

      unknown = map (e: "unknown key '${e.key}' in repo.nix")
        (builtins.filter (e: !(merged.schema ? ${e.key})) flat);

      badType = map
        (e: "key '${e.key}' in repo.nix failed its schema: expected ${merged.schema.${e.key}.type}")
        (builtins.filter (e: merged.schema ? ${e.key} && !(typeOk merged.schema.${e.key} e.value)) flat);

      missing = map (k: "required key '${k}' is not set in repo.nix or any pack default")
        (builtins.filter
          (k: (merged.schema.${k}.required or false) && !(builtins.elem k (map (e: e.key) (flatten "" resolved))))
          (builtins.attrNames merged.schema));

      errors = unknown ++ badType ++ missing;
    in
    if errors == [ ]
    then resolved
    else throw "mkGolden: repo.nix is not valid:\n  ${lib.concatStringsSep "\n  " errors}";
}
