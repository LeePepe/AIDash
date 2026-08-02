import pytest

import config


@pytest.mark.unit
def test_ado_pr_registered_in_sources_and_merge():
    assert "ado_pr" in config.SOURCES
    assert "ado_pr" in config.MERGE_SOURCES


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
