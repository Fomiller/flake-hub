import subprocess
import sys
from pathlib import Path

INIT = Path(__file__).parent.parent / "init.py"
VERSIONS = Path(__file__).parent / "fixtures" / "pack-versions.nix"


def run(cwd, *args, expect_fail=False):
    r = subprocess.run(
        [sys.executable, str(INIT), "--versions", str(VERSIONS), *args],
        cwd=cwd, capture_output=True, text=True,
    )
    if expect_fail:
        assert r.returncode != 0, r.stdout
    else:
        assert r.returncode == 0, r.stderr
    return r


def test_writes_both_files(tmp_path):
    run(tmp_path, "--name", "foo")
    assert (tmp_path / "flake.nix").exists()
    assert (tmp_path / "repo.nix").exists()


def test_repo_nix_carries_the_name(tmp_path):
    run(tmp_path, "--name", "foo")
    assert 'name = "foo";' in (tmp_path / "repo.nix").read_text()


def test_base_and_engine_are_always_inputs(tmp_path):
    run(tmp_path, "--name", "foo")
    flake = (tmp_path / "flake.nix").read_text()
    assert "dir=golden-engine&ref=refs/tags/golden-engine-" in flake
    assert "dir=golden-base&ref=refs/tags/golden-base-" in flake


def test_extra_packs_are_added_as_inputs(tmp_path):
    run(tmp_path, "--name", "foo", "--packs", "github,service")
    flake = (tmp_path / "flake.nix").read_text()
    assert "golden-github.url" in flake
    assert "golden-service.url" in flake


def test_pack_inputs_follow_the_consumers_engine_and_nixpkgs(tmp_path):
    run(tmp_path, "--name", "foo", "--packs", "github")
    flake = (tmp_path / "flake.nix").read_text()
    for pack in ("golden-base", "golden-github"):
        assert f'{pack}.inputs.nixpkgs.follows = "nixpkgs";' in flake
        assert f'{pack}.inputs.golden-engine.follows = "golden-engine";' in flake
    assert "golden-engine.inputs." not in flake


def test_commented_out_pack_is_not_a_known_pack(tmp_path):
    r = run(tmp_path, "--name", "foo", "--packs", "legacy", expect_fail=True)
    assert "golden-legacy" in r.stderr


def test_unknown_pack_is_rejected(tmp_path):
    r = run(tmp_path, "--name", "foo", "--packs", "nonsense", expect_fail=True)
    assert "nonsense" in r.stderr


def test_refuses_to_clobber_existing_files(tmp_path):
    (tmp_path / "repo.nix").write_text("{ name = \"mine\"; }\n")
    run(tmp_path, "--name", "foo", expect_fail=True)
    assert (tmp_path / "repo.nix").read_text() == "{ name = \"mine\"; }\n"
