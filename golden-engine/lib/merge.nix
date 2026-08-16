{ lib, paths }:
let
  # Packs are additive, so two packs contributing to the same list both keep
  # their entries. repo.nix is not additive: config.nix uses recursiveUpdate,
  # so a repo can still clear an inherited list with [ ].
  mergeDefaults = defaultsList:
    let
      merge2 = a: b:
        let
          keys = lib.unique (builtins.attrNames a ++ builtins.attrNames b);
          pick = k:
            if !(a ? ${k}) then b.${k}
            else if !(b ? ${k}) then a.${k}
            else if builtins.isList a.${k} && builtins.isList b.${k} then a.${k} ++ b.${k}
            else if builtins.isAttrs a.${k} && builtins.isAttrs b.${k} then merge2 a.${k} b.${k}
            else b.${k};
        in
        lib.genAttrs keys pick;
    in
    lib.foldl' merge2 { } defaultsList;
in
{
  inherit mergeDefaults;

  mergePacks = packList:
    let
      partialProblems = lib.concatMap
        (pack:
          if pack.partials == null then [ ]
          else map (rel: "${pack.name}: partials/${rel} is not named _*") (paths.partialViolations pack.partials))
        packList;

      # path -> pack name, later packs overwrite earlier ones. A pack may only
      # overwrite a path it declares in `overrides`. Partials are tracked
      # separately because emittedPaths excludes them by construction.
      step = acc: pack:
        let
          emitted = paths.emittedPaths pack.templates;
          clashes = builtins.filter
            (rel: acc.owners ? ${rel} && !(builtins.elem rel pack.overrides))
            emitted;
          errs = map
            (rel: "${pack.name} and ${acc.owners.${rel}} both emit '${rel}'. Add it to ${pack.name}'s `overrides` if that is intended.")
            clashes;

          partialRels = if pack.partials == null then [ ] else paths.listFiles pack.partials;
          partialClashes = builtins.filter
            (rel: acc.partialOwners ? ${rel} && !(builtins.elem rel pack.overrides))
            partialRels;
          partialErrs = map
            (rel: "${pack.name} and ${acc.partialOwners.${rel}} both ship partial '${rel}'. Add it to ${pack.name}'s `overrides` if that is intended.")
            partialClashes;
        in
        {
          owners = acc.owners // lib.genAttrs emitted (_: pack.name);
          partialOwners = acc.partialOwners // lib.genAttrs partialRels (_: pack.name);
          errors = acc.errors ++ errs ++ partialErrs;
        };

      folded = lib.foldl' step { owners = { }; partialOwners = { }; errors = partialProblems; } packList;

      guard = value:
        if folded.errors == [ ]
        then value
        else throw "mkGolden: pack merge failed:\n  ${lib.concatStringsSep "\n  " folded.errors}";
    in
    guard {
      owners = folded.owners;
      templateRoots = lib.reverseList (map (p: p.templates) packList);
      partialRoots = lib.reverseList (builtins.filter (r: r != null) (map (p: p.partials) packList));
      defaults = mergeDefaults (map (p: p.defaults) packList);
      registry = lib.foldl' lib.recursiveUpdate { } (map (p: p.registry) packList);
      schema = lib.foldl' lib.recursiveUpdate { } (map (p: p.schema) packList);
      executable = lib.concatMap (p: p.executable) packList;
      ownership = {
        managed = lib.concatMap (p: p.ownership.managed) packList;
        scaffold = lib.concatMap (p: p.ownership.scaffold) packList;
        retired = lib.concatMap (p: p.ownership.retired) packList;
      };
    };
}
