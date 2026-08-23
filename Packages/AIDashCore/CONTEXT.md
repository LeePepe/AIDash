---
{
  "schema": 1,
  "kind": "leaf",
  "layer": "AIDashCore",
  "parent": "Packages/CONTEXT.md",
  "scope": ["AIDashCore/**"],
  "dependencies": [],
  "dependents": ["AIDashUI", "AIDashApp", "aidashCLI"],
  "red_lines": [
    "Schema types and payload validation have one source in AIDashCore.",
    "The CLI never accesses CloudKit directly.",
    "Production code uses graceful errors; fatalError, try!, and as! are forbidden.",
    "Concurrency escape hatches require an ADR."
  ],
  "gates": [
    {"id": "spm-build", "kind": "build", "mode": "local", "command": ["swift", "build", "--package-path", "Packages/AIDashCore"]},
    {"id": "spm-test", "kind": "test", "mode": "both", "command": ["swift", "test", "--package-path", "Packages/AIDashCore"]}
  ],
  "manifest": {"kind": "swift-package", "path": "Packages/AIDashCore/Package.swift", "local_dependencies": []},
  "reference": "Packages/AIDashCore/tech-context.md"
}
---

# AIDashCore

Owns domain models, payload schemas, validation, storage contracts, and XPC
envelopes. It has no local package dependency and no UI dependency. Read the
referenced technical context for model and role details.
