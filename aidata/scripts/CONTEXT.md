---
{
  "schema": 1,
  "kind": "leaf",
  "layer": "AidataOps",
  "parent": "aidata/CONTEXT.md",
  "scope": ["scripts/**"],
  "dependencies": ["AidataFoundation", "AidataL1L2", "AidataL3", "AidataL5"],
  "dependents": ["AidataIntegrationTests"],
  "red_lines": [
    "Operational entrypoints preserve collect-normalize-merge-digest ordering.",
    "Cron execution and repository scripts remain synchronized at the documented deployment seam.",
    "Operational failures are observable and do not silently publish stale success."
  ],
  "gates": []
}
---

# AidataOps

Owns cron and shell orchestration of the end-to-end aidata pipeline. It wires
existing stage APIs and does not absorb their business logic.
