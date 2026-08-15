{
  description = "Team-agnostic core of the flake-hub golden-file generator";

  outputs = { self }: {
    lib.mkGolden = import ./mkGolden.nix;

    # Paths, not derivations: packs own the pkgs that run these. `src` is the
    # whole flake directory, so a pack can reach lib/ and tests/ together —
    # a store path cannot be escaped with `/..`.
    src = ./.;
  };
}
