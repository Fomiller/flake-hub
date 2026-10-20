import shutil
import subprocess
import sys
from pathlib import Path

INIT = Path(__file__).parent.parent / "init.py"
VERSIONS = Path(__file__).parent / "fixtures" / "pack-versions.nix"
CATALOG = Path(__file__).parent / "fixtures" / "catalog"


def run(cwd, *args, catalog=CATALOG, expect_fail=False):
    r = subprocess.run(
        [sys.executable, str(INIT), "--versions", str(VERSIONS),
         "--catalog", catalog.resolve().as_uri(), *args],
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


def test_github_pack_seeds_codeowners(tmp_path):
    run(tmp_path, "--name", "foo", "--packs", "github")
    assert 'github.codeowners = [ "@Fomiller" ];' in (tmp_path / "repo.nix").read_text()


def test_codeowners_is_absent_without_the_github_pack(tmp_path):
    run(tmp_path, "--name", "foo")
    assert (tmp_path / "repo.nix").read_text() == '{\n  name = "foo";\n}\n'


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


def test_a_pack_input_is_one_line(tmp_path):
    run(tmp_path, "--name", "foo", "--packs", "github")
    flake = (tmp_path / "flake.nix").read_text()
    assert ".follows" not in flake
    assert ".inputs." not in flake


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


def test_pins_come_from_the_catalog(tmp_path):
    run(tmp_path, "--name", "foo", "--packs", "github")
    flake = (tmp_path / "flake.nix").read_text()
    assert "ref=refs/tags/golden-base-0.4.2" in flake
    assert "ref=refs/tags/golden-engine-0.3.1" in flake
    assert "ref=refs/tags/golden-github-0.7.3" in flake
    assert "0.1.0" not in flake


def test_catalog_tag_for_another_pack_is_rejected(tmp_path):
    catalog = tmp_path / "catalog"
    shutil.copytree(CATALOG, catalog)
    f = catalog / "golden-base.yaml"
    f.write_text(f.read_text().replace("version: golden-base-", "version: golden-github-"))
    work = tmp_path / "work"
    work.mkdir()
    r = run(work, "--name", "foo", catalog=catalog, expect_fail=True)
    assert "golden-base" in r.stderr
    assert not (work / "flake.nix").exists()


def test_catalog_tag_for_a_longer_pack_name_is_rejected(tmp_path):
    catalog = tmp_path / "catalog"
    shutil.copytree(CATALOG, catalog)
    f = catalog / "golden-base.yaml"
    f.write_text(f.read_text().replace("version: golden-base-", "version: golden-base-mesh-"))
    work = tmp_path / "work"
    work.mkdir()
    r = run(work, "--name", "foo", catalog=catalog, expect_fail=True)
    assert "golden-base-mesh" in r.stderr
    assert not (work / "flake.nix").exists()


def test_missing_catalog_file_is_an_error(tmp_path):
    catalog = tmp_path / "catalog"
    shutil.copytree(CATALOG, catalog)
    (catalog / "golden-github.yaml").unlink()
    work = tmp_path / "work"
    work.mkdir()
    r = run(work, "--name", "foo", "--packs", "github", catalog=catalog, expect_fail=True)
    assert "golden-github" in r.stderr
    assert not (work / "flake.nix").exists()
