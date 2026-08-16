"""The reference tables are generated into a marked region so the prose around
them survives. These tests cover the region rewrite, which is the only part
with a way to go wrong silently."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))
from gen_reference import replace_region  # noqa: E402

BEGIN = "<!-- BEGIN GENERATED REFERENCE -->"
END = "<!-- END GENERATED REFERENCE -->"


def test_region_content_is_replaced():
    doc = f"intro\n\n{BEGIN}\nold\n{END}\n\noutro\n"
    out = replace_region(doc, "new")
    assert "old" not in out
    assert "new" in out


def test_prose_outside_the_region_survives():
    doc = f"intro\n\n{BEGIN}\nold\n{END}\n\noutro\n"
    out = replace_region(doc, "new")
    assert out.startswith("intro")
    assert out.rstrip().endswith("outro")


def test_missing_markers_is_an_error():
    try:
        replace_region("no markers here\n", "new")
    except ValueError as e:
        assert "marker" in str(e)
    else:
        raise AssertionError("expected ValueError")


def test_rewrite_is_idempotent():
    doc = f"{BEGIN}\nold\n{END}\n"
    once = replace_region(doc, "new")
    assert replace_region(once, "new") == once
