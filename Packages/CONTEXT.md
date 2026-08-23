---
{
  "schema": 1,
  "kind": "index",
  "routes": [
    {"patterns": ["AIDashCore/**"], "context": "AIDashCore/CONTEXT.md"},
    {"patterns": ["DesignKit/**"], "context": "DesignKit/CONTEXT.md"},
    {"patterns": ["AIDashUI/**"], "context": "AIDashUI/CONTEXT.md"}
  ],
  "exclusions": [
    {"patterns": ["CONTEXT.md"], "reason": "Packages routing metadata."}
  ]
}
---

# Package router

Each Swift package is an independently gated leaf. Cross-package work is split
at these boundaries.
