#!/usr/bin/env python3
"""Seed a repo with the three files a flake-hub consumer holds.

Pins come from the promoted versions in renovate-config, one
versions/nix-flakes/<pack>.yaml per pack. Kargo writes those files only when a
pack is promoted, so a new repo starts on the same versions Renovate offers
existing ones. pack-versions.nix only lists which packs exist.
"""

import argparse
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

REPO = "github:Fomiller/flake-hub"
CATALOG = "https://raw.githubusercontent.com/Fomiller/renovate-config/main/versions/nix-flakes"
ALWAYS = ["golden-engine", "golden-base"]


def read_versions(path: Path) -> dict[str, str]:
    return dict(re.findall(r'^\s*([\w-]+)\s*=\s*"([^"]+)";', path.read_text(), re.M))


def promoted_version(catalog: str, pack: str) -> str:
    url = f"{catalog.rstrip('/')}/{pack}.yaml"
    try:
        with urllib.request.urlopen(url, timeout=30) as r:
            text = r.read().decode()
    except (urllib.error.URLError, OSError, ValueError) as e:
        sys.exit(f"init: cannot read the promoted version of {pack} from {url}: {e}")
    m = re.search(r'^version:\s*["\']?([^"\'\s]+)', text, re.M)
    if not m:
        sys.exit(f"init: no `version:` line in {url}")
    tag = m.group(1)
    if not tag.startswith(f"{pack}-"):
        sys.exit(f"init: {url} names tag {tag}, which is not a {pack} tag")
    return tag.removeprefix(f"{pack}-")


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
    ap.add_argument("--versions", type=Path, default=Path(__file__).parent / "pack-versions.nix",
                    help="lists the known packs; pins come from --catalog")
    ap.add_argument("--catalog", default=CATALOG, help="base URL of the promoted <pack>.yaml files")
    args = ap.parse_args()

    known = read_versions(args.versions)
    extra = [f"golden-{p.strip()}" for p in args.packs.split(",") if p.strip()]
    unknown = [p for p in extra if p not in known]
    if unknown:
        sys.exit(f"init: unknown pack(s): {', '.join(unknown)}. Known: {', '.join(sorted(known))}")

    packs = ALWAYS + [p for p in extra if p not in ALWAYS]
    versions = {p: promoted_version(args.catalog, p) for p in packs}

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
