{ lib, paths }:
{
  mergePacks = packList:
    let
      partialProblems = lib.concatMap
        (pack:
          if pack.partials == null then [ ]
          else map (rel: "${pack.name}: partials/${rel} is not named _*") (paths.partialViolations pack.partials))
        packList;

      # path -> pack name, later packs overwrite earlier ones. A pack may only
      # overwrite a path it declares in `overrides`.
      step = acc: pack:
        let
          emitted = paths.emittedPaths pack.templates;
          clashes = builtins.filter
            (rel: acc.owners ? ${rel} && !(builtins.elem rel pack.overrides))
            emitted;
          errs = map
            (rel: "${pack.name} and ${acc.owners.${rel}} both emit '${rel}'. Add it to ${pack.name}'s `overrides` if that is intended.")
            clashes;
        in
        {
          owners = acc.owners // lib.genAttrs emitted (_: pack.name);
          errors = acc.errors ++ errs;
        };

      folded = lib.foldl' step { owners = { }; errors = partialProblems; } packList;

      guard = value:
        if folded.errors == [ ]
        then value
        else throw "mkGolden: pack merge failed:\n  ${lib.concatStringsSep "\n  " folded.errors}";
    in
    {
      owners = guard folded.owners;
      templateRoots = lib.reverseList (map (p: p.templates) packList);
      partialRoots = builtins.filter (r: r != null) (map (p: p.partials) packList);
      defaults = lib.foldl' lib.recursiveUpdate { } (map (p: p.defaults) packList);
      registry = lib.foldl' lib.recursiveUpdate { } (map (p: p.registry) packList);
      schema = lib.foldl' (a: p: a // p.schema) { } packList;
      ownership = {
        managed = lib.concatMap (p: p.ownership.managed) packList;
        scaffold = lib.concatMap (p: p.ownership.scaffold) packList;
        retired = lib.concatMap (p: p.ownership.retired) packList;
      };
    };
}
