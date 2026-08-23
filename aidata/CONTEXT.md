---
{
  "schema": 1,
  "kind": "index",
  "routes": [
    {"patterns": ["CONTEXT.foundation.md", "README.md", "tech-context.md", "pytest.ini", "cli.py", "cleanio.py", "config.py", "config_local.example.py", "rawio.py", "redaction.py", "sqlite_ro.py", "state.py", "timeutil.py", "docs/**"], "context": "CONTEXT.foundation.md"},
    {"patterns": ["adapters/**"], "context": "adapters/CONTEXT.md"},
    {"patterns": ["merge.py", "schema/**"], "context": "schema/CONTEXT.md"},
    {"patterns": ["serve.py", "L4_serve/**"], "context": "L4_serve/CONTEXT.md"},
    {"patterns": ["L5_apps/**"], "context": "L5_apps/CONTEXT.md"},
    {"patterns": ["scripts/**"], "context": "scripts/CONTEXT.md"},
    {"patterns": ["tests/**"], "context": "tests/CONTEXT.md"}
  ],
  "exclusions": [
    {"patterns": ["CONTEXT.md"], "reason": "aidata routing metadata."}
  ]
}
---

# aidata router

Route by the stage that owns the file. Adapters are one honest L1/L2 leaf
because each adapter intentionally owns collection and normalization together.
