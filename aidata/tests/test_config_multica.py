import pytest

from config import MULTICA_WORKSPACES, MULTICA_UPDATED_WINDOW_DAYS


@pytest.mark.unit
def test_multica_workspaces_shape():
    # ADR-5: an explicit ALLOW-LIST of (uuid, friendly_name), never "all
    # workspaces". The real ids are per-account and live in the git-ignored
    # config_local.py, so this asserts shape + the allow-list invariants that
    # hold regardless of which workspaces are configured.
    assert isinstance(MULTICA_WORKSPACES, tuple)
    for entry in MULTICA_WORKSPACES:
        assert isinstance(entry, tuple) and len(entry) == 2, entry
        ws_id, name = entry
        assert isinstance(ws_id, str) and ws_id, entry
        assert isinstance(name, str) and name, entry
    ids = [ws_id for ws_id, _ in MULTICA_WORKSPACES]
    assert len(ids) == len(set(ids)), "duplicate workspace id — watermarks would collide"
    names = [name for _, name in MULTICA_WORKSPACES]
    assert len(names) == len(set(names)), "duplicate friendly name — digest rows would merge"


@pytest.mark.unit
def test_multica_updated_window_days_is_positive_int():
    assert isinstance(MULTICA_UPDATED_WINDOW_DAYS, int)
    assert MULTICA_UPDATED_WINDOW_DAYS >= 7
