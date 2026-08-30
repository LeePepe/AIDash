import hashlib
import importlib.util
import json
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


@pytest.mark.unit
def test_manual_import_degrades_to_zero_when_root_is_missing(monkeypatch: pytest.MonkeyPatch) -> None:
    config = _load_config(monkeypatch)
    config.TEAM_AUDIT_IMPORT_ROOT = "/definitely/missing/path"
    adapter = _load_adapter(monkeypatch, config)
    assert adapter.collect() == 0
    assert adapter.normalize() == 0


@pytest.mark.unit
def test_manual_import_collects_and_normalizes_collision_safe(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    config = _load_config(monkeypatch)
    config.TEAM_AUDIT_IMPORT_ROOT = str(tmp_path)
    adapter = _load_adapter(monkeypatch, config)

    import cleanio
    import rawio

    rawio.raw_source_dir = lambda source: tmp_path / "raw" / source
    cleanio.CLEAN_DIR = tmp_path / "clean"
    cleanio.clean_path = lambda source: cleanio.CLEAN_DIR / f"{source}.db"

    sidecar_payload = {
        "sidecarID": "sidecar:team:weekly:2026-09-01",
        "subjectID": "team:core-platform",
        "responsibilityLayer": "AidataL1L2",
        "artifacts": ["finding-brief.md"],
        "grill": ["what-was-the-root-cause"],
    }
    sidecar_text = json.dumps(sidecar_payload, ensure_ascii=False)
    sidecar_hash = hashlib.sha256(sidecar_text.encode("utf-8")).hexdigest()
    snapshot_payload = {
        "kind": "snapshot",
        "snapshotID": "audit:team:weekly:2026-09-01",
        "subjectID": "team:core-platform",
        "responsibilityLayer": "AidataL1L2",
        "mode": "baseline",
        "capturedAt": "2026-09-01T00:00:00Z",
        "cohort": "team-audit",
        "cursor": "sprint-42",
        "axes": ["quality", "velocity"],
        "feedbackLineage": ["T001", "T002"],
        "agentRepeat": ["reviewed-contract"],
        "limitations": ["manual import only"],
        "artifacts": ["finding-brief.md"],
        "grill": ["what-was-the-root-cause"],
        "sidecarID": "sidecar:team:weekly:2026-09-01",
        "sidecarHash": sidecar_hash,
        "schemaVersion": "team-audit/v1",
    }
    collision = {
        "kind": "snapshot",
        "snapshotID": "audit:team:weekly:2026-09-01",
        "subjectID": "team:core-platform",
        "responsibilityLayer": "AidataL1L2",
        "mode": "incremental",
        "capturedAt": "2026-09-01T00:05:00Z",
        "cohort": "team-audit",
        "cursor": "sprint-42",
        "axes": ["quality", "velocity"],
        "feedbackLineage": ["T001", "T002"],
        "agentRepeat": ["reviewed-contract"],
        "limitations": ["manual import only"],
        "artifacts": ["finding-brief.md"],
        "grill": ["what-was-the-root-cause"],
        "sidecarID": "sidecar:team:weekly:2026-09-01-collision",
        "sidecarHash": "placeholder",
        "schemaVersion": "team-audit/v1",
    }
    collision_sidecar = {
        "sidecarID": "sidecar:team:weekly:2026-09-01-collision",
        "subjectID": "team:core-platform",
        "responsibilityLayer": "AidataL1L2",
        "artifacts": ["finding-brief.md"],
        "grill": ["what-was-the-root-cause"],
    }
    collision_sidecar_text = json.dumps(collision_sidecar, ensure_ascii=False)
    collision_sidecar_hash = hashlib.sha256(collision_sidecar_text.encode("utf-8")).hexdigest()
    collision["sidecarHash"] = collision_sidecar_hash

    bundle_dir = tmp_path / "audit-bundle"
    bundle_dir.mkdir()
    (bundle_dir / "snapshot.json").write_text(json.dumps(snapshot_payload, ensure_ascii=False), encoding="utf-8")
    (bundle_dir / "artifacts.json").write_text(sidecar_text, encoding="utf-8")

    collision_dir = tmp_path / "audit-bundle-collision"
    collision_dir.mkdir()
    (collision_dir / "snapshot.json").write_text(json.dumps(collision, ensure_ascii=False), encoding="utf-8")
    (collision_dir / "artifacts.json").write_text(collision_sidecar_text, encoding="utf-8")

    written = adapter.collect()
    assert written == 2

    normalized = adapter.normalize()
    assert normalized == 1

    db = cleanio.clean_path("team_audit_snapshot")
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
    assert snapshot_rows[0][2] == "team:core-platform"
    assert snapshot_rows[0][3] == "AidataL1L2"
    assert "T002" in snapshot_rows[0][4]
    assert observation_rows[0][0] == "audit:team:weekly:2026-09-01"
    assert observation_rows[0][2] == "collision"
    assert observation_rows[0][3] == "audit:team:weekly:2026-09-01"
    assert observation_rows[0][4] != ""
    assert sidecar_rows[0][0] == "sidecar:team:weekly:2026-09-01"
    assert sidecar_rows[0][1] == sidecar_hash
