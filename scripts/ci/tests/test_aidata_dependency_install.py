"""Guard the aidata dependency install contract in CI."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve()
while not (ROOT / ".github/workflows/build.yml").is_file():
    if ROOT == ROOT.parent:
        raise RuntimeError("build workflow not found")
    ROOT = ROOT.parent

WORKFLOW = ROOT / ".github/workflows/build.yml"
LOCK = ROOT / "aidata/requirements.lock"


def _aidata_job() -> str:
    workflow = WORKFLOW.read_text(encoding="utf-8")
    return workflow.split("\n  aidata:\n", 1)[1].split("\n  swiftlint:\n", 1)[0]


def test_lock_exists_and_every_entry_is_exactly_pinned() -> None:
    entries = [
        line.strip()
        for line in LOCK.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]

    assert entries
    assert all(
        re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*==[^\s;*]+", entry)
        for entry in entries
    )


def test_lock_install_is_isolated_and_precedes_aidata_gates() -> None:
    job = _aidata_job()
    install = "run: python -m pip install --requirement aidata/requirements.lock"
    gate = "scripts/context/layers --group aidata"

    assert job.count(install) == 1
    assert job.index(install) < job.index(gate)


def test_dependency_install_uses_configured_source_without_floating_upgrade() -> None:
    job = _aidata_job()

    assert "--upgrade" not in job
    assert "--index-url" not in job
    assert "--extra-index-url" not in job


def test_existing_python_ruff_and_resolved_aidata_gates_are_preserved() -> None:
    job = _aidata_job()

    assert 'python-version: "3.13"' in job
    assert "python -m pip install pytest 'ruff==0.15.13'" in job
    assert "scripts/context/layers --group aidata" in job
    assert 'scripts/context/run "$layer" --mode ci' in job
