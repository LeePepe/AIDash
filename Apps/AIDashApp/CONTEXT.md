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
    "Product telemetry is explicit-consent, GUI-only, and retains its lifetime identity and pending work when disabled.",
    "Only aidash.action and aidash.performance.ready_scene are admitted; no reset or identity rotation surface exists.",
    "Local tests use only the hostless AIDashAppLogicTests scheme.",
    "Host-based AIDashAppTests run only in CI or with explicit user authorization.",
    "MenuBar NSHostingView panels must place .padding inside .frame(width:) so fittingSize.width equals frame.width, hide duplicate summary NSMenuItems (isHidden = true), and keep Localizable.xcstrings locale sets complete so no raw keys leak."
  ],
  "gates": [
    {"id": "generate-hostless-project", "kind": "check", "mode": "local", "command": ["xcodegen", "generate"]},
    {"id": "hostless-logic-tests", "kind": "test", "mode": "local", "command": ["xcodebuild", "-scheme", "AIDashAppLogicTests", "-destination", "platform=macOS", "-clonedSourcePackagesDirPath", ".build/xcode-packages", "-disablePackageRepositoryCache", "-scmProvider", "system", "CODE_SIGNING_ALLOWED=NO", "EXCLUDED_SOURCE_FILE_NAMES=AppBootstrapTests.swift", "test"]},
    {"id": "macos-build", "kind": "build", "mode": "ci", "command": ["xcodebuild", "-scheme", "AIDashApp", "-destination", "platform=macOS", "CODE_SIGNING_ALLOWED=NO", "build"]},
    {"id": "ios-build", "kind": "build", "mode": "ci", "command": ["xcodebuild", "-scheme", "AIDashApp", "-destination", "generic/platform=iOS", "CODE_SIGNING_ALLOWED=NO", "build"]}
  ],
  "manifest": {"kind": "xcodegen-target", "path": "project.yml", "target": "AIDashApp", "local_dependencies": ["AIDashCore", "AIDashUI", "DesignKit", "shared-telemetry"]}
}
---

# AIDashApp

Owns app lifecycle, scenes, menu bar behavior, sync, XPC service, launchd
installation, resources, entitlements, and app-target tests. Workspace target
wiring belongs to XcodeWorkspace.

macOS fixed installs run sandboxed with `AIDashApp.macOS.fixed.entitlements`.
Host-home telemetry reads must use `getpwuid(getuid())` guarded by
`XCTestConfigurationFilePath == nil`; read-only path exceptions must be
declared in both macOS entitlement files, and WAL SQLite databases must
include a `mode=ro&immutable=1` URI fallback.
