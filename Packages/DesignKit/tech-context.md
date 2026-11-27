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
owns: [Seed, Neutral, PrimaryPalette, Neutrals, Semantic, Classification, TextRole, Theme, dynamicSystemColor, makePrimaryPalette, makeDynamicPrimaryPalette, chartPalette, dynamicChartPalette, Card, CardInner, Metric, Sparkline, RingGauge, StatusPill, SectionHeader, PillTone]
---

# DesignKit Tech Context

> 本层技术上下文。AIDash 的 **seed 色彩系统规范源** + 通用 SwiftUI 组件词汇。
> 铁律见 `.specify/memory/constitution.md` §Design System & Tokens;上层视图语义 token
> (卡片 type/size/style)在 `Packages/AIDashUI/tech-context.md`。

## 职责

- **seed 色彩系统**:`makePrimaryPalette(seed:isDark:darkAnchor:)` 与 `makeDynamicPrimaryPalette(seed:darkAnchor:)` 从单个 seed 派生完整
  primary token 集;`chartPalette` / `dynamicChartPalette` 派生 8 档图表色;`Semantic` 固定 success/warning/danger;
  `Neutral` 提供 slate / neutral 两套中性色。所有令牌均通过 `NSColor(name: nil) { appearance in ... }` / `UIColor { traits in ... }` 在绘制期跟随系统外观动态解析。
- **组件词汇**:`Card` / `CardInner` / `Metric` / `Sparkline` / `RingGauge` / `StatusPill` /
  `SectionHeader`——直接消费 `Theme.system` 动态令牌,不含业务逻辑。

## Dark anchor(单 seed 的深色锚点,非第二套调色板)

通用深色规则 `b + 0.06` 假设「亮色 seed 已在色相/饱和度上接近深色目标,只需从近黑提亮」。
五个标准 seed 成立;`lime` **不成立**——亮值 `#5A8A00` 为在白底存活被刻意压深
(h 80.9°, s 1.00, b 0.54),而宪法 1.7.0 / `design/north-star.md` §10 规定的签名色是
`#C6F04A`(h 75.2°, s 0.69, b 0.94):**色相要降约 6°、饱和度要降约 0.31,任何提亮都到不了**。
旧式派生得 `#679908`(卡片底对比 4.99:1,签名色为 12.97:1)——即 MY-1399 的 P0。

因此 `Seed.darkAnchorHex` 只为**这一个 seed** 固定深色 primary;整条深色 ramp 仍由该锚点
用同一套 HSB 关系派生,`Semantic` / `Classification` 不动。**这是「一个 seed 系统」的锚点
校准,不是第二套调色板**;其余 seed 返回 `nil`,走标准 HSB 派生,并由
`ColorSystemTests` 的黄金值锁死。

## 可访问性角色 token(text role + on-subtle)

同一个语义色**作填充**和**作小字**所需的明度不同。旧 `StatusPill` 让文字与填充同色,
文字落在自身 16% 淡化上,实测浅色 success 1.95:1 / warning 1.93:1——远低于 4.5:1。

- `TextRole`(`heading` / `body` / `meta`)+ `Neutrals.text(_:)`:让消费方表达**意图**而非
  凭眼挑明度档。`body` 恒解析到 `text2`(各底 ≥4.5:1),**永不落到 `text3`**——把
  north-star §4「正文别用 text3」从建议变成可执行约束。`meta` 保证 ≥3:1。
- `Semantic.{success,warning,danger}OnSubtle`:同三个色相的小字变体,校准到在**自身淡化底**
  上跨两套中性色 × card/inner/bg 均 ≥4.5:1。色相保持不变(绿仍读作绿)。
- `PrimaryPalette.onPrimarySubtle` 从 `primaryText` 解耦并加深/提亮,使**每个 seed** 的
  primary pill 都达标。
- 验收由 `ContrastTests` **实测** WCAG 比值(含 source-over 合成),不是查表断言。


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
- **AIDashUI 消费 DesignKit 颜色**:视图直接读取 `Theme.system`——
  `CardTypeBadge` 用 `Theme.system.classificationTint(...)`;stripe/trend/sparkline/priority 用
  `Theme.system.success/.warning/.danger/.primary.primary`。AIDashUI **不内联任何颜色字面量**
  (系统色 `.blue/.green` 或 hex 都不行),仅保留文本语义角色 `.primary/.secondary/.tertiary`。
- **AIDashUI 拥有卡片域几何/排版语义**:`AIDashTypography`/`AIDashSize`/`AIDashChrome`——
  绑定 constitution 的 type/size/style 三正交维度,是 briefing 专用,留在 AIDashUI。
- **运行时动态系统外观**:`Theme.system` 是全局唯一系统级动态主题(`Seed.appleBlue` + `Neutral.slate`),
  底层通过 `NSColor(name: nil) { appearance in ... }` / `UIColor { traits in ... }` 在绘制期直接读取系统外观
  (`NSAppearance` `.aqua`/`.darkAqua` 与 `UITraitCollection.userInterfaceStyle`),零平行环境键或手动切换状态。
- **宪法依据**:constitution 1.6.0 §Design System & Tokens + Quality Bar §I P1.4——
  颜色 MUST 来自 package token 源,视图 MUST NOT 内联颜色。分类 tint 用固定 light/dark
  hex 对(非 seed 派生),保证 6 色恒可区分且保留深色模式。

## 黄金值防漂移约束

色彩系统的确定性锚点是 **HSB 派生数学 + 校准常量**:`makePrimaryPalette`、语义色与分类 tint
均由 `ColorSystemTests` 的黄金值测试与 `ContrastTests` 的 WCAG 实测比值锁死,一旦偏离校准常量即被该层单测与 CI 拦截。


## 约束(red_lines 详见 frontmatter)

设计红线是 constitution §Design System & Tokens 的投影,不在本层新增独立规则;
宪法变则同步本层 frontmatter。

## 构建 / 测试

```bash
swift build --package-path Packages/DesignKit
swift test  --package-path Packages/DesignKit
```
