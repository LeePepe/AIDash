---
{
  "schema": 1,
  "kind": "leaf",
  "layer": "aidashCLI",
  "parent": "CLI/CONTEXT.md",
  "scope": ["aidash/**"],
  "dependencies": ["AIDashCore"],
  "dependents": [],
  "red_lines": [
    "The CLI is a thin macOS XPC client and never talks to CloudKit directly.",
    "The CLI imports AIDashCore only; it never imports AIDashUI or DesignKit.",
    "Errors use the contracted stderr JSON envelope and exit-code taxonomy."
  ],
  "gates": [
    {"id": "macos-build", "kind": "build", "mode": "ci", "command": ["xcodebuild", "-scheme", "aidash", "-destination", "platform=macOS", "CODE_SIGNING_ALLOWED=NO", "build"]}
  ],
  "manifest": {"kind": "xcodegen-target", "path": "project.yml", "target": "aidash", "local_dependencies": ["AIDashCore"]}
}
---

# aidashCLI

Owns argument parsing, payload file resolution, output formatting, app launch,
and XPC client behavior. Command changes carry success and validation tests.
