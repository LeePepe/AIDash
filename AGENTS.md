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
| **Global technical context** (architecture, data flow, layers) | `tech-context.md` |
| **Per-layer technical context** | `Packages/<X>/tech-context.md` |
| **Design system / seed color source** (canonical) | `Packages/DesignKit/tech-context.md` |
| CI / quality gates 说明 | `docs/ci-gates.md` |
| Daily digest + aidash push-chain 运维 | `docs/daily-digest-and-aidash-push-chain.md` |
| Agent-ops redo backlog | `docs/agent-ops-redo-backlog.md` |
| ADR: nonisolated(unsafe) XPC reply | `docs/adr/001-nonisolated-unsafe-xpc-reply.md` |
| Design north-star (视觉目标) | `design/north-star.md` |

## Read Contract(读取契约)

任务开始前,按你要碰的东西,先读对应文档 —— 不读就动手 = 违规。
优先级:Constitution > spec > tech-context > plan > task > intuition。

| 你要做的事 | 必读(前置) | 拿什么 |
|---|---|---|
| 任何任务 | `.specify/memory/constitution.md` | 不可违反的红线 |
| 决定"做什么" / 改需求 | `specs/<当前>/spec.md` | 功能意图、验收标准、范围边界 |
| 改全局架构 / 跨层设计 | `tech-context.md`(顶层) | 架构决策、数据流、分层规则 |
| **改 `Packages/<X>/**`** | **`Packages/<X>/tech-context.md`** | 该层职责、依赖、红线、测试约定 |
| **改颜色/组件视觉** | **`Packages/DesignKit/tech-context.md`** | seed 色彩系统单源、组件词汇、设计红线 |
| 改 CI / hook / gate | 见 Constitution 的 Quality Gates 节 | 门禁约定 |

### 分层路由(Layer Routing)—— 核心

- 改哪个包,**先读那个包的 `tech-context.md`**(顶部 frontmatter 有 layer/依赖/红线)。
- 改动只落在 **1 个层** → 一个 agent 直接做。
- 改动跨 **2+ 层** → 任务太大,**按层拆**成 N 个子任务;每个子任务 = 一层 =
  一个独立可 build/test 的 commit。
- 单层内仍很大 → 按技术切面拆(lib / 接口 / UI / 格式化 / fixture / 文档 / 迁移)。
- 做完发现别层也要动 → **记为新任务,不扩展原任务**。
- 用行数/文件数当"任务大小"阈值是脆弱的;**layer 边界才是 scope 单元**。

### 分层发现(Layer Discovery)

lint / UT 失败时:解析失败路径 → 映射到 layer(哪个 Package)→ 派该层的修复
(带上该层 `tech-context.md` frontmatter 的 `red_lines`)→ 只在该层内修 → 跑该层
test 验证 → 若根因在别层,记为新任务,不跨层改。

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
AIDashUI  (SwiftUI views; depends on Core + DesignKit)
   ↑
AIDashApp (macOS + iPadOS + iOS app; depends on UI + Core)

DesignKit (seed color system + components; zero local deps)
   ↑
AIDashUI  (consumes DesignKit's color source)

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
- **`main` is protected.** Three gates guard every change (发现→修复解耦):
  1. **Local `pre-commit` hook** (`scripts/hooks/pre-commit`) — 增量:只对本次
     暂存改动涉及的 SPM 包跑 `swift build` + `swift test` + 对暂存 `.swift`
     跑 swiftlint(用根 `.swiftlint.yml`)。秒级。**注意:顶层代码(`Apps/**`、
     `CLI/**`)不属于任何 `Packages/<X>` 层,pre-commit 的 build/test 不覆盖——
     但 swiftlint 用根 config 覆盖全仓库;它们的 build 门禁落在 pre-push/CI。**
  2. **Local `pre-push` hook** (`scripts/hooks/pre-push`) — 全量:防腐校验
     (frontmatter 对代码)、「改代码必带测试」门、`swiftlint`(根 config,全仓库)、
     `swift test`(AIDashCore)、`xcodegen generate`、`xcodebuild` for BOTH
     `AIDashApp` and `aidash` CLI。
     Activated per-worktree via `git config core.hooksPath scripts/hooks`.
  3. **GitHub Actions** (`.github/workflows/build.yml`) — re-runs the same
     gates(含防腐校验 + 改代码必带测试 + `swiftlint` job)on `macos-26` for every
     PR against `main` and for every push to `main`. This is the authoritative
     CI signal; 只有它挡得住 `--no-verify`。**需在仓库 branch ruleset 里把
     `build + test (macOS 26)`、`require-tests`、`swiftlint (root config)` 都设为
     required status check**(脚本进 workflow ≠ 已 required)。
- **SwiftLint 单源.** 根 `.swiftlint.yml` 是全仓库唯一 config(pre-commit/pre-push/CI
  共用)。阈值目前 lenient(放宽到覆盖既有代码,零改动兑绿),但仍拦明显糟糕的新代码;
  逐规则收紧是后续独立 issue。`Tests/` 豁免(`try!` 等惯例)。
- **改代码必带测试.** 改了 `.swift` 源码却没动任何测试文件 → pre-push / CI 拦。
  逃生舱:任一 commit message 写 `Allow-No-Tests: <原因>`(仅限确无法测的改动)。
- **防腐校验.** `scripts/hooks/check-frontmatter` 核对每层 `tech-context.md`
  frontmatter 与代码一致(layer 名==目录名、`depends_on` ⇄ `Package.swift`
  双向一致、`depended_by` 镜像、`test` 路径存在)。架构变了就更新对应层文档。
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
