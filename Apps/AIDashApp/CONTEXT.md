---
{
  "schema": 1,
  "kind": "leaf",
  "layer": "AIDashApp",
  "parent": "Apps/CONTEXT.md",
  "scope": ["AIDashApp/**"],
  "dependencies": ["AIDashCore", "AIDashUI", "DesignKit"],
  "dependents": [],
  "red_lines": [
    "The app reads briefings and writes append-only user events; it never authors briefing content.",
    "The app owns the sole CloudKit identity and XPC server endpoint.",
    "Local tests use only the hostless AIDashAppLogicTests scheme.",
    "Host-based AIDashAppTests run only in CI or with explicit user authorization."
  ],
  "gates": [
    {"id": "macos-build", "kind": "build", "mode": "ci", "command": ["xcodebuild", "-scheme", "AIDashApp", "-destination", "platform=macOS", "CODE_SIGNING_ALLOWED=NO", "build"]},
    {"id": "ios-build", "kind": "build", "mode": "ci", "command": ["xcodebuild", "-scheme", "AIDashApp", "-destination", "generic/platform=iOS", "CODE_SIGNING_ALLOWED=NO", "build"]}
  ],
  "manifest": {"kind": "xcodegen-target", "path": "project.yml", "target": "AIDashApp", "local_dependencies": ["AIDashCore", "AIDashUI", "DesignKit"]}
}
---

# AIDashApp

Owns app lifecycle, scenes, menu bar behavior, sync, XPC service, launchd
installation, resources, entitlements, and app-target tests. Workspace target
wiring belongs to XcodeWorkspace.
