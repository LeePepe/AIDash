# Scheduled Pulse migration receipt

- **Date:** 2026-11-10
- **Owner:** AIDash
- **Scope:** AIDash-owned Scheduled Pulse registry and LaunchAgent definitions

## Owned jobs

The registry owns exactly two live jobs:

- `pr-auto-review`
- `my-pr-supervisor`

`workiq-digest` remains a reserved idle row only. It has no plist, program,
scheduler process, or network request.

## Boundary receipt

AIDash writes only its own per-job plists under
`~/Library/LaunchAgents/com.tianpli.aidash.job.<id>.plist` and bootstraps them
with plain `launchctl bootstrap` in the user GUI domain. The existing
`com.tianpli.aidash` XPC MachServices plist is unchanged.

Legacy Hermes and Clockwork schedules remain disabled and untouched. This
receipt does not inspect, scrape, discover, or import data from Hermes,
Clockwork, other LaunchAgents, GitHub runners, or WorkIQ. No migration or
bootstrap action was performed against those systems.
