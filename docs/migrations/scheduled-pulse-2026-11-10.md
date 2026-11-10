# AIDash Job Framework migration receipt

- **Date:** 2026-11-10
- **Owner:** AIDash
- **Scope:** Registry-driven job framework, dynamic Overview, Need Actions, and owned launchd controls

## Current registry

The framework owns exactly three live jobs:

- `my-pr-supervisor` — every 5 minutes
- `pr-auto-review` — every 5 minutes
- `aidata-digest` — 04:00 CST

WorkIQ is not registered and has no row, plist, script, scheduler process, or
network request.

## Boundaries

Job output is read only from each AIDash-owned directory under
`~/Library/Application Support/AIDash/jobs/<id>/`. Need Actions responses append
UserEvent receipts only; they do not mutate Briefing content or source work.

Start/stop controls address only
`com.tianpli.aidash.job.<id>` labels. Stop uses `launchctl bootout` and leaves
the plist on disk; start uses `launchctl bootstrap`. The existing
`com.tianpli.aidash` XPC MachServices plist is unchanged.

Legacy Hermes and Clockwork schedules remain disabled and untouched. This
receipt does not inspect, scrape, discover, or import data from Hermes,
Clockwork, other LaunchAgents, GitHub runners, or WorkIQ.

## Constitution 1.15.0 exception

The amendment preserves the Briefing no-input/no-authoring rule while allowing
main-window Need Actions/Todo controls, including textInput capped at 80
characters. Responses are append-only UserEvent receipts. Existing Briefing,
CardType, CloudKit, SwiftData, and event records require no migration.
