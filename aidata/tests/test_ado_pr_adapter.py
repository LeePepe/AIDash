"""Hermetic unit tests for adapters/ado_pr — no live az auth required.

subprocess/az and the raw/clean IO are monkeypatched, so these prove the
filter/normalize logic and the degrade-not-crash paths deterministically.

The ADO_* constants are monkeypatched too (autouse `_configured`): the real
values live in the git-ignored config_local.py, so tests must never depend on
them being set. test_collect_degrades_when_unconfigured covers the opposite.
"""

import json

import pytest

import adapters.ado_pr as ado


MY_ID = "00000000-0000-0000-0000-000000000001"

_PR_MINE = {
    "pullRequestId": 6887926,
    "title": "feat(ABC-123): autosuggest",
    "status": "active",
    "creationDate": "2026-07-09T05:45:37.395565+00:00",
    "closedDate": None,
    "isDraft": False,
    "sourceRefName": "refs/heads/me/abc-123",
    "targetRefName": "refs/heads/dev/main",
    "createdBy": {"id": MY_ID, "uniqueName": "me@example.com"},
    "reviewers": [{"displayName": "Someone", "vote": 10}],
    "repository": {"name": "InternalRepo"},
}
_PR_OTHER = {
    "pullRequestId": 999,
    "title": "not mine",
    "status": "active",
    "creationDate": "2026-07-09T01:00:00+00:00",
    "createdBy": {"id": "other-id-0000", "uniqueName": "someone@example.com"},
    "repository": {"name": "InternalRepo"},
}


@pytest.fixture(autouse=True)
def _configured(monkeypatch):
    """Give the adapter a complete ADO config so tests never read the real one."""
    monkeypatch.setattr(ado, "ADO_ORG", "https://example.visualstudio.com/DefaultCollection")
    monkeypatch.setattr(ado, "ADO_PROJECT", "MyProject")
    monkeypatch.setattr(ado, "ADO_REPO", "InternalRepo")
    monkeypatch.setattr(ado, "ADO_CREATOR_EMAIL", "me@example.com")
    monkeypatch.setattr(ado, "ADO_CREATOR_ID", MY_ID)


class _Proc:
    def __init__(self, rc: int, out: str):
        self.returncode = rc
        self.stdout = out
        self.stderr = ""


@pytest.mark.unit
def test_collect_filters_to_my_creator_id(monkeypatch):
    monkeypatch.setattr(ado.shutil, "which", lambda _: "/usr/bin/az")
    monkeypatch.setattr(
        ado.subprocess, "run",
        lambda *a, **k: _Proc(0, json.dumps([_PR_MINE, _PR_OTHER])),
    )
    captured = {}

    def _cap_snap(source, records):
        captured["recs"] = records
        return len(records)

    monkeypatch.setattr(ado, "write_raw_snapshot", _cap_snap)
    n = ado.collect()
    assert n == 1
    ids = [r["pullRequestId"] for r in captured["recs"]]
    assert ids == [6887926]  # only my immutable creator id survives


@pytest.mark.unit
def test_collect_degrades_when_unconfigured(monkeypatch):
    # ADR-23: on a machine with no config_local.py the ADO_* constants are ""
    # — collect must return 0 without ever shelling out to az.
    monkeypatch.setattr(ado, "ADO_ORG", "")
    monkeypatch.setattr(ado, "ADO_REPO", "")
    monkeypatch.setattr(ado, "ADO_CREATOR_ID", "")
    monkeypatch.setattr(ado.shutil, "which",
                        lambda _: pytest.fail("must not probe for az when unconfigured"))
    monkeypatch.setattr(ado, "write_raw_snapshot",
                        lambda *a, **k: pytest.fail("should not write"))
    assert ado.collect() == 0


@pytest.mark.unit
def test_collect_degrades_when_az_missing(monkeypatch):
    monkeypatch.setattr(ado.shutil, "which", lambda _: None)
    called = {"wrote": False}
    monkeypatch.setattr(ado, "write_raw_snapshot",
                        lambda *a, **k: called.__setitem__("wrote", True))
    assert ado.collect() == 0
    assert called["wrote"] is False


@pytest.mark.unit
def test_collect_degrades_on_az_error(monkeypatch):
    monkeypatch.setattr(ado.shutil, "which", lambda _: "/usr/bin/az")
    monkeypatch.setattr(ado.subprocess, "run", lambda *a, **k: _Proc(1, ""))
    monkeypatch.setattr(ado, "write_raw_snapshot",
                        lambda *a, **k: pytest.fail("should not write on error"))
    assert ado.collect() == 0


@pytest.mark.unit
def test_collect_degrades_on_bad_json(monkeypatch):
    monkeypatch.setattr(ado.shutil, "which", lambda _: "/usr/bin/az")
    monkeypatch.setattr(ado.subprocess, "run", lambda *a, **k: _Proc(0, "not json"))
    monkeypatch.setattr(ado, "write_raw_snapshot",
                        lambda *a, **k: pytest.fail("should not write"))
    assert ado.collect() == 0


@pytest.mark.unit
def test_normalize_last_write_wins_and_fields(monkeypatch):
    active = dict(_PR_MINE)
    completed = dict(_PR_MINE)
    completed["status"] = "completed"
    completed["closedDate"] = "2026-07-10T09:00:00+00:00"
    monkeypatch.setattr(ado, "read_raw", lambda source: [active, completed])
    captured = {}

    def _cap_clean(source, table, ddl, rows, cols):
        captured["rows"] = rows
        return len(rows)

    monkeypatch.setattr(ado, "write_clean", _cap_clean)
    n = ado.normalize()
    assert n == 1
    row = captured["rows"][0]
    assert row["status"] == "completed"           # last write wins
    assert row["closed_date"] == "2026-07-10T09:00:00+00:00"
    assert row["source_branch"] == "me/abc-123"  # refs/heads/ stripped
    assert row["target_branch"] == "dev/main"
    assert row["is_draft"] == 0                    # bool -> int
    assert isinstance(row["reviewers"], str)       # JSON-encoded
    assert json.loads(row["reviewers"])[0]["vote"] == 10
    assert row["created_date"] == "2026-07-09T05:45:37.395565+00:00"  # ISO passthrough
    assert isinstance(row["age_hours"], (int, float))
    assert row["repo"] == "InternalRepo"


@pytest.mark.unit
def test_normalize_empty_raw_is_zero(monkeypatch):
    monkeypatch.setattr(ado, "read_raw", lambda source: [])
    monkeypatch.setattr(ado, "write_clean",
                        lambda source, table, ddl, rows, cols: len(rows))
    assert ado.normalize() == 0
