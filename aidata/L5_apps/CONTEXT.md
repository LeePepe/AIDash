---
{
  "schema": 1,
  "kind": "leaf",
  "layer": "AidataL5",
  "group": "aidata",
  "parent": "aidata/CONTEXT.md",
  "scope": ["L5_apps/**"],
  "test_paths": ["tests/fixtures/**", "tests/test_aidash_payload.py", "tests/test_aidash_push.py", "tests/test_aidash_radar.py", "tests/test_batch2_cards.py", "tests/test_briefing_budget.py", "tests/test_card_interest_card.py", "tests/test_card_policy.py", "tests/test_cost_attribution.py", "tests/test_cost_improvement_card.py", "tests/test_cst.py", "tests/test_digest_aidash.py", "tests/test_digest_freshness.py", "tests/test_digest_golden.py", "tests/test_digest_llm.py", "tests/test_fixture_completeness.py", "tests/test_inbox.py", "tests/test_llm.py", "tests/test_metric_dedup.py", "tests/test_multica_completed.py", "tests/test_must_see.py", "tests/test_polish.py", "tests/test_proposals.py", "tests/test_relationship_sources.py", "tests/test_render.py", "tests/test_render_m3.py", "tests/test_render_multica.py", "tests/test_repo_radar_enrichment.py", "tests/test_sources.py", "tests/test_sources_m3.py", "tests/test_todo_rules.py", "tests/test_todo_truncation.py", "tests/test_trends.py", "tests/test_value_efficiency_card.py", "tests/test_verify.py", "tests/test_work_by_project_card.py"],
  "dependencies": ["AidataFoundation", "AidataL4"],
  "dependents": ["AidataOps"],
  "red_lines": [
    "L5 maps real upstream values into schema-valid briefing payloads; it does not invent absent data.",
    "Payload shapes remain aligned with AIDashCore and the rendering contract.",
    "Publishing shells out to aidash and remains best-effort; Python never accesses CloudKit."
  ],
  "gates": [
    {"id": "pytest-local", "kind": "test", "mode": "local", "command": ["/usr/bin/python3", "-m", "pytest", "{test_paths}", "-q"]},
    {"id": "pytest-ci", "kind": "test", "mode": "ci", "command": ["python3", "-m", "pytest", "{test_paths}", "-q"]},
    {"id": "ruff", "kind": "lint", "mode": "ci", "command": ["ruff", "check", "{owned_python_paths}"]}
  ]
}
---

# AidataL5

Owns digest source assembly, policy, rendering, optional polish, payload mapping,
and best-effort publication through the `aidash` executable.
