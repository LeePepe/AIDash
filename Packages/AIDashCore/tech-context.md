---
layer: AIDashCore
role: 领域模型(Briefing/Container/Card)、CloudKit 客户端、XPC 协议、schema 校验。零 UI 依赖,App 与 CLI 共用,保证 schema 单一来源。
depends_on: []                      # 零依赖(仅 Apple 框架)
depended_by: [AIDashUI, AIDashApp, aidash-CLI]
red_lines:
  - schema 是唯一来源:Briefing/Container/Card 的定义只在此层,App/CLI 不得各自重定义
  - CLI 永不直连 CloudKit:CloudKit 身份由 App 独占;此层的 CloudKit 客户端仅 App 侧使用
  - 生产代码禁止 fatalError / try! / as!,用 Result/throws/优雅回退
  - Swift 6 严格并发;@unchecked Sendable、nonisolated(unsafe) 需 docs/adr/ 下 ADR
  - 默认仅 Apple 框架;新增非 Apple 依赖(swift-argument-parser 之外)需 ADR
  - 三个正交卡片维度(type/size/style)不得混为一谈
test: swift test --package-path Packages/AIDashCore
owns: [Briefing, Container, Card, CardType, CardSize, CardStyle, CloudKitContainer, XPCProtocol, XPCRequest, XPCResponse, XPCError, SchemaValidator, URLPolicy, CardPayloadProtocol, DeviceIdentifier]
---

# AIDashCore Tech Context

## 职责

领域层。承载 AIDash 的**数据契约**——Briefing / Container / Card 模型、卡片
payload schema、XPC 协议(CLI ↔ App 通信信封与错误分类)、CloudKit 存储客户端、
schema 校验与 URL 策略。**零 UI 依赖**,是 App 和 CLI 共同依赖的底座,确保数据
schema 只有一处定义。

## 为什么零依赖

App 和 CLI 都依赖 Core。如果 schema 在两处各写一份,agent 改了一处忘了另一处
就会 drift。Core 单源 + 包边界强制 = schema 不可能分叉。这也是 `depends_on: []`
的原因:Core 不能反向依赖任何上层。

## 关键结构

- **Models/**:`Briefing` `Container` `Card` + `CardType`/`CardSize`/`CardStyle`
  三个正交维度 + 各类型 payload(`MetricPayload` `TodoListPayload`
  `TrendingPayload` `InsightPayload` `AgentSummaryPayload` `SectionHeaderPayload`)。
  SwiftData model 类(`*Model.swift`)是本地缓存镜像。
- **CloudKit/**:`CloudKitContainer` —— CloudKit Private DB 客户端。**仅 App 侧用**。
- **XPC/**:`XPCProtocol` `XPCRequest` `XPCResponse` `XPCError`
  `XPCPendingRequests` —— CLI 作为瘦 XPC 客户端与 App 通信的契约。
- **Validation/**:`SchemaValidator`(schema 锁定校验)、`URLPolicy`(链接策略)。
- **Storage/**:SwiftData 相关。**DeviceID/**:`DeviceIdentifier`。

## 数据流(关键约束)

```
CLI ──XPC──▶ App ──CloudKit──▶ CloudKit Private DB
                 └─ App 独占 CloudKit 身份
CLI 永不直连 CloudKit;CLI 只依赖 Core(XPC 契约),绝不 import UI。
```
CloudKit 是唯一真理来源;App 本地 SwiftData 镜像是可丢弃缓存。

## 依赖方向

```
AIDashCore(本层,零 UI 依赖)
   ↑ AIDashUI      ↑ AIDashApp      ↑ aidash CLI
```
本层是最底层,只能被依赖,不能依赖上层。包边界(SPM)强制此方向。

## 平台 / 语言

macOS 26 / iOS 26 最低,Swift 6.0 严格并发。无 OS 25 及以下兼容 shim。

## 测试

```bash
swift test --package-path Packages/AIDashCore
```
两个 test target:`AIDashCoreTests`(内部)、`AIDashCorePublicAPITests`(公共 API 契约)。
