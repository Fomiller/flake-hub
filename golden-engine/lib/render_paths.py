#!/usr/bin/env python3
"""Rename rendered paths whose names carry {{ key }} components.

makejinja renders file contents but copies path names through untouched. The
plan applies the same substitution on the Nix side, so the two agree on where
a file ends up. Only top-level strings are substituted, which is what
pathvars.nix does too.
"""

import json
import os
import sys
from pathlib import Path


def main() -> None:
    out = Path(sys.argv[1])
    data = json.loads(Path(sys.argv[2]).read_text())
    subs = {f"{{{{ {k} }}}}": v for k, v in data.items() if isinstance(v, str)}

    # Bottom-up, so a directory is renamed only after its contents are done.
    for root, dirs, files in os.walk(out, topdown=False):
        for name in dirs + files:
            new = name
            for old, value in subs.items():
                new = new.replace(old, value)
            if new != name:
                os.rename(Path(root) / name, Path(root) / new)


if __name__ == "__main__":
    main()
