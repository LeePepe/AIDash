import ast
import builtins
import importlib.util
from pathlib import Path

import config
import pytest


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
