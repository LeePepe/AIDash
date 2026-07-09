---
layer: DesignKit
role: seed 色彩系统(单源)+ 通用 SwiftUI 组件词汇。零本地依赖,AIDash 颜色的规范源,被 AIDashUI 消费。
depends_on: []                      # 零依赖(仅 Apple 框架)
depended_by: [AIDashUI]
red_lines:                          # 投影自 constitution §Design System & Tokens + design-language 7 条
  - 颜色单源:seed→token(makePrimaryPalette)+ Semantic + Classification 是唯一入口;raw hex 仅允许在本层 token 源
  - 一个 seed 主题全局;语义色(success/warning/danger)与分类 tint(Classification)固定,不得新增第二套调色板
  - elevation = 明度分层(bg < card < inner)+ 1px border,不用阴影
  - status 用彩色 pill(StatusPill)作内容级信号(payload 字段驱动,非 style),不用灰字表达状态
  - 只依赖 Apple 框架;新增非 Apple 依赖需 docs/adr/ 下 ADR
  - Swift 6 严格并发;生产代码禁 fatalError / try! / as!
roles:                              # 层内轴:类角色 → 目录(角色顺序见顶层 canonical_roles)
  Types: [Color]                    # ColorSystem + Theme:seed→token,纯值,不依赖组件
  UI:    [Components]               # Card/Metric/Sparkline/RingGauge/StatusPill:消费 Color
test: swift test --package-path Packages/DesignKit
owns: [Seed, Neutral, PrimaryPalette, Neutrals, Semantic, Classification, Theme, makePrimaryPalette, chartPalette, Card, CardInner, Metric, Sparkline, RingGauge, StatusPill, SectionHeader, PillTone]
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

## 与 AIDashUI 的边界(AIDashUI 消费 DesignKit 颜色)

两层**共享同一设计语言**;职责按"颜色源 vs 卡片域语义"切分:

- **DesignKit 拥有颜色**(规范源):seed 系统(`makePrimaryPalette`)、`Semantic`
  (success/warning/danger)、`Classification`(6 个 per-CardType 分类 tint)、`chartPalette`。
  raw hex **只允许存在于此层的 token 源**。
- **AIDashUI 消费 DesignKit 颜色**:视图经 `@Environment(\.theme)` 读 `Theme`——
  `CardTypeBadge` 用 `theme.classificationTint(...)`;stripe/trend/sparkline/priority 用
  `theme.success/.warning/.danger/.primary.primary`。AIDashUI **不内联任何颜色字面量**
  (系统色 `.blue/.green` 或 hex 都不行),仅保留文本语义角色 `.primary/.secondary/.tertiary`。
- **AIDashUI 拥有卡片域几何/排版语义**:`AIDashTypography`/`AIDashSize`/`AIDashChrome`——
  绑定 constitution 的 type/size/style 三正交维度,是 briefing 专用,留在 AIDashUI。
- **运行时注入**:`AIDashApp` 在 `BriefingWindowScene` 用
  `.designTheme(seed: .appleBlue, neutral: .slate)` 注入 `Theme`;视图据此解析所有颜色,
  自动随 colorScheme 出深/浅色变体。
- **宪法依据**:constitution 1.6.0 §Design System & Tokens + Quality Bar §I P1.4——
  颜色 MUST 来自 package token 源,视图 MUST NOT 内联颜色。分类 tint 用固定 light/dark
  hex 对(非 seed 派生),保证 6 色恒可区分且保留深色模式。

## 分发模型(跨 repo 同一设计语言)

这套设计语言来自 `design-system` skill,**分发靠"拷贝 + 校准常量",不靠"共享包"**:

- skill 的 `templates/swiftui/` 被**逐字拷进**本 repo 成为 `DesignKit/`(commit `7cd6a9e`);
  web 项目拷 `templates/shared/`。参考实现(如 nocoo/basalt)同理——是 reference 不是库。
- **统一性的真正锚点是"seed 色彩数学逐字一致"**:`makePrimaryPalette`(SwiftUI)与
  `color-system.ts`(web)镜像同一算法与校准常量。语言的一致由"规则+常量相同"保证,
  不由"import 同一 artifact"保证。
- **已知弱点 = 漂移**:各 repo 的拷贝会各自演化。本层已给 seed 数学 + 分类 tint 加了
  **黄金值测试**(`ColorSystemTests`),拷贝一旦偏离固定 hex 即被该层 test / CI 抓。


## 约束(red_lines 详见 frontmatter)

设计红线是 constitution §Design System & Tokens 的投影,不在本层新增独立规则;
宪法变则同步本层 frontmatter。

## 构建 / 测试

```bash
swift build --package-path Packages/DesignKit
swift test  --package-path Packages/DesignKit
```
