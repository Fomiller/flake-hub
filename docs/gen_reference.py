#!/usr/bin/env python3
"""Rewrite the generated reference region in each flake page.

Nix renders the tables; this only splices them in, so the prose around the
markers stays hand-written.
"""

import argparse
import json
from pathlib import Path

BEGIN = "<!-- BEGIN GENERATED REFERENCE -->"
END = "<!-- END GENERATED REFERENCE -->"


def replace_region(doc: str, body: str) -> str:
    if BEGIN not in doc or END not in doc:
        raise ValueError(f"page is missing the {BEGIN} / {END} marker pair")
    head, rest = doc.split(BEGIN, 1)
    _, tail = rest.split(END, 1)
    return f"{head}{BEGIN}\n{body.strip()}\n{END}{tail}"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--tables", required=True, type=Path)
    ap.add_argument("--pages-dir", required=True, type=Path)
    args = ap.parse_args()

    tables = json.loads(args.tables.read_text())
    for pack, body in tables.items():
        page = args.pages_dir / f"{pack}.md"
        if not page.exists():
            raise SystemExit(f"gen-reference: no page for {pack} at {page}")
        page.write_text(replace_region(page.read_text(), body))
        print(f"gen-reference: updated {page}")


if __name__ == "__main__":
    main()
