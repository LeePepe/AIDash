"""Hermetic regression tests for scripts/verify (RG-001..RG-004) and scripts/install_local_app.sh."""

from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
VERIFY_SCRIPT = ROOT / "scripts/verify"
INSTALL_LOCAL_SCRIPT = ROOT / "scripts/install_local_app.sh"
PRE_PUSH_HOOK = ROOT / "scripts/hooks/pre-push"


def _isolated_git_env() -> dict[str, str]:
    env = os.environ.copy()
    for key in list(env):
        if key.startswith("GIT_"):
            env.pop(key, None)
    return env


def test_verify_and_install_local_app_are_executable_and_valid_syntax():
    assert VERIFY_SCRIPT.is_file()
    assert VERIFY_SCRIPT.stat().st_mode & 0o111
    subprocess.run(["bash", "-n", str(VERIFY_SCRIPT)], check=True)

    assert INSTALL_LOCAL_SCRIPT.is_file()
    assert INSTALL_LOCAL_SCRIPT.stat().st_mode & 0o111
    subprocess.run(["bash", "-n", str(INSTALL_LOCAL_SCRIPT)], check=True)

    subprocess.run(["bash", "-n", str(PRE_PUSH_HOOK)], check=True)


def test_verify_help_and_install_local_app_dry_run():
    help_proc = subprocess.run(
        [str(VERIFY_SCRIPT), "--help"],
        cwd=ROOT,
        env=_isolated_git_env(),
        capture_output=True,
        text=True,
        check=True,
    )
    assert "--changed" in help_proc.stdout
    assert "--all" in help_proc.stdout

    dry_proc = subprocess.run(
        [str(INSTALL_LOCAL_SCRIPT), "--dry-run", "--with-preview-host"],
        cwd=ROOT,
        env=_isolated_git_env(),
        capture_output=True,
        text=True,
        check=True,
    )
    assert "install-fixed-build.sh" in dry_proc.stdout
    assert "AIDashPreviewHost" in dry_proc.stdout


def test_verify_changed_and_all_in_hermetic_git_repo(tmp_path: Path):
    repo = tmp_path / "repo"
    (repo / "scripts" / "context").mkdir(parents=True)
    shutil.copy2(VERIFY_SCRIPT, repo / "scripts" / "verify")
    (repo / "scripts" / "verify").chmod(0o755)

    records = tmp_path / "records"
    records.mkdir()

    (repo / "scripts" / "context" / "audit").write_text(
        f"#!/bin/sh\nprintf 'audit\\n' >> '{records}/audit.log'\n",
        encoding="utf-8",
    )
    (repo / "scripts" / "context" / "audit").chmod(0o755)

    (repo / "scripts" / "context" / "layers").write_text(
        f"#!/bin/sh\n"
        f"if [ \"${{1:-}}\" = \"--all\" ]; then\n"
        f"  printf 'RepoInfra\\nDesignKit\\nAIDashCore\\nAidataL5\\n'\n"
        f"  exit 0\n"
        f"fi\n"
        f"cat > '{records}/layers_stdin.log'\n"
        f"printf 'RepoInfra\\n'\n",
        encoding="utf-8",
    )
    (repo / "scripts" / "context" / "layers").chmod(0o755)

    (repo / "scripts" / "context" / "run").write_text(
        f"#!/bin/sh\nprintf '%s\\n' \"$*\" >> '{records}/run.log'\n",
        encoding="utf-8",
    )
    (repo / "scripts" / "context" / "run").chmod(0o755)

    env = _isolated_git_env()
    subprocess.run(["git", "init", "-q"], cwd=repo, env=env, check=True)
    subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=repo, env=env, check=True)
    subprocess.run(["git", "config", "user.name", "Verify Test"], cwd=repo, env=env, check=True)

    (repo / "README.md").write_text("base\n", encoding="utf-8")
    subprocess.run(["git", "add", "README.md", "scripts"], cwd=repo, env=env, check=True)
    subprocess.run(["git", "commit", "-qm", "base"], cwd=repo, env=env, check=True)
    base_sha = subprocess.run(
        ["git", "rev-parse", "HEAD"], cwd=repo, env=env, capture_output=True, text=True, check=True
    ).stdout.strip()
    subprocess.run(["git", "update-ref", "refs/remotes/origin/main", base_sha], cwd=repo, env=env, check=True)

    # Modify a file and commit on feature branch
    (repo / "README.md").write_text("updated\n", encoding="utf-8")
    subprocess.run(["git", "add", "README.md"], cwd=repo, env=env, check=True)
    subprocess.run(["git", "commit", "-qm", "change readme"], cwd=repo, env=env, check=True)

    res_changed = subprocess.run(
        [str(repo / "scripts" / "verify"), "--changed"],
        cwd=repo,
        env=env,
        capture_output=True,
        text=True,
        check=True,
    )
    assert "[verify] ok:" in res_changed.stdout
    assert "README.md" in (records / "layers_stdin.log").read_text(encoding="utf-8")
    assert "RepoInfra --mode local" in (records / "run.log").read_text(encoding="utf-8")

    (records / "run.log").unlink()
    res_all = subprocess.run(
        [str(repo / "scripts" / "verify"), "--all"],
        cwd=repo,
        env=env,
        capture_output=True,
        text=True,
        check=True,
    )
    assert "[verify] ok: all" in res_all.stdout
    run_lines = (records / "run.log").read_text(encoding="utf-8").splitlines()
    assert run_lines == [
        "RepoInfra --mode local",
        "DesignKit --mode local",
        "AIDashCore --mode local",
        "AidataL5 --mode local",
    ]
