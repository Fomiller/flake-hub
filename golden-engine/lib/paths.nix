{ lib }:
rec {
  listFiles = root:
    let
      walk = prefix: dir:
        lib.concatLists (lib.mapAttrsToList
          (name: type:
            let rel = if prefix == "" then name else "${prefix}/${name}";
            in
            if type == "directory" then walk rel "${dir}/${name}" else [ rel ])
          (builtins.readDir dir));
    in
    walk "" (toString root);

  # Matches on any path segment, not just the filename — e.g., "_foo/bar.txt" is partial
  isPartial = rel: lib.any (lib.hasPrefix "_") (lib.splitString "/" rel);

  stripJinja = rel: lib.removeSuffix ".jinja" rel;

  emittedPaths = root: map stripJinja (builtins.filter (rel: !isPartial rel) (listFiles root));

  partialViolations = root: builtins.filter (rel: !isPartial rel) (listFiles root);
}
