# AIDash

> A personal AI briefing dashboard for macOS, iPadOS, and iPhone.
> Agents publish daily briefings; the user reads.

[![CI](https://github.com/LeePepe/AIDash/actions/workflows/ci.yml/badge.svg)](https://github.com/LeePepe/AIDash/actions/workflows/ci.yml)

## What it is

AIDash is a single-user app that displays a fresh briefing every morning,
composed entirely by background AI agents. The user does not type, does
not chat, and does not compose content — they open the app, read the day's
briefing, and close it. Two lightweight reactions (mark done, star) flow
back to agents so they can learn what to surface tomorrow.

For the full mission and principles, see
[Constitution v1.0.0](.specify/memory/constitution.md).

## Architecture

```
Agent (Python / shell)
   │
   └─> aidash CLI (Swift binary, macOS only)
          │ XPC (com.tianpli.aidash.xpc.v1)
          ▼
   AIDash.app (macOS menubar host)
       ├── SwiftData + NSPersistentCloudKitContainer
       │       ↕ auto-sync
       │   iCloud Private DB
       │       ↕ auto-sync
       │   iPad / iPhone apps (read-only render + UserEvent writeback)
       └── Menubar UI + briefing window
```

- **CLI never touches CloudKit directly.** It talks XPC to the app.
- **App is the sole CloudKit identity.** No dual-process write races.
- **Schema source of truth** is `AIDashCore` (shared SPM package
  between CLI and app).

## Getting started (development)

Prerequisites:

- macOS 26+
- Xcode 26+
- [XcodeGen](https://github.com/yonsm/XcodeGen) (`brew install xcodegen`)
- A paid Apple Developer account for CloudKit Private DB.

```bash
git clone https://github.com/LeePepe/AIDash.git
cd AIDash

# Generate xcodeproj from project.yml
xcodegen generate

# Activate the version-controlled git hooks
git config core.hooksPath scripts/hooks

# Run Core unit tests
swift test --package-path Packages/AIDashCore

# Build everything
xcodebuild -scheme AIDashApp -destination "platform=macOS" build
xcodebuild -scheme aidash    -destination "platform=macOS" build

# Open in Xcode
open AIDash.xcodeproj
```

## Project layout

```
AIDash/
├── .specify/             Spec Kit artifacts (constitution, templates)
├── docs/                 Decision logs, architecture diagrams
├── specs/                Feature specifications (versioned)
│   └── 001-core-briefing-cli/
│       ├── spec.md       What and why
│       ├── plan.md       How
│       ├── research.md   Architecture decisions + alternatives
│       ├── data-model.md SwiftData + Codable schemas
│       ├── tasks.md      Task breakdown
│       ├── contracts/    CLI surface, XPC protocol, payload schemas
│       └── quickstart.md Agent-facing recipe
├── Packages/
│   ├── AIDashCore/       Models, Codable schemas, validator
│   └── AIDashUI/         SwiftUI views
├── Apps/AIDashApp/       Universal macOS + iPadOS + iPhone app target
├── CLI/aidash/           macOS-only command-line helper
├── scripts/hooks/        Version-controlled git hooks (activate with
│                         `git config core.hooksPath scripts/hooks`)
├── project.yml           XcodeGen configuration
└── AGENTS.md             Instructions for automated agents
```

## How agents publish briefings

See [`specs/001-core-briefing-cli/quickstart.md`](specs/001-core-briefing-cli/quickstart.md)
for the 5-minute agent recipe. Minimum example:

```bash
aidash briefing put --date today --generated-by "morning-briefer"

aidash container put --briefing-date today --id <uuid> \
    --title "Yesterday" --order 10 --layout list

aidash card put --container-id <uuid> --id <uuid> \
    --type digest --size hero \
    --payload '{"title":"...","body":"..."}'

aidash briefing publish --date today
```

The CLI validates schema locally, dispatches via XPC to the macOS app,
and the app writes to CloudKit. iPad and iPhone pick up the new briefing
within ~60 seconds via CloudKit auto-sync.

## Related project

[agent-ops-dashboard](https://github.com/LeePepe/agent-ops-dashboard) —
a separate monitoring-focused dashboard for the agent fleet. AIDash and
agent-ops are complementary; see
[`docs/agent-ops-redo-backlog.md`](docs/agent-ops-redo-backlog.md) for
the rework plan tracking.

## License

MIT.
