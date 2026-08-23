---
{
  "schema": 1,
  "kind": "leaf",
  "layer": "AidataL4",
  "parent": "aidata/CONTEXT.md",
  "scope": ["serve.py", "L4_serve/**"],
  "dependencies": ["AidataFoundation", "AidataL3"],
  "dependents": ["AidataL5", "AidataIntegrationTests"],
  "red_lines": [
    "L4 serves named read-only queries over L3 and never mutates the warehouse.",
    "Query output has an explicit grain and stable field contract.",
    "Missing local data degrades visibly instead of fabricating values."
  ],
  "gates": []
}
---

# AidataL4

Owns the read-only serving facade and named SQL queries consumed by applications.
Business presentation and card mapping stay downstream in L5.
