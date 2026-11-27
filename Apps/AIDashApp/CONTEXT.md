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
    "Only aidash.action, aidash.performance.ready_scene, and aidash.performance.scroll_hitch are admitted; no reset or identity rotation surface exists.",
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

macOS workspace navigation uses a 3-Section `NavigationSplitView` sidebar
(`总览与进化` / `Goal 与工作流` / `Skills 武器库`). Section 2
(`GoalWorkStreamWorkbenchView` + `WorkStatusWorkbenchSnapshot`) consumes
`aidash-work-status/v1` (`work-status.json` with read-only `warehouse.db`
`fact_session_work_summary` fallback), rendering Goal-aggregated expandable
rows, 4-segment action bars, skill hit/empty-load chips, concrete file/PR
outputs, and a 1-page `SessionWorkReceiptSheet` without raw prompt spans or
bare internal codes, alongside Native 120Hz `PreviewHost` `v01..v04` variants.

macOS fixed installs run sandboxed with `AIDashApp.macOS.fixed.entitlements`.
Host-home telemetry reads must use `getpwuid(getuid())` guarded by
`XCTestConfigurationFilePath == nil`; read-only path exceptions must be
declared in both macOS entitlement files, and WAL SQLite databases must
include a `mode=ro&immutable=1` URI fallback.

Skills ROI is an App-owned read-only typed projection (`SkillsRoiReport`) of the
canonical diagnostic populations. Scalar and `.value` observations retain
metric/population freshness, nulls and estimates; daily source populations are
not summed. Optional `quality_behavior` and `quality_judge` fields decode
additively and remain nil for older payloads; script P50 is preferred with a
P95 fallback, and missing quality populations stay unknown rather than being
fabricated as zero. `SkillsRoiDiagnosticsCardView` renders a proposal-driven
4-column macro vitals band, a 4-object segmented stage with 2-column Bento
cards, and a single-skill 4-in-1 health sheet opened on demand. Repeated
cards/rows combine their child accessibility labels so metadata remains
announced, while all semantic colors come from `DesignKit`'s OS-dynamic `Theme.system`.
It never renders diagnostic workbenches, source previews, commands, session
samples, or root-cause panels. Responsive geometry is proposal-driven and
Decodable report models remain backward compatible with existing fixtures.

Agent Efficiency (`AgentEfficiencyWorkbenchSnapshot` + `AgentRetroTrajectoryPanelsView`)
decodes optional `agent_retro` 6-layer trajectory health, long-horizon waste,
and `vN@sha` post-fix watermarks (plus `agent_retro_watermarks` in `skill_retro`)
using plain-language labels and honest degraded/empty states without bare
internal codes.

