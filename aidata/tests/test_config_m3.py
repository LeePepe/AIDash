import ast
import builtins
import importlib.util
import sqlite3
from pathlib import Path

import cleanio
import config
import pytest
from cli import _load_adapter


def _load_config_without_local(monkeypatch):
    real_import = builtins.__import__

    def import_without_local(name, *args, **kwargs):
        if name == "config_local":
            raise ImportError("config_local intentionally unavailable")
        return real_import(name, *args, **kwargs)

    monkeypatch.setattr(builtins, "__import__", import_without_local)
    spec = importlib.util.spec_from_file_location(
        "_config_without_local",
        Path(config.__file__),
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.mark.unit
def test_ado_pr_registered_in_sources_and_merge():
    assert "ado_pr" in config.SOURCES
    assert "ado_pr" in config.MERGE_SOURCES


@pytest.mark.unit
def test_icloud_token_sync_is_registered_and_reachable():
    assert "icloud_token_sync" in config.SOURCES
    assert "icloud_token_sync" in config.SCHEDULED_SOURCES
    adapter = _load_adapter("icloud_token_sync")
    assert adapter.SOURCE == "icloud_token_sync"
    assert callable(adapter.collect)
    assert callable(adapter.normalize)


@pytest.mark.unit
def test_linear_issue_registered_in_sources_and_merge():
    assert "linear_issue" in config.SOURCES
    assert "linear_issue" in config.MERGE_SOURCES
    assert "linear_issue" in config.SCHEDULED_SOURCES
    assert config.LINEAR_TEAM_KEY == "TIA"
    assert config.LINEAR_SYNC_SCRIPT.name == "linear-sync.py"
    assert isinstance(config.LINEAR_UPDATED_WINDOW_DAYS, int)
    assert config.LINEAR_UPDATED_WINDOW_DAYS >= 7
    assert config.TODO_SYNC_PROVIDER == "auto"
    assert config.TODO_SYNC_CONFIG_PATH.name == "todo-sync.json"
    assert config.LOCAL_TODOS_PATH.name == "local_todos.jsonl"


@pytest.mark.unit
def test_state_db_registered_in_sources_but_not_merged():
    # ADR-13: state.db stops at L2 clean, queried directly, never merged.
    assert "state_db" in config.SOURCES
    assert "state_db" not in config.MERGE_SOURCES


@pytest.mark.unit
def test_ado_constants_present():
    # The real values are per-account and live in the git-ignored
    # config_local.py, so this asserts SHAPE, not content: all five names exist
    # and are strings. Empty is a legal state — ado_pr then degrades to a no-op
    # (ADR-23), which test_ado_pr_adapter covers.
    for name in ("ADO_ORG", "ADO_PROJECT", "ADO_REPO",
                 "ADO_CREATOR_EMAIL", "ADO_CREATOR_ID"):
        assert hasattr(config, name), f"config.{name} missing"
        assert isinstance(getattr(config, name), str), f"config.{name} not str"


@pytest.mark.unit
def test_hermes_state_db_path():
    assert config.HERMES_STATE_DB.name == "state.db"


@pytest.mark.unit
def test_icloud_paths_and_resolution_are_hermetic(monkeypatch, tmp_path):
    assert config.ICLOUD_DRIVE_ROOT == config.HOME / "Library" / "Mobile Documents" / "com~apple~CloudDocs"
    assert config.ICLOUD_JOBS_DIR == config.AIDASH_ICLOUD_SYNC_DIR / "jobs"
    assert config.ICLOUD_SKILLS_MIRROR_DIR == config.AIDASH_ICLOUD_SYNC_DIR / "skills-mirror"
    assert config.ICLOUD_TELEMETRY_SHARDS_DIR == config.AIDASH_ICLOUD_SYNC_DIR / "telemetry-shards"

    monkeypatch.setenv("PYTEST_CURRENT_TEST", "test_icloud_paths")
    monkeypatch.delenv("AIDASH_ICLOUD_SYNC_DIR", raising=False)
    assert config.resolve_icloud_sync_dir() is None
    explicit = tmp_path / "icloud"
    assert config.resolve_icloud_sync_dir(explicit) == explicit
    assert config.icloud_sync_available(explicit)


@pytest.mark.unit
def test_icloud_environment_override_is_allowed_during_tests(monkeypatch, tmp_path):
    configured = tmp_path / "configured-icloud"
    monkeypatch.setenv("PYTEST_CURRENT_TEST", "test_icloud_environment_override")
    monkeypatch.setenv("AIDASH_ICLOUD_SYNC_DIR", str(configured))
    assert config.resolve_icloud_sync_dir() == configured
    assert config.icloud_sync_available()


@pytest.mark.unit
def test_icloud_disable_flag_and_bounded_probe_degrade_safely(monkeypatch, tmp_path):
    import subprocess

    explicit = tmp_path / "explicit-icloud"
    configured = tmp_path / "configured-icloud"
    monkeypatch.setenv("AIDASH_ICLOUD_SYNC_DIR", str(configured))
    monkeypatch.setenv("AIDASH_DISABLE_ICLOUD_MIRROR", "1")
    assert config.resolve_icloud_sync_dir() is None
    assert config.resolve_icloud_sync_dir(explicit) is None
    assert not config.icloud_sync_available(explicit)

    monkeypatch.delenv("AIDASH_DISABLE_ICLOUD_MIRROR", raising=False)
    monkeypatch.delenv("AIDASH_ICLOUD_SYNC_DIR", raising=False)
    monkeypatch.delenv("PYTEST_CURRENT_TEST", raising=False)
    cloud_docs = tmp_path / "CloudDocs"
    cloud_docs.mkdir()
    sync_dir = cloud_docs / "AIDashSync"
    monkeypatch.setattr(config, "ICLOUD_DRIVE_ROOT", cloud_docs)
    monkeypatch.setattr(config, "AIDASH_ICLOUD_SYNC_DIR", sync_dir)
    monkeypatch.setattr(config, "_ICLOUD_PROBE_CACHE", {})

    def timeout_run(*_args, **_kwargs):
        raise subprocess.TimeoutExpired(cmd="probe", timeout=1.5)

    monkeypatch.setattr(config.subprocess, "run", timeout_run)
    assert config.resolve_icloud_sync_dir() is None
    assert config._ICLOUD_PROBE_CACHE[sync_dir] is False

    monkeypatch.setattr(config, "_ICLOUD_PROBE_CACHE", {})
    monkeypatch.setattr(
        config.subprocess,
        "run",
        lambda *_args, **_kwargs: subprocess.CompletedProcess(args=["probe"], returncode=0),
    )
    assert config.resolve_icloud_sync_dir() == sync_dir
    assert config._ICLOUD_PROBE_CACHE[sync_dir] is True


@pytest.mark.unit
def test_fresh_config_import_disables_product_blob(monkeypatch):
    fresh_config = _load_config_without_local(monkeypatch)

    assert fresh_config.PRODUCT_BLOB_CONTAINER_URL == ""
    assert fresh_config.PRODUCT_BLOB_PREFIX == ""


@pytest.mark.unit
def test_product_blob_config_surface_has_no_auth_or_secret_fields(monkeypatch):
    fresh_config = _load_config_without_local(monkeypatch)
    config_fields = {
        name for name in vars(fresh_config) if name.startswith("PRODUCT_BLOB_")
    }
    assert config_fields == {
        "PRODUCT_BLOB_CONTAINER_URL",
        "PRODUCT_BLOB_PREFIX",
    }

    example_path = Path(config.__file__).with_name("config_local.example.py")
    assignments = {
        node.targets[0].id: ast.literal_eval(node.value)
        for node in ast.parse(example_path.read_text(encoding="utf-8")).body
        if (
            isinstance(node, ast.Assign)
            and len(node.targets) == 1
            and isinstance(node.targets[0], ast.Name)
            and node.targets[0].id.startswith("PRODUCT_BLOB_")
        )
    }
    assert assignments == {
        "PRODUCT_BLOB_CONTAINER_URL": "",
        "PRODUCT_BLOB_PREFIX": "",
    }


@pytest.mark.unit
def test_scheduled_sources_are_unique_and_registered():
    assert len(config.SCHEDULED_SOURCES) == len(set(config.SCHEDULED_SOURCES))
    assert set(config.SCHEDULED_SOURCES) <= set(config.SOURCES)
    assert "mail_inbox" in config.SOURCES
    assert "work_teams_bridge" in config.SOURCES
    assert config.MAIL_INBOX_ENABLE_JXA is False
    assert config.MAIL_INBOX_DROP_DIR.name == "mail-inbox-drop"
    assert config.WORK_TEAMS_DROP_DIR.name == "work-teams-drop"


@pytest.mark.unit
def test_product_blob_is_not_activated():
    for registry in (
        config.SOURCES,
        config.MERGE_SOURCES,
        config.SCHEDULED_SOURCES,
    ):
        assert "product_blob" not in registry


@pytest.mark.unit
def test_write_clean_replaces_duplicate_primary_keys(tmp_path, monkeypatch):
    monkeypatch.setattr(cleanio, "CLEAN_DIR", tmp_path)
    monkeypatch.setattr(cleanio, "clean_path", lambda source: tmp_path / f"{source}.db")

    ddl = "CREATE TABLE req (request_id TEXT PRIMARY KEY, value TEXT NOT NULL)"
    rows = [
        {"request_id": "req-1", "value": "first"},
        {"request_id": "req-1", "value": "latest"},
    ]

    assert cleanio.write_clean("fixture", "req", ddl, rows, ("request_id", "value")) == 2

    conn = sqlite3.connect(tmp_path / "fixture.db")
    stored = conn.execute("SELECT request_id, value FROM req").fetchall()
    conn.close()
    assert stored == [("req-1", "latest")]


@pytest.mark.unit
def test_unpriced_models_include_gateway_models():
    assert {
        "gpt-6.1-sol",
        "gpt-6.1-terra",
        "gpt-6-luna",
        "gemini-4-argon",
        "gemini-4-carbon",
        "microsoft-decision-1",
    } <= set(config.UNPRICED_MODELS)


@pytest.mark.unit
def test_raw_source_lock_serializes_concurrent_writes_and_times_out_when_held(tmp_path, monkeypatch):
    import fcntl

    import rawio

    monkeypatch.setattr(rawio, "raw_source_dir", lambda source: tmp_path / source)
    assert rawio.write_raw("fixture_src", [{"id": "r1"}], shard_date="2026-11-20") == 1
    source_dir = tmp_path / "fixture_src"
    assert (source_dir / ".source.lock").is_file()

    with (source_dir / ".source.lock").open("a+", encoding="utf-8") as held:
        fcntl.flock(held.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        try:
            with pytest.raises(TimeoutError), rawio.raw_source_lock(source_dir, timeout=0.05):
                pass
        finally:
            fcntl.flock(held.fileno(), fcntl.LOCK_UN)

