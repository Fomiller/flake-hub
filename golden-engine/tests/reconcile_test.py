import json
import subprocess
import sys
from pathlib import Path

RECONCILE = Path(__file__).parent.parent / "lib" / "reconcile.py"


def run(tmp_path, plan, files):
    files_dir = tmp_path / "files"
    root = tmp_path / "root"
    for rel, content in files.items():
        p = files_dir / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(content)
    root.mkdir(exist_ok=True)
    plan_path = tmp_path / "plan.json"
    plan_path.write_text(json.dumps(plan))
    subprocess.run(
        [sys.executable, str(RECONCILE), "--files", str(files_dir),
         "--plan", str(plan_path), "--root", str(root)],
        check=True,
    )
    return root


def base_plan(**kw):
    plan = {"repo": "t", "managed": [], "scaffold": [], "retired": [],
            "unmanaged": [], "executable": []}
    plan.update(kw)
    return plan


def test_managed_file_is_written(tmp_path):
    root = run(tmp_path, base_plan(managed=[".gitignore"]), {".gitignore": "a\n"})
    assert (root / ".gitignore").read_text() == "a\n"


def test_managed_file_overwrites_local_edit(tmp_path):
    root = tmp_path / "root"
    root.mkdir()
    (root / ".gitignore").write_text("hand edited\n")
    run(tmp_path, base_plan(managed=[".gitignore"]), {".gitignore": "a\n"})
    assert (root / ".gitignore").read_text() == "a\n"


def test_managed_path_absent_from_files_is_deleted(tmp_path):
    root = tmp_path / "root"
    root.mkdir()
    (root / "Dockerfile").write_text("stale\n")
    run(tmp_path, base_plan(managed=["Dockerfile"]), {})
    assert not (root / "Dockerfile").exists()


def test_scaffold_file_is_written_when_absent(tmp_path):
    root = run(tmp_path, base_plan(scaffold=["cmd/main.go"]), {"cmd/main.go": "package main\n"})
    assert (root / "cmd" / "main.go").read_text() == "package main\n"


def test_scaffold_file_is_left_alone_when_present(tmp_path):
    root = tmp_path / "root"
    root.mkdir()
    (root / "cmd").mkdir()
    (root / "cmd" / "main.go").write_text("mine\n")
    run(tmp_path, base_plan(scaffold=["cmd/main.go"]), {"cmd/main.go": "package main\n"})
    assert (root / "cmd" / "main.go").read_text() == "mine\n"


def test_retired_file_is_deleted(tmp_path):
    root = tmp_path / "root"
    root.mkdir()
    (root / "old.yml").write_text("x\n")
    run(tmp_path, base_plan(retired=["old.yml"]), {})
    assert not (root / "old.yml").exists()


# reconcile.py never reads plan["unmanaged"] — plan.nix drops those paths before
# the plan is written. So this covers the reconcile half only: a rendered file the
# plan does not classify is not copied out. The unmanaged classification itself is
# covered by testUnmanagedPathLeavesManagedList and golden-base's render-customized.
def test_unclassified_file_is_not_written(tmp_path):
    root = tmp_path / "root"
    root.mkdir()
    (root / "Dockerfile").write_text("mine\n")
    run(tmp_path, base_plan(), {"Dockerfile": "generated\n"})
    assert (root / "Dockerfile").read_text() == "mine\n"


def test_executable_path_lands_0755_and_others_0644(tmp_path):
    root = run(
        tmp_path,
        base_plan(managed=["scripts/next.sh", "README.md"], executable=["scripts/next.sh"]),
        {"scripts/next.sh": "#!/bin/sh\n", "README.md": "hi\n"},
    )
    assert (root / "scripts" / "next.sh").stat().st_mode & 0o777 == 0o755
    assert (root / "README.md").stat().st_mode & 0o777 == 0o644


def test_wrong_mode_is_corrected_when_content_already_matches(tmp_path):
    plan = base_plan(managed=["scripts/next.sh"], executable=["scripts/next.sh"])
    files = {"scripts/next.sh": "#!/bin/sh\n"}
    root = run(tmp_path, plan, files)
    (root / "scripts" / "next.sh").chmod(0o644)
    run(tmp_path, plan, files)
    assert (root / "scripts" / "next.sh").stat().st_mode & 0o777 == 0o755


def test_dropping_a_path_from_executable_takes_the_bit_back(tmp_path):
    files = {"scripts/next.sh": "#!/bin/sh\n"}
    run(tmp_path, base_plan(managed=["scripts/next.sh"], executable=["scripts/next.sh"]), files)
    root = run(tmp_path, base_plan(managed=["scripts/next.sh"]), files)
    assert (root / "scripts" / "next.sh").stat().st_mode & 0o777 == 0o644


def test_second_run_changes_nothing(tmp_path):
    plan = base_plan(managed=[".gitignore"], scaffold=["cmd/main.go"])
    files = {".gitignore": "a\n", "cmd/main.go": "package main\n"}
    root = run(tmp_path, plan, files)
    before = {p: p.read_bytes() for p in root.rglob("*") if p.is_file()}
    run(tmp_path, plan, files)
    after = {p: p.read_bytes() for p in root.rglob("*") if p.is_file()}
    assert before == after
