import importlib.util
import shutil
import sqlite3
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
CONFIG_PATH = ROOT / "config.py"
ADAPTER_PATH = ROOT / "adapters" / "team_audit_snapshot.py"


def _load_config(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.delitem(sys.modules, "config", raising=False)
    spec = importlib.util.spec_from_file_location("config", CONFIG_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec is not None and spec.loader is not None
    spec.loader.exec_module(module)
    monkeypatch.setitem(sys.modules, "config", module)
    return module


def _load_adapter(monkeypatch: pytest.MonkeyPatch, config_module):
    spec = importlib.util.spec_from_file_location("team_audit_snapshot", ADAPTER_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec is not None and spec.loader is not None
    monkeypatch.setitem(sys.modules, "config", config_module)
    monkeypatch.setitem(sys.modules, "team_audit_snapshot", module)
    spec.loader.exec_module(module)
    return module


def _clear_generated_state() -> None:
    raw_dir = ROOT / "L1_collect" / "raw" / "team_audit_snapshot"
    clean_db = ROOT / "L2_normalize" / "clean" / "team_audit_snapshot.db"
    if raw_dir.exists():
        shutil.rmtree(raw_dir)
    if clean_db.exists():
        clean_db.unlink()


@pytest.mark.unit
def test_manual_import_degrades_to_zero_when_root_is_missing(monkeypatch: pytest.MonkeyPatch) -> None:
    _clear_generated_state()
    config = _load_config(monkeypatch)
    config.TEAM_AUDIT_IMPORT_ROOT = "/definitely/missing/path"
    adapter = _load_adapter(monkeypatch, config)
    assert adapter.collect() == 0
    assert adapter.normalize() == 0


@pytest.mark.unit
def test_manual_import_collects_and_normalizes_collision_safe(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    _clear_generated_state()
    config = _load_config(monkeypatch)
    config.TEAM_AUDIT_IMPORT_ROOT = str(tmp_path)
    adapter = _load_adapter(monkeypatch, config)

    bundle = {
        "kind": "snapshot",
        "identity": "audit:team:weekly:2026-09-01",
        "hash": "bundle-hash-v1",
        "cohort": "team-audit",
        "cursor": "sprint-42",
        "instruction_hash": "inst:hash:abc123",
        "axes": ["quality", "velocity"],
        "subject_id": "team:core-platform",
        "responsibility_layer": "AidataL1L2",
        "feedback_lineage": ["T001", "T002"],
        "agent_repeat": ["reviewed-contract"],
        "limitations": ["manual import only"],
        "artifacts": ["finding-brief.md"],
        "grill": ["what-was-the-root-cause"],
        "sidecar_id": "sidecar:team:weekly:2026-09-01",
        "sidecar_hash": "sidecar-hash-v1",
    }
    collision = {
        "kind": "snapshot",
        "identity": "audit:team:weekly:2026-09-01",
        "hash": "bundle-hash-v2",
        "parent_snapshot_id": "audit:team:weekly:2026-09-01",
        "parent_snapshot_hash": "bundle-hash-v1",
        "observation_kind": "collision",
        "detail": "replayed snapshot differs from accepted parent",
    }

    (tmp_path / "bundle.json").write_text(__import__("json").dumps({**bundle, "children": [collision]}, ensure_ascii=False), encoding="utf-8")

    written = adapter.collect()
    assert written == 2

    normalized = adapter.normalize()
    assert normalized == 1

    db = ROOT / "L2_normalize" / "clean" / "team_audit_snapshot.db"
    assert db.exists()
    with sqlite3.connect(db) as conn:
        snapshot_rows = conn.execute(
            "SELECT identity, content_hash, subject_id, responsibility_layer, feedback_lineage FROM snapshot"
        ).fetchall()
        observation_rows = conn.execute(
            "SELECT identity, content_hash, observation_kind, parent_snapshot_id, parent_snapshot_hash FROM observation"
        ).fetchall()
        sidecar_rows = conn.execute(
            "SELECT sidecar_id, sidecar_hash, snapshot_id FROM sidecar"
        ).fetchall()

    assert snapshot_rows[0][0] == "audit:team:weekly:2026-09-01"
    assert snapshot_rows[0][1] == "bundle-hash-v1"
    assert snapshot_rows[0][2] == "team:core-platform"
    assert snapshot_rows[0][3] == "AidataL1L2"
    assert "T002" in snapshot_rows[0][4]
    assert observation_rows[0][0] == "audit:team:weekly:2026-09-01"
    assert observation_rows[0][1] == "bundle-hash-v2"
    assert observation_rows[0][2] == "collision"
    assert observation_rows[0][3] == "audit:team:weekly:2026-09-01"
    assert observation_rows[0][4] == "bundle-hash-v1"
    assert sidecar_rows[0][0] == "sidecar:team:weekly:2026-09-01"
    assert sidecar_rows[0][1] == "sidecar-hash-v1"
