---
{
  "schema": 1,
  "kind": "leaf",
  "layer": "AidataL1L2",
  "parent": "aidata/CONTEXT.md",
  "scope": ["adapters/**"],
  "dependencies": ["AidataFoundation"],
  "dependents": ["AidataL3", "AidataOps", "AidataIntegrationTests"],
  "red_lines": [
    "Adapters are the honest combined L1/L2 seam: each source owns collect and normalize together.",
    "Collection is read-only against external sources and raw output is append-only.",
    "Adapters do not import downstream L3, L4, or L5 code.",
    "Unconfigured sources return zero and preserve pipeline progress."
  ],
  "gates": []
}
---

# AidataL1L2

Owns all source adapters, including collection into raw records and the paired
normalization into source-clean data. Splitting these files into fictional L1
and L2 leaves would misstate the implementation.
