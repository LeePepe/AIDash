---
{
  "schema": 1,
  "kind": "leaf",
  "layer": "AidataL1L2",
  "group": "aidata",
  "parent": "aidata/CONTEXT.md",
  "scope": ["adapters/**"],
  "test_paths": ["tests/test_ado_pr_adapter.py", "tests/test_aidash_events_adapter.py", "tests/test_browser_history_adapter.py", "tests/test_claude_jsonl_adapter.py", "tests/test_claude_prompts_adapter.py", "tests/test_codex_prompts_adapter.py", "tests/test_gecko_adapter.py", "tests/test_github_pr_adapter.py", "tests/test_github_repo_adapter.py", "tests/test_hermes_messages_adapter.py", "tests/test_hermes_tools_adapter.py", "tests/test_kimi_prompts_adapter.py", "tests/test_local_git_adapter.py", "tests/test_model_canon.py", "tests/test_multica_comment_adapter.py", "tests/test_multica_issue_collect.py", "tests/test_multica_run_collect.py", "tests/test_multica_shared.py", "tests/test_news_adapter.py", "tests/test_raven_cost.py", "tests/test_state_db_adapter.py", "tests/test_team_audit_adapter.py"],
  "dependencies": ["AidataFoundation"],
  "dependents": ["AidataL3", "AidataOps"],
  "red_lines": [
    "Adapters are the honest combined L1/L2 seam: each source owns collect and normalize together.",
    "Collection is read-only against external sources and raw output is append-only.",
    "Adapters do not import downstream L3, L4, or L5 code.",
    "Unconfigured sources return zero and preserve pipeline progress."
  ],
  "gates": [
    {"id": "pytest-local", "kind": "test", "mode": "local", "command": ["/usr/bin/python3", "-m", "pytest", "{test_paths}", "-q"]},
    {"id": "pytest-ci", "kind": "test", "mode": "ci", "command": ["python3", "-m", "pytest", "{test_paths}", "-q"]},
    {"id": "ruff", "kind": "lint", "mode": "ci", "command": ["ruff", "check", "{owned_python_paths}"]}
  ]
}
---

# AidataL1L2

Owns all source adapters, including collection into raw records and the paired
normalization into source-clean data. Splitting these files into fictional L1
and L2 leaves would misstate the implementation.
