---
{
  "schema": 1,
  "kind": "leaf",
  "layer": "AidataIntegrationTests",
  "parent": "aidata/CONTEXT.md",
  "scope": ["tests/**"],
  "dependencies": ["AidataFoundation", "AidataL1L2", "AidataL3", "AidataL4", "AidataL5", "AidataOps"],
  "dependents": [],
  "red_lines": [
    "Tests are hermetic and pass without config_local.py or a local warehouse.",
    "Golden tests freeze every source seam used by the digest.",
    "Tests never contact external services or consume personal data."
  ],
  "gates": [
    {"id": "pytest-local", "kind": "test", "mode": "local", "command": ["/usr/bin/python3", "-m", "pytest", "aidata/tests", "-q"]},
    {"id": "pytest-ci", "kind": "test", "mode": "ci", "command": ["python3", "-m", "pytest", "aidata/tests", "-q"]}
  ]
}
---

# AidataIntegrationTests

Owns hermetic unit, contract, golden, and optional local-warehouse integration
tests across the Python pipeline.
