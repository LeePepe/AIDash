from __future__ import annotations

import json
from pathlib import Path

from L5_apps.digest import skills_roi_snapshot


def test_normal_snapshot_path_loads_quality_sections(tmp_path, monkeypatch):
    report = Path(__file__).parent / "fixtures" / "skills_roi_report.json"
    warehouse = tmp_path / "warehouse.db"
    warehouse.write_bytes(b"fixture")
    monkeypatch.delenv("PYTEST_CURRENT_TEST", raising=False)
    monkeypatch.setattr(
        skills_roi_snapshot,
        "load_snapshot_from_warehouse",
        lambda _path: {
            "behavior": {"skills": [{"skill": "team-lead", "coverage_status": "covered"}]},
            "judge": {"coverage_label": "1/1", "skills": []},
        },
    )
    output = tmp_path / "snapshot.json"
    payload = skills_roi_snapshot.write_snapshot(
        output,
        report,
        warehouse_db=warehouse,
        skills_repo=tmp_path / "skills",
        usage_jsonl=tmp_path / "usage.jsonl",
        clean_dir=tmp_path / "clean",
        raw_dir=tmp_path / "raw",
        query_runner=lambda _name, _params: (
            [("2026-11-11", "copilot_cli_skill", "team-lead", 1, 1)],
            ["day", "source", "skill", "n", "sessions"],
        ),
        icloud_sync_dir=tmp_path / "icloud",
    )
    assert payload["quality_behavior"] == [{"skill": "team-lead", "coverage_status": "covered"}]
    assert payload["quality_judge"]["coverage_label"] == "1/1"
    assert json.loads(output.read_text(encoding="utf-8"))["quality_judge"]["coverage_label"] == "1/1"
