---
layer: AIDashUI
role: 跨平台 SwiftUI 视图:卡片类型渲染器、容器布局、briefing 骨架、设计令牌。依赖 Core。
depends_on: [AIDashCore]
depended_by: [AIDashApp]
red_lines:
  - 只能依赖 AIDashCore,不得引入其它本地包或非 Apple 依赖(需 ADR)
  - 容器是通用渲染槽:布局由数据驱动(CardType/Size/Style),不得为特定业务硬编码布局
  - 设计令牌纪律:颜色/间距/字号走 DesignTokens,禁止散落魔法值(P0 维度混淆 / P1 令牌漂移)
  - 三个正交卡片维度(type/size/style)渲染时不得混为一谈
  - 视图层默认 @MainActor;Swift 6 严格并发
  - 无 App 侧 LLM 调用:内容是 agent 撰写的,不在视图层生成
  - 无 fatalError / try! / as!,渲染失败走优雅 UI 回退
roles:                              # 层内轴:类角色 → 目录(角色顺序见顶层 canonical_roles)
  Types:   [DesignTokens]          # 设计令牌:颜色/间距/字号单源,纯值,不依赖任何视图
  Runtime: [Layout]                # 容器布局引擎:Grid/List/Hero/Auto,消费 Tokens
  UI:      [CardView]              # 类型渲染器 + 视图:依赖 Layout + Tokens,最上层
test: swift test --package-path Packages/AIDashUI
owns: [BriefingView, ContainerView, CardRouter, DesignTokens, AutoLayout, GridLayout, ListLayout, HeroLayout, MetricCardView, TrendingCardView, SectionHeaderCardView]
---

# AIDashUI Tech Context

## 职责

表现层。跨平台 SwiftUI 视图:按 `CardType` 分发的**类型渲染器**、容器**布局**
(Grid/List/Hero/Auto)、briefing 骨架、以及**设计令牌**(DesignTokens)。依赖 Core
拿数据契约,自身不碰存储/网络。

## 核心设计:容器 = 通用渲染槽

布局**数据驱动**——`ContainerView` 读 Core 的 `Container` + 卡片的三个正交维度
(`CardType` 决定渲染器、`CardSize` 决定尺寸、`CardStyle` 决定样式),`CardRouter`
按 `CardType` 分发到对应渲染器。**不得**为某个具体 briefing 硬编码布局:新增卡片
类型 = 加一个渲染器 + 注册到 router,而非改容器。

## 关键结构

- **CardView/**:`CardRouter`(类型分发)+ 各类型视图(`MetricCardView`
  `TrendingCardView` `SectionHeaderCardView` …)。
- **Layout/**:`AutoLayout` `GridLayout` `ListLayout` `HeroLayout` +
  `ContainerView` `BriefingView`。
- **DesignTokens.swift**:颜色/间距/字号/圆角的单一来源。**所有视觉值走它**。
- **Prototype/**:设计原型(`KPICardPrototype` `HeatmapPrototype`
  `ModernBriefingPrototype` 等)+ `ProtoTheme`/`ProtoDesign`/`PrimaryPalette`。
  原型用于探索,不是生产渲染路径。
- **Resources/**:`.process` 资源(Asset Catalog 等)。

## 设计令牌纪律(重点红线)

constitution 把"维度混淆"列为 P0、"令牌漂移"列为 P1。实操:
- 颜色/间距/字号/圆角一律从 `DesignTokens` 取,不写魔法值(如 `.padding(16)` 应为
  token)。
- type/size/style 三维度各司其职,渲染时不得交叉判断(如"某 type 就强制某 size")。

## 依赖方向

```
AIDashCore
   ↑ AIDashUI(本层)
        ↑ AIDashApp
```
只依赖 Core,只被 App 依赖。不得依赖 App,不得被 CLI 依赖(CLI 永不 import UI)。

## 平台 / 语言

macOS 26 / iOS 26,Swift 6.2(比 Core 的 6.0 高,CI 需 Xcode 26 / macos-26 runner)。
视图层默认 `@MainActor`。

## 测试

```bash
swift test --package-path Packages/AIDashUI
```
