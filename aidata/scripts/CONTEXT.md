---
{
  "schema": 1,
  "kind": "leaf",
  "layer": "AidataOps",
  "group": "aidata",
  "parent": "aidata/CONTEXT.md",
  "scope": ["scripts/**"],
  "test_paths": ["tests/test_cron_installer.py", "tests/test_runner_sources.py"],
  "dependencies": ["AidataFoundation", "AidataL1L2", "AidataL3", "AidataL5"],
  "dependents": [],
  "red_lines": [
    "Operational entrypoints preserve collect-normalize-merge-digest ordering.",
    "Cron execution and repository scripts remain synchronized at the documented deployment seam.",
    "Operational failures are observable and do not silently publish stale success."
  ],
  "gates": [
    {"id": "pytest-local", "kind": "test", "mode": "local", "command": ["/usr/bin/python3", "-m", "pytest", "{test_paths}", "-q"]},
    {"id": "pytest-ci", "kind": "test", "mode": "ci", "command": ["python3", "-m", "pytest", "{test_paths}", "-q"]},
    {"id": "ruff", "kind": "lint", "mode": "ci", "command": ["ruff", "check", "{owned_python_paths}"]}
  ]
}
---

# AidataOps

Owns cron and shell orchestration of the end-to-end aidata pipeline. It wires
existing stage APIs and does not absorb their business logic.
