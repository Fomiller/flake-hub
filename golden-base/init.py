#!/usr/bin/env python3
"""Seed a repo with the three files a flake-hub consumer holds.

Pack versions come from pack-versions.nix, which release-flake.yaml
regenerates. A stale init writes stale pins and the first Renovate run
corrects them.
"""

import argparse
import re
import sys
from pathlib import Path

REPO = "github:Fomiller/flake-hub"
ALWAYS = ["golden-engine", "golden-base"]


def read_versions(path: Path) -> dict[str, str]:
    return dict(re.findall(r'^\s*([\w-]+)\s*=\s*"([^"]+)";', path.read_text(), re.M))


# No `follows` lines. A consumer reads only `<pack>.pack`, which is a plain
# import of pack.nix, so a pack flake's own inputs never reach the build.
def input_line(pack: str, version: str) -> str:
    return f'    {pack}.url = "{REPO}?dir={pack}&ref=refs/tags/{pack}-{version}";'


def render_flake(packs: list[str], versions: dict[str, str]) -> str:
    inputs = "\n".join(input_line(p, versions[p]) for p in packs)
    args = ", ".join(["self", "nixpkgs", "flake-utils"] + packs)
    pack_list = " ".join(f"{p}.pack" for p in packs if p != "golden-engine")
    return f"""{{
  inputs = {{
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
{inputs}
  }};

  outputs = {{ {args} }}:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${{system}};
        golden = golden-engine.lib.mkGolden {{
          packs = [ {pack_list} ];
        }} pkgs (import ./repo.nix);
      in
      {{
        apps.generate = golden.generateApp;
        packages.golden-files = golden.filesDrv;
      }});
}}
"""


def render_repo_nix(name: str, packs: list[str]) -> str:
    lines = [f'  name = "{name}";']
    # golden-github makes github.codeowners required, so a repo that selects it
    # and is not seeded here cannot generate at all.
    if "golden-github" in packs:
        lines.append('  github.codeowners = [ "@Fomiller" ];')
    body = "\n".join(lines)
    return f"{{\n{body}\n}}\n"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--name", required=True)
    ap.add_argument("--packs", default="", help="comma-separated, without the golden- prefix")
    ap.add_argument("--versions", type=Path, default=Path(__file__).parent / "pack-versions.nix")
    args = ap.parse_args()

    versions = read_versions(args.versions)
    extra = [f"golden-{p.strip()}" for p in args.packs.split(",") if p.strip()]
    unknown = [p for p in extra if p not in versions]
    if unknown:
        sys.exit(f"init: unknown pack(s): {', '.join(unknown)}. Known: {', '.join(sorted(versions))}")

    packs = ALWAYS + [p for p in extra if p not in ALWAYS]

    targets = {Path("flake.nix"): render_flake(packs, versions),
               Path("repo.nix"): render_repo_nix(args.name, packs)}
    existing = [str(p) for p in targets if p.exists()]
    if existing:
        sys.exit(f"init: refusing to overwrite {', '.join(existing)}")

    for path, content in targets.items():
        path.write_text(content)
        print(f"init: wrote {path}")
    print("init: now run `nix run .#generate`")


if __name__ == "__main__":
    main()
