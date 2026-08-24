---
{
  "schema": 1,
  "kind": "leaf",
  "layer": "AidataL4",
  "group": "aidata",
  "parent": "aidata/CONTEXT.md",
  "scope": ["serve.py", "L4_serve/**"],
  "test_paths": ["tests/test_card_interest_query.py", "tests/test_query_tiers.py", "tests/test_serve_attach.py"],
  "dependencies": ["AidataFoundation", "AidataL3"],
  "dependents": ["AidataL5", "AidataIntegrationTests"],
  "red_lines": [
    "L4 serves named read-only queries over L3 and never mutates the warehouse.",
    "Query output has an explicit grain and stable field contract.",
    "Missing local data degrades visibly instead of fabricating values."
  ],
  "gates": [
    {"id": "pytest-local", "kind": "test", "mode": "local", "command": ["/usr/bin/python3", "-m", "pytest", "{test_paths}", "-q"]},
    {"id": "pytest-ci", "kind": "test", "mode": "ci", "command": ["python3", "-m", "pytest", "{test_paths}", "-q"]},
    {"id": "ruff", "kind": "lint", "mode": "ci", "command": ["ruff", "check", "{owned_python_paths}"]}
  ]
}
---

# AidataL4

Owns the read-only serving facade and named SQL queries consumed by applications.
Business presentation and card mapping stay downstream in L5.
