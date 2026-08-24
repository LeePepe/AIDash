---
{
  "schema": 1,
  "kind": "leaf",
  "layer": "AidataL3",
  "group": "aidata",
  "parent": "aidata/CONTEXT.md",
  "scope": ["merge.py", "schema/**"],
  "test_paths": ["tests/test_warehouse_integrity.py", "tests/test_warehouse_quality.py"],
  "dependencies": ["AidataFoundation", "AidataL1L2"],
  "dependents": ["AidataL4", "AidataOps", "AidataIntegrationTests"],
  "red_lines": [
    "L3 merges normalized inputs; it does not recollect or renormalize sources.",
    "Warehouse facts preserve honest keys, grains, nullability, and additive measures.",
    "Generated warehouse databases are never tracked."
  ],
  "gates": [
    {"id": "pytest-local", "kind": "test", "mode": "local", "command": ["/usr/bin/python3", "-m", "pytest", "{test_paths}", "-q"]},
    {"id": "pytest-ci", "kind": "test", "mode": "ci", "command": ["python3", "-m", "pytest", "{test_paths}", "-q"]},
    {"id": "ruff", "kind": "lint", "mode": "ci", "command": ["ruff", "check", "{owned_python_paths}"]}
  ]
}
---

# AidataL3

Owns the warehouse schema, dimensions, and merge implementation that combines
normalized source stores into the local analytical warehouse.
