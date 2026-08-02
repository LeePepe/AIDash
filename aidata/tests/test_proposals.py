"""Tests for the agent-proposal inbox reader (§M3, 待决策 bucket)."""

import json
import pytest

from L5_apps.digest.proposals import read_pending, _coerce, Proposal


def _write(tmp_path, records):
    p = tmp_path / "proposals.jsonl"
    p.write_text("\n".join(json.dumps(r, ensure_ascii=False) for r in records),
                 encoding="utf-8")
    return p


VALID = {"id": "p1", "ts": "2026-07-18T04:00:00Z", "agent": "pm-agent",
         "title": "立项：拆分 digest pane"}


@pytest.mark.unit
def test_reads_pending_proposal(tmp_path):
    p = _write(tmp_path, [VALID])
    out = read_pending(p)
    assert len(out) == 1
    assert out[0].id == "p1"
    assert out[0].agent == "pm-agent"
    assert out[0].priority == "medium"   # default
    assert out[0].status == "pending"    # default


@pytest.mark.unit
def test_missing_file_returns_empty(tmp_path):
    assert read_pending(tmp_path / "nope.jsonl") == []


@pytest.mark.unit
def test_skips_malformed_lines(tmp_path):
    p = tmp_path / "proposals.jsonl"
    p.write_text('{"bad json\n' + json.dumps(VALID) + "\nnot even json\n",
                 encoding="utf-8")
    out = read_pending(p)
    assert len(out) == 1                  # only the valid line survives


@pytest.mark.unit
def test_requires_core_fields(tmp_path):
    p = _write(tmp_path, [{"id": "x", "ts": "t", "agent": "a"}])  # no title
    assert read_pending(p) == []


@pytest.mark.unit
def test_last_occurrence_wins_drops_approved(tmp_path):
    approved = dict(VALID, status="approved")
    p = _write(tmp_path, [VALID, approved])   # same id, later = approved
    assert read_pending(p) == []              # no longer pending


@pytest.mark.unit
def test_only_pending_surface(tmp_path):
    p = _write(tmp_path, [VALID, dict(VALID, id="p2", status="dismissed")])
    out = read_pending(p)
    assert [x.id for x in out] == ["p1"]


@pytest.mark.unit
def test_coerce_normalizes_bad_priority():
    prop = _coerce(dict(VALID, priority="URGENT"))
    assert prop.priority == "medium"      # invalid → default


@pytest.mark.unit
def test_coerce_rejects_non_dict():
    assert _coerce("just a string") is None
