---
{
  "schema": 1,
  "kind": "leaf",
  "layer": "XcodeWorkspace",
  "parent": "CONTEXT.md",
  "scope": ["Configs/**", "fastlane/**", "project.yml"],
  "dependencies": [],
  "dependents": [],
  "red_lines": [
    "project.yml is the Xcode target and scheme source; regenerate the project after changes.",
    "Tracked identity configuration contains placeholders only.",
    "The hostless AIDashAppLogicTests target remains separate from host-based AIDashAppTests.",
    "Local automation never runs the host-based AIDashAppTests target."
  ],
  "gates": [
    {"id": "generate", "kind": "check", "mode": "ci", "command": ["xcodegen", "generate"]}
  ]
}
---

# XcodeWorkspace

Owns XcodeGen target and scheme wiring, build identity defaults, entitlements
configuration, and release automation. App and CLI source code have separate
leaves.
