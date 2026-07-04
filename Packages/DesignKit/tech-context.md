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

## 与 AIDashUI 的边界

- **DesignKit 拥有颜色**:seed→token 是这里的单一入口。
- **AIDashUI 拥有卡片域语义**:`AIDashTypography` / `AIDashSize` / `AIDashChrome` /
  `CardTypeBadge`——绑定 constitution 的 type/size/style 三正交维度,是 briefing 专用。
- AIDashUI 的**颜色用法**应消费 DesignKit(迁移进行中,见 Multica issue);几何/排版 token
  留在 AIDashUI。

## 约束(red_lines 详见 frontmatter)

设计红线是 constitution §Design System & Tokens 的投影,不在本层新增独立规则;
宪法变则同步本层 frontmatter。

## 构建 / 测试

```bash
swift build --package-path Packages/DesignKit
swift test  --package-path Packages/DesignKit
```
