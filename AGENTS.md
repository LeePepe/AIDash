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
| **Recursive layer routing** | `CONTEXT.md` → `scripts/context/resolve <path>` |
| **Global technical context** (architecture, data flow, layers) | `tech-context.md` |
| **Per-layer technical context** | `Packages/<X>/tech-context.md` |
| **aidata 数据层**(Python,上游内容生产) | `aidata/tech-context.md` |
| **Design system / seed color source** (canonical) | `Packages/DesignKit/tech-context.md` |
| CI / quality gates 说明 | `docs/ci-gates.md` |
| Daily digest + aidash push-chain 运维 | `docs/daily-digest-and-aidash-push-chain.md` |
| Agent-ops redo backlog | `docs/agent-ops-redo-backlog.md` |
| ADR: nonisolated(unsafe) XPC reply | `docs/adr/001-nonisolated-unsafe-xpc-reply.md` |
| Design north-star (视觉目标) | `design/north-star.md` |

## Read Contract(读取契约)

任务开始前,按你要碰的东西,先读对应文档 —— 不读就动手 = 违规。
优先级:Constitution > spec > CONTEXT.md leaf > tech-context > plan > task > intuition。

| 你要做的事 | 必读(前置) | 拿什么 |
|---|---|---|
| 任何任务 | `.specify/memory/constitution.md` | 不可违反的红线 |
| 改任何文件 | `scripts/context/contexts <path>` 返回的链 | 唯一 owning leaf、依赖、red lines、gate |
| 决定"做什么" / 改需求 | `specs/<当前>/spec.md` | 功能意图、验收标准、范围边界 |
| 改全局架构 / 跨层设计 | `tech-context.md`(顶层) | 架构决策、数据流、分层规则 |
| **改 `Packages/<X>/**`** | **`Packages/<X>/tech-context.md`** | 该层职责、依赖、红线、测试约定 |
| **改 `aidata/**`**(Python 数据层) | **`aidata/tech-context.md`** | L1-L5 分层、契约、config_local 约定、cron 双维护点 |
| **改颜色/组件视觉** | **`Packages/DesignKit/tech-context.md`** | seed 色彩系统单源、组件词汇、设计红线 |
| 改 CI / hook / gate | 见 Constitution 的 Quality Gates 节 | 门禁约定 |

### 分层路由(Layer Routing)—— 核心

- 先跑 `scripts/context/resolve <path>`;再读 `scripts/context/contexts <path>`
  返回的 root → child index → leaf 链。leaf frontmatter 是 layer / dependency /
  red-lines / gate 的单一结构化来源;`tech-context.md` 是 leaf 指向的深入参考。
- `scripts/context/audit` 必须让每个 tracked file 恰好落到一个 leaf 或带原因的
  exclusion。路由、依赖或 manifest 改动和 audit 修复同一个 commit 落地。
- 改动只落在 **1 个层** → 一个 agent 直接做。
- 改动跨 **2+ 层** → 任务太大,**按层拆**成 N 个子任务;每个子任务 = 一层 =
  一个独立可 build/test 的 commit。
- 单层内仍很大 → 按技术切面拆(lib / 接口 / UI / 格式化 / fixture / 文档 / 迁移)。
- 做完发现别层也要动 → **记为新任务,不扩展原任务**。
- 用行数/文件数当"任务大小"阈值是脆弱的;**layer 边界才是 scope 单元**。

### 分层发现(Layer Discovery)

lint / UT 失败时:读取结构化 `{layer,path,kind,detail,red_lines}` → 只在该 leaf
内修 → `scripts/context/run <layer>` → 若根因在别层,记为新任务,不跨层改。

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
AIDashApp (macOS + iPadOS + iOS app; depends on UI + Core + DesignKit)

DesignKit (seed color system + components; zero local deps)
   ↑
AIDashUI  (consumes DesignKit's color source)

aidash CLI (macOS only; depends on Core only; MUST NOT import UI)
```

The SPM package boundaries enforce this — do not break it.

### aidata(Python 数据层)不在这张图里

`aidata/` 是**上游内容生产**,不是 Swift 包:它不 import 任何 Swift 代码,Swift
侧也不 import 它。耦合点是**单向数据流** —— aidata 产出卡片 payload(JSON),经
`aidash` CLI 的 XPC 推给 App:

```
aidata/ (Python, L1→L5)  ──JSON payload──>  aidash CLI  ──XPC──>  AIDashApp
```

契约是 payload 的形状,由 `AIDashCore/Models/Payloads/` 定义。跨语言没有编译器
把关,所以用 `.claude/skills/aidash-content/` 的 layer-through 路由 +
`scripts/contract_check.sh` 兜底。改 briefing 内容一律走那个 skill。

**Swift 门禁(swiftlint / require-tests / build+test / check-frontmatter)只覆盖
`.swift` 与 `Packages/*`,不覆盖 `aidata/`。** Python 层由**独立的 CI job**
`aidata (pytest + ruff)` 把关:pytest + `ruff check` + 无 `config_local.py` 的
降级探针。本地跑:`/usr/bin/python3 -m pytest aidata/tests/ -q`。

## Test through hooks; do not manually repeat suites

**Verification is mandatory and hook-driven.** Do not manually repeat suites.
`pre-commit` and `pre-push` resolve changed paths and run declared local leaf
gates; CI runs the required resolver-declared App/CLI builds and repository-wide
gates. A hook failure is the test signal: fix its owning leaf and commit again.

**NEVER run a host-based test target locally:**

```bash
xcodebuild -scheme AIDashApp ... test     # ❌ FORBIDDEN locally
```

`AIDashAppTests` pins `TEST_HOST` to the real `AIDash.app`, so the bundle
executes **as the production app** — same bundle id, same real home, freshly
re-signed each build. Two things follow, both of which actually happened:

1. macOS re-prompts for TCC access (Contacts / iCloud, which the app
   container symlinks to) on **every** run.
2. Code resolving the real home operates on the user's **live data** — a
   test once moved the developer's SwiftData store into a temp dir and
   deleted it on teardown.

If you genuinely must verify an app-layer change beyond the build gate, use
the hostless target — it runs as `xctest`, launches no app, and cannot reach
the real home:

```bash
xcodebuild -scheme AIDashAppLogicTests -destination 'platform=macOS' test
```

Host-based targets belong to CI (no one to prompt, no live user data) or to
a run the user explicitly asks for.

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

# Test the aidata Python data layer (CI job: `aidata (pytest + ruff)`).
# 注意用 /usr/bin/python3(装了 pytest);cron 链用的 homebrew python3 没装。
/usr/bin/python3 -m pytest aidata/tests/ -q
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
  1. **Local `pre-commit` hook** (`scripts/hooks/pre-commit`) — 递归 resolve 暂存
     路径,先 audit 唯一归类,再跑 affected leaf 的 local gates;SPM leaf 是
     `swift build` + `swift test`。暂存 `.swift` 另过根 SwiftLint config。
  2. **Local `pre-push` hook** (`scripts/hooks/pre-push`) — resolve push diff,跑
     affected leaf 的 local gates +「改代码必带测试」+ 所有 pushed ranges 中去重后仍
     存在的变更 `.swift` 文件 SwiftLint(`--force-exclude`,故 Tests/.build 仍按根 config
     排除)。App / CLI / XcodeWorkspace 的 heavy gates 标为 CI-only,本地不启动 host
     app test target。
     Activated per-worktree via `git config core.hooksPath scripts/hooks`.
  3. **GitHub Actions** (`.github/workflows/build.yml`) — re-runs the same
     gates(含防腐校验 + 改代码必带测试 + `swiftlint` job)on `macos-26` for every
     PR against `main` and for every push to `main`. This is the authoritative
     CI signal; 只有它挡得住 `--no-verify`。
     **实际 required status checks(ruleset `main protection`,2026-08-02 核实):**
     `build + test (macOS 26)`、`codex-review-target`、`aidata (pytest + ruff)`,strict
     模式开(分支须与 main 同步)。**注意 `require-tests` 与 `swiftlint (root config)`
     两个 job 会跑但目前 NOT required** —— 它们红了不挡合并。要设为强制,改
     ruleset(脚本进 workflow ≠ 已 required)。
     `claude-review` 已暂停;`kimi-review` 只发 advisory comment,不进入 required ruleset。
     另:ruleset 的 `bypass_actors` 含 admin 且 `bypass_mode: always`,所以
     维护者本人直推/强推会被放行,remote 的提示只是告知而非拦截。
- **SwiftLint 单源.** 根 `.swiftlint.yml` 是全仓库唯一 config(pre-commit 按文件、
  pre-push 按 pushed ranges 的变更 Swift 文件、CI 全仓共用;CI job 当前非 required)。
  阈值目前 lenient(放宽到覆盖既有代码,零改动兑绿),但仍拦明显糟糕的新代码;
  逐规则收紧是后续独立 issue。`Tests/` 豁免(`try!` 等惯例)。
- **改代码必带测试.** 改了 `.swift` 源码却没动任何测试文件 → pre-push / CI 拦。
  逃生舱:任一 commit message 写 `Allow-No-Tests: <原因>`(仅限确无法测的改动)。
- **防腐校验.** `scripts/context/audit` 是递归 routing/dependency/manifest 单源门;
  CI 暂时继续跑 legacy `scripts/hooks/check-frontmatter`,直到旧 `tech-context.md`
  深入参考完成迁移。架构变了就更新 owning leaf context。
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
