---
{
  "schema": 1,
  "kind": "index",
  "routes": [
    {"patterns": ["CONTEXT.foundation.md", "README.md", "tech-context.md", "pytest.ini", "cli.py", "cleanio.py", "config.py", "config_local.example.py", "rawio.py", "redaction.py", "sqlite_ro.py", "state.py", "timeutil.py", "docs/**"], "test_paths": ["tests/__init__.py", "tests/test_config_m3.py", "tests/test_config_multica.py", "tests/test_team_audit_manual_source.py", "tests/test_timeutil.py"], "context": "CONTEXT.foundation.md"},
    {"patterns": ["adapters/**"], "test_paths": ["tests/test_ado_pr_adapter.py", "tests/test_aidash_events_adapter.py", "tests/test_browser_history_adapter.py", "tests/test_claude_jsonl_adapter.py", "tests/test_claude_prompts_adapter.py", "tests/test_codex_prompts_adapter.py", "tests/test_gecko_adapter.py", "tests/test_github_pr_adapter.py", "tests/test_github_repo_adapter.py", "tests/test_hermes_messages_adapter.py", "tests/test_hermes_tools_adapter.py", "tests/test_kimi_prompts_adapter.py", "tests/test_local_git_adapter.py", "tests/test_model_canon.py", "tests/test_multica_comment_adapter.py", "tests/test_multica_issue_collect.py", "tests/test_multica_run_collect.py", "tests/test_multica_shared.py", "tests/test_news_adapter.py", "tests/test_raven_cost.py", "tests/test_state_db_adapter.py", "tests/test_team_audit_adapter.py"], "context": "adapters/CONTEXT.md"},
    {"patterns": ["merge.py", "schema/**"], "test_paths": ["tests/test_warehouse_integrity.py", "tests/test_warehouse_quality.py"], "context": "schema/CONTEXT.md"},
    {"patterns": ["serve.py", "L4_serve/**"], "test_paths": ["tests/test_card_interest_query.py", "tests/test_query_tiers.py", "tests/test_serve_attach.py"], "context": "L4_serve/CONTEXT.md"},
    {"patterns": ["L5_apps/**"], "test_paths": ["tests/fixtures/**", "tests/test_aidash_payload.py", "tests/test_aidash_push.py", "tests/test_aidash_radar.py", "tests/test_batch2_cards.py", "tests/test_briefing_budget.py", "tests/test_card_interest_card.py", "tests/test_card_policy.py", "tests/test_cost_attribution.py", "tests/test_cost_improvement_card.py", "tests/test_cst.py", "tests/test_delivery_health.py", "tests/test_digest_aidash.py", "tests/test_digest_freshness.py", "tests/test_digest_golden.py", "tests/test_digest_llm.py", "tests/test_fixture_completeness.py", "tests/test_inbox.py", "tests/test_llm.py", "tests/test_metric_dedup.py", "tests/test_multica_completed.py", "tests/test_must_see.py", "tests/test_polish.py", "tests/test_proposals.py", "tests/test_relationship_sources.py", "tests/test_render.py", "tests/test_render_m3.py", "tests/test_render_multica.py", "tests/test_repo_radar_enrichment.py", "tests/test_sources.py", "tests/test_sources_m3.py", "tests/test_todo_rules.py", "tests/test_todo_truncation.py", "tests/test_trends.py", "tests/test_value_efficiency_card.py", "tests/test_verify.py", "tests/test_work_by_project_card.py"], "context": "L5_apps/CONTEXT.md"},
    {"patterns": ["scripts/**"], "test_paths": ["tests/test_cron_installer.py", "tests/test_runner_sources.py"], "context": "scripts/CONTEXT.md"},
    {"patterns": [], "test_paths": ["tests/test_cst_day_contract.py"], "context": "tests/CONTEXT.md"}
  ],
  "exclusions": [
    {"patterns": ["CONTEXT.md", "tests/CONTEXT.md"], "reason": "aidata routing metadata."}
  ]
}
---

# aidata router

Route implementation and its tests to the same stage leaf. Only tests that
exercise multiple stage contracts remain in the integration-test leaf.
