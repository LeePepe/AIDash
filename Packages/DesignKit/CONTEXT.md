---
{
  "schema": 1,
  "kind": "leaf",
  "layer": "DesignKit",
  "parent": "Packages/CONTEXT.md",
  "scope": ["DesignKit/**"],
  "dependencies": [],
  "dependents": ["AIDashUI", "AIDashApp"],
  "red_lines": [
    "Seed-derived colors and component tokens have one source in DesignKit.",
    "DesignKit has zero local package dependencies.",
    "Raw color values remain inside token sources, never feature views."
  ],
  "gates": [
    {"id": "spm-build", "kind": "build", "mode": "local", "command": ["swift", "build", "--package-path", "Packages/DesignKit"]},
    {"id": "spm-test", "kind": "test", "mode": "both", "command": ["swift", "test", "--package-path", "Packages/DesignKit"]}
  ],
  "manifest": {"kind": "swift-package", "path": "Packages/DesignKit/Package.swift", "local_dependencies": []},
  "reference": "Packages/DesignKit/tech-context.md"
}
---

# DesignKit

Owns the reusable seed color system, semantic palettes, and generic SwiftUI
components. Product-specific card meaning belongs in AIDashUI.
