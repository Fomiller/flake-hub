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
    executable = set(plan["executable"])
    actions = 0

    def mode_of(rel: str) -> int:
        return 0o755 if rel in executable else 0o644

    for rel in plan.get("retiredTrees", []):
        actions += remove_tree(args.root / rel, rel)

    for rel in plan["retired"]:
        actions += remove(args.root / rel, rel, "retired")

    for rel in plan["managed"]:
        src = args.files / rel
        if src.exists():
            actions += write(src, args.root / rel, rel, "managed", mode_of(rel))
        else:
            actions += remove(args.root / rel, rel, "gated off")

    for rel in plan["scaffold"]:
        dst = args.root / rel
        if dst.exists():
            continue
        src = args.files / rel
        if src.exists():
            actions += write(src, dst, rel, "scaffold", mode_of(rel))

    print(f"generate: {plan['repo']}: {actions} change(s)")


def write(src: Path, dst: Path, rel: str, why: str, mode: int) -> int:
    new = src.read_bytes()
    # A wrong mode counts as drift on its own. Returning early here on matching
    # bytes would leave it uncorrected and report the repo clean.
    if dst.exists() and dst.read_bytes() == new:
        if dst.stat().st_mode & 0o777 == mode:
            return 0
        dst.chmod(mode)
        print(f"  {why}: mode {mode:o} {rel}")
        return 1
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(src, dst)
    dst.chmod(mode)
    print(f"  {why}: {rel}")
    return 1


def remove_tree(dst: Path, rel: str) -> int:
    # Hand-written files go too. That is the point of a gate being off: the
    # directory is not part of this repo any more.
    if not dst.is_dir():
        return 0
    shutil.rmtree(dst)
    print(f"  retired tree: removed {rel}/")
    return 1


def remove(dst: Path, rel: str, why: str) -> int:
    if not dst.exists():
        return 0
    dst.unlink()
    print(f"  {why}: removed {rel}")
    return 1


if __name__ == "__main__":
    main()
