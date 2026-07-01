# AIDash Tech Context

> 顶层技术上下文。全局架构决策、数据流、包结构、分层规则。
> 每层的局部技术上下文见 `Packages/*/tech-context.md`。
> 不可违反的铁律见 `.specify/memory/constitution.md`;功能规格见 `specs/*/spec.md`。

## Product Identity

AIDash = **agent 撰写、用户阅读**的每日 briefing。CLI(agent 侧)写内容,
macOS/iPadOS/iOS App(用户侧)读展示,两者经 CloudKit 同步。核心是一屏可扫读的
每日 briefing,由 schema 锁定的卡片类型 + 数据驱动布局组成。

## 架构总览

```
┌─ aidash CLI(macOS,agent 侧)── 写 briefing
│      │ XPC(瘦客户端)
│      ▼
├─ AIDashApp(macOS/iPadOS/iOS,用户侧)── 独占 CloudKit 身份,读展示
│      │
│      ▼
└─ CloudKit Private DB ── 唯一真理来源(Briefing / UserEvent 记录)
        App 本地 SwiftData = 可丢弃镜像缓存
```

## Data Architecture Decisions

- **CLI 写 / App 读 / CloudKit 同步**(constitution 原则 II):严格分离。CLI **永不**
  直连 CloudKit,只经 XPC 与 App 通信;**App 独占** CloudKit 身份。
- **Schema 单一来源**:Briefing/Container/Card 定义只在 AIDashCore。App/CLI 共用,
  不各自重定义 → schema 不可能分叉。
- **持久化**:Briefing/UserEvent 存 CloudKit Private DB(自定义记录类型);App 侧
  SwiftData 镜像最近一次 briefing 供离线展示,可丢弃;CloudKit 是真理来源。
- **无第三方存储**(无 Firebase/Realm/SwiftData 外的本地 SQLite)。

## Package Structure(分层)

| 层 | 是什么 | 依赖 | tech-context |
|---|---|---|---|
| **AIDashCore** | 领域模型 + CloudKit 客户端 + XPC 协议 + schema 校验。零 UI 依赖 | 无 | `Packages/AIDashCore/tech-context.md` |
| **AIDashUI** | 跨平台 SwiftUI 视图、布局、设计令牌 | Core | `Packages/AIDashUI/tech-context.md` |
| **AIDashApp** | macOS/iPadOS/iOS App target(XcodeGen 管理) | UI + Core | (app target,见 project.yml) |
| **aidash CLI** | Swift Argument Parser CLI,仅 macOS | **仅 Core**,禁 import UI | (CLI target) |

## 依赖方向(单向,包边界强制)

```
AIDashCore ← AIDashUI ← AIDashApp
AIDashCore ← aidash CLI        (CLI 绝不 import UI)
```
方向单向不可逆。改动跨越这条边界 = 信号:任务太大或分层错了,应拆(见分层路由)。

## Rules(全局技术约束,摘自 constitution)

- macOS 26 / iOS 26 最低,无向后兼容 shim。
- Swift 6 严格并发;`@unchecked Sendable` 等需 `docs/adr/` 下 ADR。
- 生产代码禁 `fatalError` / `try!` / `as!`。
- 默认仅 Apple 框架;新增非 Apple 依赖(`swift-argument-parser` 之外)需 ADR。
- 无 App 侧 LLM 调用(内容 agent 撰写)。
- 三个正交卡片维度(type/size/style)不混淆;设计值走 DesignTokens。

## 分层路由(agent 工作范围)

- 改 `Packages/AIDashCore/**` → 先读 `Packages/AIDashCore/tech-context.md`
- 改 `Packages/AIDashUI/**` → 先读 `Packages/AIDashUI/tech-context.md`
- 改跨 2+ 层 → 任务太大,按层拆成独立可 build/test 的 commit
- 收尾遗留 → 记为新任务,不扩展原任务

## 构建 / 测试

见 `AGENTS.md → Build commands`。快速门:`swift test --package-path Packages/AIDashCore`。
