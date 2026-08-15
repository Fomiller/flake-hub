#!/usr/bin/env python3
"""Execute a golden plan against a repository working tree.

Nix builds and validates the plan; this script only carries it out. It names
no file layout of its own: every path it touches comes from the plan.

Pass order is load-bearing. Retired paths are removed before anything is
written, so a path that moved between classes in the same release does not
get deleted after it was just written.
"""

import argparse
import json
import shutil
from pathlib import Path


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--files", required=True, type=Path)
    ap.add_argument("--plan", required=True, type=Path)
    ap.add_argument("--root", required=True, type=Path)
    args = ap.parse_args()

    plan = json.loads(args.plan.read_text())
    actions = 0

    for rel in plan["retired"]:
        actions += remove(args.root / rel, rel, "retired")

    for rel in plan["managed"]:
        src = args.files / rel
        if src.exists():
            actions += write(src, args.root / rel, rel, "managed")
        else:
            actions += remove(args.root / rel, rel, "gated off")

    for rel in plan["scaffold"]:
        dst = args.root / rel
        if dst.exists():
            continue
        src = args.files / rel
        if src.exists():
            actions += write(src, dst, rel, "scaffold")

    print(f"generate: {plan['repo']}: {actions} change(s)")


def write(src: Path, dst: Path, rel: str, why: str) -> int:
    new = src.read_bytes()
    if dst.exists() and dst.read_bytes() == new:
        return 0
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(src, dst)
    dst.chmod(0o644)
    print(f"  {why}: {rel}")
    return 1


def remove(dst: Path, rel: str, why: str) -> int:
    if not dst.exists():
        return 0
    dst.unlink()
    print(f"  {why}: removed {rel}")
    return 1


if __name__ == "__main__":
    main()
