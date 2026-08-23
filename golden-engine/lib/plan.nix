{ lib, pathvars }:
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

  # A pack declares `retireTrees = [ { unless = "argocd.enabled"; trees = [ "argocd" ]; } ]`.
  # Data, not a function, because pack.nix is imported with no arguments.
  treeEntries = merged: config:
    let
      entries = merged.retireTrees or [ ];
      gateOf = entry: lib.attrByPath (lib.splitString "." entry.unless) null config;
      badGate = lib.concatMap
        (entry:
          let v = gateOf entry; in
          if builtins.isBool v then [ ]
          else [ "retireTrees gate '${entry.unless}' is ${if v == null then "not set in the merged config" else "not a bool"}" ])
        entries;
      badTree = lib.concatMap
        (entry: map (t: "retireTrees tree '${t}' must be a plain relative directory")
          (builtins.filter
            (t: t == "" || lib.hasPrefix "/" t || lib.hasInfix ".." t || lib.hasInfix "*" t)
            entry.trees))
        entries;
      active = lib.concatMap (entry: if gateOf entry == false then entry.trees else [ ]) entries;
    in
    {
      errors = badGate ++ badTree;
      trees = lib.unique active;
    };

  classOf = ownership: path:
    if lib.any (p: matches p path) ownership.managed then "managed"
    else if lib.any (p: matches p path) ownership.scaffold then "scaffold"
    else null;
in
{
  mkPlan = merged: config:
    let
      # Template paths may carry {{ key }}. Everything below works on the
      # substituted path, which is where the file actually lands.
      owners = lib.mapAttrs' (p: pack: lib.nameValuePair (pathvars.substitute config p) pack)
        merged.owners;

      emitted = builtins.attrNames owners;

      unresolved = map (p: "'${p}' still holds an unresolved {{ ... }} after path substitution; only top-level string keys can appear in a path")
        (builtins.filter (p: lib.hasInfix "{{" p) emitted);
      unmanaged = config.unmanaged or [ ];
      live = builtins.filter (p: !(builtins.elem p unmanaged)) emitted;

      retiredAndUnmanaged = builtins.filter (u: builtins.elem u merged.ownership.retired) unmanaged;

      # Reported ahead of `stale` so the contradiction gets the accurate
      # message: a retired path is never emitted, so it is stale as well.
      retiredButUnmanaged = map (p: "'${p}' is listed as retired but also declared unmanaged in repo.nix; a repo cannot both keep a file untouched and have it deleted")
        retiredAndUnmanaged;

      stale = map (u: "unmanaged entry '${u}' in repo.nix matches no generated path")
        (builtins.filter (u: !(builtins.elem u emitted) && !(builtins.elem u retiredAndUnmanaged)) unmanaged);

      unclassified = map (p: "'${p}' is rendered by ${owners.${p}} but matches no ownership glob")
        (builtins.filter (p: classOf merged.ownership p == null) live);

      retiredButEmitted = map (p: "'${p}' is listed as retired but is still emitted by ${owners.${p}}")
        (builtins.filter (p: builtins.elem p emitted) merged.ownership.retired);

      # `retired` is unlinked path by path, unlike managed and scaffold which
      # are matched as globs against what the templates emit. A `*` here
      # therefore deletes nothing and says nothing, which is the worst way to
      # find out.
      retiredGlobs = map (p: "retired entry '${p}' contains a glob; retired paths are deleted literally, so list each one")
        (builtins.filter (p: lib.hasInfix "*" p || lib.hasInfix "?" p) merged.ownership.retired);

      bothClasses = map (p: "'${p}' matches both a managed and a scaffold glob; make the globs disjoint")
        (builtins.filter
          (p: lib.any (g: matches g p) merged.ownership.managed
            && lib.any (g: matches g p) merged.ownership.scaffold)
          live);

      # Checked against everything emitted, not just `live`: a repo is allowed
      # to declare an executable path unmanaged without that reading as a typo.
      staleExecutable = map (g: "executable glob '${g}' matches no generated path")
        (builtins.filter (g: !(lib.any (p: matches g p) emitted)) merged.executable);

      trees = treeEntries merged config;

      # A retired tree takes hand-written files with it, so a repo cannot keep
      # anything under it.
      unmanagedUnderTree = lib.concatMap
        (t: map (u: "unmanaged entry '${u}' in repo.nix sits under '${t}', which is retired wholesale")
          (builtins.filter (u: lib.hasPrefix "${t}/" u) unmanaged))
        trees.trees;

      errors = unresolved ++ retiredButUnmanaged ++ stale ++ unclassified ++ retiredButEmitted
        ++ retiredGlobs ++ bothClasses ++ staleExecutable ++ trees.errors ++ unmanagedUnderTree;

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
      retiredTrees = trees.trees;
      executable = builtins.filter (p: lib.any (g: matches g p) merged.executable) live;
      inherit unmanaged;
    };
}
