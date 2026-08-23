---
{
  "schema": 1,
  "kind": "leaf",
  "layer": "AidataFoundation",
  "parent": "aidata/CONTEXT.md",
  "scope": ["CONTEXT.foundation.md", "README.md", "tech-context.md", "pytest.ini", "cli.py", "cleanio.py", "config.py", "config_local.example.py", "rawio.py", "redaction.py", "sqlite_ro.py", "state.py", "timeutil.py", "docs/**"],
  "dependencies": [],
  "dependents": ["AidataL1L2", "AidataL3", "AidataL4", "AidataL5", "AidataOps", "AidataIntegrationTests"],
  "red_lines": [
    "Tracked configuration contains neutral empty defaults; identities stay in ignored config_local.py.",
    "Missing sources and configuration degrade to a no-op rather than crashing.",
    "Raw and clean I/O preserves redaction and append-only guarantees."
  ],
  "gates": [],
  "reference": "aidata/tech-context.md"
}
---

# AidataFoundation

Owns shared configuration, redaction, state, safe I/O, time, and CLI utilities
used across the Python pipeline. It contains no source-specific business logic.
