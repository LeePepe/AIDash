import csv
import shutil
import sqlite3

import merge

EXPECTED_RULES = [
    ("client", "multica-agent-sdk", "automated"),
    ("client", "codex_exec", "automated"),
    ("client", "codex-tui", "interactive"),
    ("originator", "codex_exec", "automated"),
    ("cwd_prefix", "~/Development/worktrees/", "automated"),
    ("cwd_prefix", "~/Development/handoff/", "automated"),
    ("cwd_prefix", "/private/tmp/herdr-", "automated"),
]


def test_merge_loads_automation_rules_and_expands_home(tmp_path, monkeypatch):
    schema_dir = tmp_path / "schema"
    schema_dir.mkdir()
    shutil.copy(merge.SCHEMA_DIR / "warehouse.sql", schema_dir / "warehouse.sql")
    with (schema_dir / "automation_rules.csv").open(
        "w", newline="", encoding="utf-8"
    ) as fh:
        writer = csv.writer(fh)
        writer.writerow(("kind", "match", "class", "note"))
        writer.writerows((*rule, "test") for rule in EXPECTED_RULES)

    warehouse = tmp_path / "warehouse.db"
    monkeypatch.setattr(merge, "SCHEMA_DIR", schema_dir)
    monkeypatch.setattr(merge, "WAREHOUSE_DB", warehouse)
    monkeypatch.setattr(merge, "clean_path", lambda source: tmp_path / f"{source}.db")
    monkeypatch.setenv("HOME", "/hermetic-home")

    assert merge.run_merge()["dim_automation_rule"] == len(EXPECTED_RULES)

    conn = sqlite3.connect(warehouse)
    rows = conn.execute(
        "SELECT kind, match, class FROM dim_automation_rule ORDER BY rowid"
    ).fetchall()
    conn.close()

    expected = [
        (
            kind,
            "/hermetic-home" + match[1:]
            if kind == "cwd_prefix" and match.startswith("~")
            else match,
            rule_class,
        )
        for kind, match, rule_class in EXPECTED_RULES
    ]
    assert rows == expected
