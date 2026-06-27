# AIDash Agent Instructions

This file is read by automated agents (Multica TL, Multica Fullstack,
Multica Reviewer, Claude Code, Codex CLI, Hermes, GitHub Copilot, etc.)
when they work on this repo. Keep it short and authoritative.

## Constitution

Project constitution lives at `.specify/memory/constitution.md`. **Read it
before doing anything material.** It governs every decision below.

## Where to find what

| Looking for | Path |
|---|---|
| Project mission and principles | `.specify/memory/constitution.md` |
| Feature spec (what & why) | `specs/001-core-briefing-cli/spec.md` |
| Implementation plan (how) | `specs/001-core-briefing-cli/plan.md` |
| Architecture decisions + alternatives | `specs/001-core-briefing-cli/research.md` |
| Data model (SwiftData + Codable schemas) | `specs/001-core-briefing-cli/data-model.md` |
| CLI surface (subcommands, exit codes) | `specs/001-core-briefing-cli/contracts/cli-surface.md` |
| XPC protocol (envelope, error taxonomy) | `specs/001-core-briefing-cli/contracts/xpc-protocol.md` |
| Card payload schemas (per type) | `specs/001-core-briefing-cli/contracts/cardtype-payloads.md` |
| Agent quickstart (how to publish a briefing) | `specs/001-core-briefing-cli/quickstart.md` |
| Task breakdown | `specs/001-core-briefing-cli/tasks.md` |
| Original grill decisions (audit trail) | `docs/grill-2026-06-23-decisions.md` |

## Hard constraints (from Constitution)

These are non-negotiable. PRs violating them must be rejected by the
Reviewer.

- **macOS 26 / iPadOS 26 / iOS 26 minimum.** No back-compat shims for
  OS 25 or earlier.
- **Swift 6.0 strict concurrency.** `@MainActor` default for view-layer.
  `@unchecked Sendable`, `nonisolated(unsafe)`, etc. require an ADR
  under `docs/adr/`.
- **No `fatalError` / `try!` / `as!` in production code.** Use `Result`,
  `throws`, or graceful UI fallback.
- **Apple frameworks only by default.** Adding any non-Apple dependency
  beyond `swift-argument-parser` requires an ADR.
- **No HTTP client introduced unless needed.** CloudKit is the storage
  backend; CLI talks XPC, not HTTP.
- **No app-side LLM calls in v1.** Content is agent-authored, not
  app-generated.
- **CLI never talks to CloudKit directly.** CLI is a thin XPC client to
  the macOS app; the app owns the sole CloudKit identity.

## Module dependency direction

```
AIDashCore (zero UI deps, used by both app and CLI)
   ↑
AIDashUI  (SwiftUI views; depends on Core)
   ↑
AIDashApp (macOS + iPadOS + iOS app; depends on UI + Core)

aidash CLI (macOS only; depends on Core only; MUST NOT import UI)
```

The SPM package boundaries enforce this — do not break it.

## Build commands

```bash
# Generate the Xcode project from project.yml (run after any project.yml change)
xcodegen generate

# Test the Core package only (fast, no Xcode needed)
swift test --package-path Packages/AIDashCore

# Build the macOS app
xcodebuild -scheme AIDashApp -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO build

# Build the iPhone/iPad app
xcodebuild -scheme AIDashApp -destination "platform=iOS Simulator,name=iPhone 17,OS=26.0" build
xcodebuild -scheme AIDashApp -destination "platform=iOS Simulator,name=iPad Pro,OS=26.0" build

# Build the aidash CLI (macOS only). MUST pass before any push that
# touches CLI/aidash/** or project.yml.
xcodebuild -scheme aidash -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO build
```

## Git workflow

- **Worktree per task.** Multica Fullstack agents create
  `/tmp/aidash-<task>/` worktrees; do not pollute the user's local
  `~/Development/AIDash/` checkout. New worktree's first step:
  `git config core.hooksPath scripts/hooks`.
- **Conventional commits.** `feat:`, `fix:`, `refactor:`, `test:`,
  `docs:`, `chore:`.
- **PR is the unit of merge.** Each PR closes one Multica issue.
- **`main` is protected.** Two layers of CI gate every change:
  1. **Local `pre-push` hook** (`scripts/hooks/pre-push`) — runs
     `swift test` on `AIDashCore`, then `xcodegen generate`, then
     `xcodebuild` for BOTH `AIDashApp` and the `aidash` CLI. Activated
     per-worktree via `git config core.hooksPath scripts/hooks`.
  2. **GitHub Actions** (`.github/workflows/build.yml`) — re-runs the
     same gates on `macos-latest` for every PR against `main` and for
     every push to `main`. This is the authoritative CI signal that the
     Reviewer and PR Manager must confirm green before merge.
- **Hooks live in `scripts/hooks/`** (under version control), activated
  via `git config core.hooksPath scripts/hooks`. `.git/hooks/` is
  per-worktree and ignored. Bypass with `--no-verify` is allowed only
  for docs-only changes — the GitHub Actions gate still runs and will
  fail the PR if non-docs code is broken.

## When in doubt

- Read the relevant section of the Constitution or spec first.
- If the spec is ambiguous, raise it as a question in the issue
  comments — do not guess and ship.
- Constitution > spec > plan > task description > intuition.
