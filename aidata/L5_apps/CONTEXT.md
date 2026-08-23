---
{
  "schema": 1,
  "kind": "leaf",
  "layer": "AidataL5",
  "parent": "aidata/CONTEXT.md",
  "scope": ["L5_apps/**"],
  "dependencies": ["AidataFoundation", "AidataL4"],
  "dependents": ["AidataOps", "AidataIntegrationTests"],
  "red_lines": [
    "L5 maps real upstream values into schema-valid briefing payloads; it does not invent absent data.",
    "Payload shapes remain aligned with AIDashCore and the rendering contract.",
    "Publishing shells out to aidash and remains best-effort; Python never accesses CloudKit."
  ],
  "gates": []
}
---

# AidataL5

Owns digest source assembly, policy, rendering, optional polish, payload mapping,
and best-effort publication through the `aidash` executable.
