---
{
  "schema": 1,
  "kind": "leaf",
  "layer": "AidataIntegrationTests",
  "group": "aidata",
  "parent": "aidata/CONTEXT.md",
  "scope": [],
  "test_paths": ["tests/test_cst_day_contract.py"],
  "dependencies": ["AidataL3", "AidataL4"],
  "dependents": [],
  "red_lines": [
    "Tests are hermetic and pass without config_local.py or a local warehouse.",
    "Golden tests freeze every source seam used by the digest.",
    "Tests never contact external services or consume personal data."
  ],
  "gates": [
    {"id": "pytest-local", "kind": "test", "mode": "local", "command": ["/usr/bin/python3", "-m", "pytest", "{test_paths}", "-q"]},
    {"id": "pytest-ci", "kind": "test", "mode": "ci", "command": ["python3", "-m", "pytest", "{test_paths}", "-q"]},
    {"id": "ruff", "kind": "lint", "mode": "ci", "command": ["ruff", "check", "{owned_python_paths}"]}
  ]
}
---

# AidataIntegrationTests

Owns only cross-stage integration contracts. Unit, contract, and golden tests
resolve to the implementation leaf that owns the behavior they verify.
