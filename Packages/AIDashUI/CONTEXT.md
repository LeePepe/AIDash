---
{
  "schema": 1,
  "kind": "leaf",
  "layer": "AIDashUI",
  "parent": "Packages/CONTEXT.md",
  "scope": ["AIDashUI/**"],
  "dependencies": ["AIDashCore", "DesignKit"],
  "dependents": ["AIDashApp"],
  "red_lines": [
    "AIDashUI renders typed Core payloads and does not own persistence or CloudKit.",
    "Card type, size, and style remain orthogonal.",
    "Views consume DesignKit tokens; they do not inline signal colors.",
    "View-layer code is MainActor-isolated by default."
  ],
  "gates": [
    {"id": "spm-build", "kind": "build", "mode": "local", "command": ["swift", "build", "--package-path", "Packages/AIDashUI"]},
    {"id": "spm-test", "kind": "test", "mode": "both", "command": ["swift", "test", "--package-path", "Packages/AIDashUI"]}
  ],
  "manifest": {"kind": "swift-package", "path": "Packages/AIDashUI/Package.swift", "local_dependencies": ["AIDashCore", "DesignKit"]},
  "reference": "Packages/AIDashUI/tech-context.md"
}
---

# AIDashUI

Owns cross-platform briefing, container, card, and feedback views. It consumes
Core contracts and DesignKit tokens and contains no app lifecycle code.
