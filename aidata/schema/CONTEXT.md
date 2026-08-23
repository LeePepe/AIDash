---
{
  "schema": 1,
  "kind": "leaf",
  "layer": "AidataL3",
  "parent": "aidata/CONTEXT.md",
  "scope": ["merge.py", "schema/**"],
  "dependencies": ["AidataFoundation", "AidataL1L2"],
  "dependents": ["AidataL4", "AidataOps", "AidataIntegrationTests"],
  "red_lines": [
    "L3 merges normalized inputs; it does not recollect or renormalize sources.",
    "Warehouse facts preserve honest keys, grains, nullability, and additive measures.",
    "Generated warehouse databases are never tracked."
  ],
  "gates": []
}
---

# AidataL3

Owns the warehouse schema, dimensions, and merge implementation that combines
normalized source stores into the local analytical warehouse.
