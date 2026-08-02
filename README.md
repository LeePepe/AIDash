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
[Constitution v1.0.0](.specify/memory/constitution.md). For the feature
scope and acceptance criteria, see the
[Core Briefing CLI spec](specs/001-core-briefing-cli/spec.md)
(plan: [plan.md](specs/001-core-briefing-cli/plan.md),
tasks: [tasks.md](specs/001-core-briefing-cli/tasks.md)).

## Architecture

```
Agent (Python / shell)
   │
   └─> aidash CLI (Swift binary, macOS only)
          │ XPC (<bundle id>.xpc.v1)
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

# One-line setup: install XcodeGen, generate the project, and open it in Xcode
brew install xcodegen && xcodegen generate && open AIDash.xcodeproj

# Activate the version-controlled git hooks
git config core.hooksPath scripts/hooks

# Run Core unit tests
swift test --package-path Packages/AIDashCore

# Build everything
xcodebuild -scheme AIDashApp -destination "platform=macOS" build
xcodebuild -scheme aidash    -destination "platform=macOS" build
```

## Fork 本项目(换成你自己的身份)

项目里所有个人标识都收敛在**两个文件**,fork 后改这两处即可。默认值是原作者的,
不改也能编译通过 —— 但 CloudKit 会拒绝(容器不属于你的团队),所以要跑起来必须改。

### 1. Swift 侧 —— `Configs/Identity.xcconfig`

Bundle ID / CloudKit 容器 / 开发者团队的**单源**。

其中 `AIDASH_DEVELOPMENT_TEAM` 在仓库里存的是占位符 `REPLACE_ME` —— Apple Team ID
是可关联到真实身份的标识符,不该进公开仓库。Bundle ID 保留 `com.tianpli.aidash`
作为默认值:它是这个 app 的公开身份(任何上架 app 的 bundle ID 都可见),不是凭据,
而且 mach service 名必须与它字面一致(见下面的例外),留占位符反而会让全新 clone
自相矛盾。fork 时把两者都换成你自己的即可。

两种改法,推荐后者:

**(a) 直接改 `Configs/Identity.xcconfig`** —— 简单,但它受版本控制,你的
Team ID 会随提交进仓库。

**(b) 本地覆盖(推荐)** —— 真实值不进版本库:

```bash
cp Configs/Identity.local.xcconfig.example Configs/Identity.local.xcconfig
# 填入你的值,然后
xcodegen generate
```

`Identity.local.xcconfig` 已 gitignore,在 `Identity.xcconfig` **末尾**被
`#include?` 进来。xcconfig 是「后定义覆盖先定义」,所以 include 放末尾才能生效
(放开头会被默认值反盖 —— 已实测)。带 `?` 表示文件不存在就静默跳过,因此全新
clone 不做任何配置也能直接编译。

| 变量 | 改成 | 去哪找 |
|---|---|---|
| `AIDASH_BUNDLE_PREFIX` | 你的反向域名(如 `com.yourname`) | 自定 |
| `AIDASH_DEVELOPMENT_TEAM` | 你的 10 位 Team ID | developer.apple.com → Membership |
| `AIDASH_CLOUDKIT_CONTAINER` | 仅当容器名不遵循 `iCloud.<bundle id>` 惯例时才需设 | [icloud.developer.apple.com](https://icloud.developer.apple.com/dashboard/) |

CloudKit 容器必须在 Dashboard 里**真实存在**且属于你的团队,否则 app 启动即
`CKError 15/2000`。CI 用 `CODE_SIGNING_ALLOWED=NO`,所以占位符也能过 CI;
但**本机带签名运行 app 必须填真实 Team ID**。

这些值必须在**编译期**确定(entitlements 与 Info.plist 是构建产物,读不了运行时
配置),所以是 xcconfig 而非普通配置文件。App 侧的 CloudKit 容器与 launchd label
从 `Bundle.main.bundleIdentifier` 自动推导,无需再改代码。

**一个例外需要手工同步**:`Packages/AIDashCore/Sources/AIDashCore/XPC/XPCProtocol.swift`
里的 `machServiceName`。它在 SPM 包内(SPM 不消费 xcconfig),且 CLI 是命令行工具
(`Bundle.main.bundleIdentifier` 为 nil),两条路都走不通,所以改 bundle id 后要把
它一并改成 `<你的 bundle id>.xpc.v1`。

> ⚠️ 改完必须重装:旧的 launchd agent 仍以旧 label 注册着旧 mach service。
> `launchctl bootout gui/$(id -u)/<旧 label>`,再重新安装 app 与 CLI。

### 2. 数据侧 —— `aidata/config_local.py`

```bash
cp aidata/config_local.example.py aidata/config_local.py   # 再填真实值
```

账号 / 雇主 / workspace 标识符(Multica workspace、Azure DevOps、GitHub 仓库列表)
都在这里,该文件已 gitignore。**不配也能跑** —— 相关数据源会干净地降级为 0
(ADR-23),digest 照常产出,只是少几个源。

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

## Quality expectations

**Accessibility.** All SwiftUI views must preserve platform accessibility
conventions: support Dynamic Type, use semantic labels for VoiceOver, and
maintain clear touch targets (≥ 44pt). Decorative images are marked
`.accessibilityHidden(true)`.

**Localisation.** User-facing copy must live in localizable string catalogs
(`.xcstrings`), not hardcoded in source files. This ensures translation
readiness without expanding Phase 1 implementation scope.

**Privacy.** Data is stored exclusively in CloudKit Private DB — no
third-party analytics, no external storage services, and no app-side LLM
calls in v1. The CLI never touches the network directly; it communicates
via XPC to the app.

**Design boundary.** AIDash is read-only: no compose surface, no chat
input, no user-authored content. The information hierarchy is flat:
`Briefing → Container → Card`. Module dependency flows upward
(`Core → UI → App`; CLI depends on Core only).

## Related project

[agent-ops-dashboard](https://github.com/LeePepe/agent-ops-dashboard) —
a separate monitoring-focused dashboard for the agent fleet. AIDash and
agent-ops are complementary; see
[`docs/agent-ops-redo-backlog.md`](docs/agent-ops-redo-backlog.md) for
the rework plan tracking.

## License

MIT.
