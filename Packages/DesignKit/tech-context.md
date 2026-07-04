---
layer: DesignKit
role: seed 色彩系统(单源)+ 通用 SwiftUI 组件词汇。零本地依赖,AIDash 颜色的规范源,被 AIDashUI 消费。
depends_on: []                      # 零依赖(仅 Apple 框架)
depended_by: [AIDashUI]
red_lines:                          # 投影自 constitution §Design System & Tokens + design-language 7 条
  - 颜色单源:makePrimaryPalette 是 seed→token 的唯一入口;禁止散落 hex(仅本层色彩源文件可含 hex)
  - 一个 seed 主题全局;语义色(success/warning/danger)固定,不得新增第二套调色板
  - elevation = 明度分层(bg < card < inner)+ 1px border,不用阴影
  - status 用彩色 pill(StatusPill),不用灰字表达状态
  - 只依赖 Apple 框架;新增非 Apple 依赖需 docs/adr/ 下 ADR
  - Swift 6 严格并发;生产代码禁 fatalError / try! / as!
roles:                              # 层内轴:类角色 → 目录(角色顺序见顶层 canonical_roles)
  Types: [Color]                    # ColorSystem + Theme:seed→token,纯值,不依赖组件
  UI:    [Components]               # Card/Metric/Sparkline/RingGauge/StatusPill:消费 Color
test: swift test --package-path Packages/DesignKit
owns: [Seed, Neutral, PrimaryPalette, Neutrals, Semantic, Theme, makePrimaryPalette, chartPalette, Card, CardInner, Metric, Sparkline, RingGauge, StatusPill, SectionHeader, PillTone]
---

# DesignKit Tech Context

> 本层技术上下文。AIDash 的 **seed 色彩系统规范源** + 通用 SwiftUI 组件词汇。
> 铁律见 `.specify/memory/constitution.md` §Design System & Tokens;上层视图语义 token
> (卡片 type/size/style)在 `Packages/AIDashUI/tech-context.md`。

## 职责

- **seed 色彩系统**:`makePrimaryPalette(seed:isDark:)` 从单个 seed 派生完整 primary token 集;
  `chartPalette` 派生 8 档图表色;`Semantic` 固定 success/warning/danger;`Neutral` 提供
  slate / neutral 两套中性色。**同一套色彩数学与 web 模板 (`color-system.ts`) 逐字一致。**
- **组件词汇**:`Card` / `CardInner` / `Metric` / `Sparkline` / `RingGauge` / `StatusPill` /
  `SectionHeader`——消费上面的 token,不含业务逻辑。

## 依赖方向

```
DesignKit (零本地依赖) ← AIDashUI ← AIDashApp
```
DesignKit 与 AIDashCore 平级(都零本地依赖)但**正交**:Core 管领域模型/存储/XPC,
DesignKit 管视觉。AIDashUI 同时依赖二者。

## 与 AIDashUI 的边界(刻意不同的颜色源)

两层**共享同一设计语言的结构规则与组件词汇,但颜色源刻意不同**——这不是待修的分叉:

- **DesignKit 的颜色源 = seed hex 系统**(`makePrimaryPalette`/`Semantic` 基于 `Color(hex:)`)。
  它的价值在"换 seed → 全表面重主题",且与 web 端 `color-system.ts` **逐字同源**。适用于
  可主题化 / 跨平台 / 非原生的表面。
- **AIDashUI 的颜色源 = 系统语义色**(`.blue`/`.green`/`.orange`/`.accentColor`)。这是
  **constitution 强制的**(§Design System & Tokens line 405-409 + Quality Bar §I P1.4:
  「Hardcoded `Color(hex:)` literals are forbidden」;Per-Type Recipe 表逐行钉死 tint)。
  理由:Apple 原生 briefing app 要**自动继承 OS 深色模式 / 对比度 / 辅助功能适配**,
  这正是系统色给的、hex 值给不了的。
- 因此:**让 AIDashUI 消费 DesignKit 的 hex 颜色会违宪(P1),不做。** AIDashUI 拥有卡片域
  语义(`AIDashTypography`/`AIDashSize`/`AIDashChrome`/`CardTypeBadge`);DesignKit 是这套
  设计语言的**通用载体**(组件词汇 + seed 系统),供 web、未来非原生表面、seed 主题化使用。
- ⚠️ DesignKit 的运行时 `Theme` 目前**未被 AIDashApp 注入**(无 `designTheme`/`environment(\.theme)`),
  即其颜色在本 app 内是备用能力,不参与当前 briefing 渲染。

## 分发模型(跨 repo 同一设计语言)

这套设计语言来自 `design-system` skill,**分发靠"拷贝 + 校准常量",不靠"共享包"**:

- skill 的 `templates/swiftui/` 被**逐字拷进**本 repo 成为 `DesignKit/`(commit `7cd6a9e`);
  web 项目拷 `templates/shared/`。参考实现(如 nocoo/basalt)同理——是 reference 不是库。
- **统一性的真正锚点是"seed 色彩数学逐字一致"**:`makePrimaryPalette`(SwiftUI)与
  `color-system.ts`(web)镜像同一算法与校准常量。语言的一致由"规则+常量相同"保证,
  不由"import 同一 artifact"保证。
- **已知弱点 = 漂移**:各 repo 的拷贝会各自演化,无机制强制它们仍是"同一套"。本轮
  **仅文档化此现状**(用户决定);若未来要防漂,最小手段是给 seed 数学加黄金值测试
  (`makePrimaryPalette(blue)` 必产出固定 hex),让拷贝偏离模板即被 CI 抓。


## 约束(red_lines 详见 frontmatter)

设计红线是 constitution §Design System & Tokens 的投影,不在本层新增独立规则;
宪法变则同步本层 frontmatter。

## 构建 / 测试

```bash
swift build --package-path Packages/DesignKit
swift test  --package-path Packages/DesignKit
```
