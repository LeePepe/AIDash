---
{
  "schema": 1,
  "kind": "index",
  "routes": [
    {"patterns": ["aidash/**"], "context": "aidash/CONTEXT.md"}
  ],
  "exclusions": [
    {"patterns": ["CONTEXT.md"], "reason": "CLI routing metadata."}
  ]
}
---

# CLI router

The macOS `aidash` executable is one leaf and remains a thin XPC client.
