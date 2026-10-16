"""Guard the aidata dependency install contract in CI."""

from pathlib import Path
import re
import shlex


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


def _install_command(job: str) -> str:
    prefix = "run: python -m pip install "
    matches = [
        line.strip()
        for line in job.splitlines()
        if line.strip().startswith(prefix)
    ]
    assert matches == [
        "run: python -m pip install --requirement aidata/requirements.lock",
        "run: python -m pip install pytest 'ruff==0.15.13'",
    ]
    return matches[0].removeprefix("run: ")


def _has_forbidden_pip_option(command: str) -> bool:
    arguments = shlex.split(command)
    return any(
        argument in {"--upgrade", "-U", "--index-url", "--extra-index-url"}
        or argument.startswith(("-i", "--index-url=", "--extra-index-url="))
        for argument in arguments
    )


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
    install = _install_command(job)
    repo_infra_gate = "scripts/context/run RepoInfra --mode ci"
    gate = "scripts/context/layers --group aidata"

    assert job.count(repo_infra_gate) == 1
    assert job.index(install) < job.index(repo_infra_gate) < job.index(gate)


def test_dependency_install_uses_configured_source_without_floating_upgrade() -> None:
    install = _install_command(_aidata_job())

    assert not _has_forbidden_pip_option(install)


def test_dependency_install_rejects_equivalent_short_and_long_flags() -> None:
    base = "python -m pip install --requirement aidata/requirements.lock"

    for option in (
        "--upgrade",
        "-U",
        "--index-url https://example.invalid/simple",
        "--index-url=https://example.invalid/simple",
        "-i https://example.invalid/simple",
        "-ihttps://example.invalid/simple",
        "--extra-index-url https://example.invalid/simple",
        "--extra-index-url=https://example.invalid/simple",
    ):
        assert _has_forbidden_pip_option(f"{base} {option}")


def test_existing_python_ruff_and_resolved_aidata_gates_are_preserved() -> None:
    job = _aidata_job()

    assert 'python-version: "3.13"' in job
    assert "python -m pip install pytest 'ruff==0.15.13'" in job
    assert "scripts/context/layers --group aidata" in job
    assert 'scripts/context/run "$layer" --mode ci' in job
