---
{
  "schema": 1,
  "kind": "index",
  "routes": [
    {"patterns": ["AIDashApp/**"], "context": "AIDashApp/CONTEXT.md"}
  ],
  "exclusions": [
    {"patterns": ["CONTEXT.md"], "reason": "App routing metadata."}
  ]
}
---

# App router

App target changes resolve to the AIDashApp leaf. Workspace wiring remains in
the XcodeWorkspace leaf.
