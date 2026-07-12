# AIDash 视觉北极星 (North Star)

> 这是 AIDash UI 现代化的**视觉基准**。它把"好看的现代仪表盘"翻译成 SwiftUI 可执行的具体规则。
> 所有设计决定都锚定到这里,而不是凭感觉。design-reviewer 子代理用它来打分。
>
> **参考来源**(公开视觉语言,无需 Figma):Linear、Vercel Dashboard、Apple 原生 App(Settings / App Store / Stocks)。
> **设计哲学**:Apple 原生精致克制为底 + 现代仪表盘的密度与数据可视化。

---

## 0. 一句话原则

> **留白舍得给,层级拉得开,数字配上图,配色管得住。**

当前界面的四宗罪与对治:
| 病 | 治 |
|---|---|
| 满屏铺开、稀疏 | 最大内容宽度 1200pt 居中 |
| KPI 挤一张大卡 | 每个指标独立成卡,响应式分列 |
| 通篇无图 | sparkline + 环形进度,数字旁配可视化 |
| 卡片平贴、文字单一 | 亮度分层 + 1px 边框 + 三级排版 + 状态胶囊 |

---

## 1. 布局与栅格 (Layout)

- **最大内容宽度**:`1200pt`,水平居中(`.frame(maxWidth: 1200).frame(maxWidth: .infinity)`)。超宽屏不再把卡片拉稀。
- **页面水平内边距**:macOS `24pt` / iOS `20pt`(沿用现有 token)。
- **页面垂直内边距**:顶部/底部 `28pt`。
- **分区(容器)间距**:分区与分区之间 `32pt`(比现在的 24 更舒展)。
- **分区标题到首卡**:`12pt`。
- **KPI 网格**:`LazyVGrid`,`.adaptive(minimum: 220, maximum: 320)`,列间距 `16pt`,行间距 `16pt`。宽屏自然 4 列,窄屏降到 2 列。
- **卡片间距(同组)**:`16pt`。

## 2. 间距阶梯 (Spacing Scale)

只用这套阶梯,**禁止随手数字**(10/15/18 这种):

```
2  4  8  12  16  20  24  28  32  40
```

- 卡内元素垂直间距:`8`(紧凑)/ `12`(标准)。
- 卡内分组之间:`16`。
- 图标与文字:`8` 或 `12`。

## 3. 排版层级 (Typography) —— 至少三级

现代感的关键是**层级拉开**。目标层级(原型阶段直接用 SwiftUI 语义字体):

| 角色 | 字体 | 用途 |
|---|---|---|
| 页面大标题 | `.largeTitle.bold()` | 顶部日期 |
| 分区标题 | `.caption.weight(.semibold)` + `.tracking(0.8)` + `.textCase(.uppercase)` + `.secondary` | 总览 / ADO PR WATCH |
| **KPI 数值** | `.system(size: 34, weight: .bold, design: .rounded)` | 大数字,**这是视线焦点** |
| KPI 标签 | `.caption` `.secondary` 大写 + tracking | 指标名 |
| 卡片标题 | `.headline` | 正文卡头部 |
| 正文 | `.callout` 或 `.body` + `lineSpacing(3)` | 段落 |
| 元信息 | `.caption` `.secondary` | 时间戳 / 引用 / ref |
| 状态胶囊文字 | `.caption2.weight(.semibold)` | badge 内文字 |

规则:
- 数字一律 `design: .rounded`,更现代、更 Apple。
- 长正文必须给 `lineSpacing`,别让文字挤成一坨。
- 同一屏里**至少三种**视觉权重(大标题 / 正文 / caption),不能一片同字号同灰。

## 4. 色彩 (Color) —— 一个种子派生主色,语义色固定

配色统一走 **DesignKit 种子色系统**(`makePrimaryPalette`):给一个品牌种子色
(当前 `appleBlue` = `#007AFF`),用 HSB 公式派生整套主色 token,明暗自适应。
**换 app 只改一个种子即换主题**;绿=好、红=坏这类语义色**不派生、永远固定**。

- **主色 / 强调** 走派生 token,不用系统色硬编码:`theme.primary.primary`(实色)、
  `theme.primary.primarySubtle`(柔和底)、`theme.primary.primaryText`(链接文案)、
  `theme.primary.ring`(focus)。
- **中性(文字/底/边框)** 走 `theme.neutrals.*`(`bg` < `card` < `inner` 三档亮度 +
  发丝边分层):`text1`(正文)、`text2`(次级)、`text3`(元信息)、`border`。
  正文别用最淡的 `text3`(对比不足)。
- **图表** 走 `theme.chart(i)`(从种子色相绕色轮派生的 8 色板,与主色同源协调)。
- **禁止在 UI 层散落 hex/RGB**。hex 只允许出现在色彩系统源码(`ColorSystem.swift`)里;
  视图层一律读 token。这是「令牌纪律」,也是暗色 + 增强对比自动适配的前提。
- **强调克制**:一张卡里最多一个强调色锚点(状态胶囊 或 sparkline 着色),不要又描边又填色又变字色。
- **状态语义色(固定,不随种子变)**:
  - 成功 / 正向 → `theme.success`(绿,PR merged、达标)
  - 警告 / 需注意 → `theme.warning`(橙,卡住、临期)
  - 危险 / 阻塞 → `theme.danger`(红,P0、冲突、超期)
  - 中性 / 信息 → `theme.neutrals.text2`
- **状态胶囊 (pill)** 配方:`色.opacity(0.12~0.16)` 作背景 + 同色全饱和文字/图标,`Capsule()` 形状,内边距 `horizontal 8 / vertical 3`。这是把"纯文字状态"变现代的关键件。

## 5. 卡片与分层 (Card & Elevation)

现代卡片靠**亮度分层**浮起来,不靠阴影(对齐 DesignKit 的无阴影做法):

- **三档亮度(elevation = luminance tiers)**:页面底 `theme.neutrals.bg` < 卡片
  `theme.neutrals.card` < 卡内嵌块 `theme.neutrals.inner`。每升一档亮度提一档,
  层级自然拉开——这取代旧的投影方案。
- **1px 边框**:每张卡叠 `theme.neutrals.border` 的 1px 描边定义边缘(暗色下尤其关键)。
  **不使用 `.shadow`**(除非整个 app 切到 soft-shadow 变体)。
- **圆角**:KPI/卡片 `14pt`,卡内嵌块 `10pt`(`style: .continuous` 连续圆角)。
- **内边距**:卡片 `16`,卡内嵌块 `12`。
- **页面背景**:始终用 `theme.neutrals.bg`,比卡片低一档,卡片才浮得起来。

## 6. KPI 卡结构 (核心改造件)

每个指标 = **独立卡片**(不再共用大卡)。自上而下:

```
┌─────────────────────────┐
│ 指标名 (caption 大写灰)    │   ← label
│                         │
│ 34  天 ↑               │   ← 大数值(rounded bold) + 单位 + 趋势箭头
│ ┌─────────────────┐     │
│ │ ↑ +2 较昨日       │     │   ← 状态胶囊 (pill)
│ └─────────────────┘     │
│ ╱╲╱──╲╱  (sparkline)    │   ← Swift Charts 迷你折线(40pt 高,渐变填充)
└─────────────────────────┘
```

- 比率型指标(如 0% 完成率)用**环形进度**(`Gauge` 或 Swift Charts `SectorMark`)替代 sparkline。
- sparkline:`Chart { AreaMark(渐变) + LineMark }`,`.frame(height: 40)`,着色用状态语义色。
- 原型阶段 sparkline / 环形数据 = 写死的 mock `[Double]`。

## 7. 数据可视化 (Swift Charts)

- `import Charts`(macOS 26 原生支持)。
- **sparkline**:`LineMark` + `AreaMark`(`.foregroundStyle(.linearGradient(...))` 顶部色→透明),隐藏坐标轴(`.chartXAxis(.hidden).chartYAxis(.hidden)`)。
- **环形进度**:`Gauge(value:)` `.gaugeStyle(.accessoryCircularCapacity)`,或 `Chart` + `SectorMark(angularInset:)`。
- 图表克制:无网格、无标签喧宾夺主,只传达趋势/比率。
- 着色与卡片状态语义一致(success=green 等)。

## 8. 正文卡结构 (Prose Card)

解决"文字单一/拥挤":

- **头部行**:`icon badge` + 标题(`.headline`)+ `Spacer` + 时间戳(`.caption .secondary`)。
- **正文**:`.callout` + `lineSpacing(3)`,段落之间 `12pt` 留白分组。
- **列表行**(如 PR 列表):每行末尾用**状态胶囊**(merged=绿 / conflicts=橙 / P0=红)替代纯文字状态。
- 至少三级排版:小节标题 / 正文 / 元信息。

## 9. 验收清单 (design-reviewer 对照打分)

一屏要"现代"需同时满足:
- [ ] 内容有最大宽度,不满屏拉稀
- [ ] KPI 各自独立成卡、分列清晰
- [ ] 每个 KPI 数字旁有 sparkline 或环形图
- [ ] 卡片靠亮度分层 + 1px 边框浮于背景(无阴影)
- [ ] 同屏至少三级排版权重
- [ ] 状态用彩色胶囊而非纯灰字
- [ ] 配色克制,主色走种子派生 token、语义色固定,UI 层无 hex 硬编码
- [ ] 长正文有 lineSpacing,分组有留白

---

## 10. Cockpit 主题 (Dark Cockpit theme) — 当前生产方向

北极星的通用现代仪表盘语言之上,AIDash 采用 **"深色驾驶舱 / 终端"** 主题作为产品人格
(宪法 1.7.0)。它不是另起一套设计语言,而是把同一套**数据驱动卡片系统**在
**主题/token 层**重塑成一个控制台的样子。种子色一换、指标 viz 一换、报头一换,整屏即换脸;
明暗自适应(跟随系统 `colorScheme`)。

- **底盘**:近黑机身(`theme.neutrals` slate 暗档),卡片靠亮度分层 + 1px 边框浮起,**无阴影**
  (沿用 §5)。亮色下加深纸底(让白卡浮起),同一身份两套明暗。
- **签名色**:单一**电光绿**种子(`Seed.lime`,暗 `#C6F04A` / 亮 `#5A8A00`),经
  `makePrimaryPalette` 派生整套主色;语义绿/红/橙**不变**(绿=好、红=坏永不破)。
- **数字**:KPI 用**等宽 tabular** 数字(`design: .monospaced`),读作仪表盘精度而非营销大字。
- **趋势/比率 viz**:series → **bar-spark**(`Sparkbars`,按自身 min…max 归一,缓坡也读得出);
  ratio → **分段容量表**(`SegmentedGauge`,一排点亮/熄灭的格子)替代环形。方向靠字形
  (▲ 升 / ▼ 降 / ▬ 平),好坏靠颜色——两通道解耦,一眼不误读。
- **报头 (masthead)**:顶部日期用终端式等宽读出 + 产品标 + 同步状态行 + 发丝分割线。
- **保留**:每类卡片的 32×32 彩色图标 badge(宪法 P0.5 强制,类型的首要判别channel)——
  这是 cockpit 主题与纯手绘原型的**有意分歧**:图标按类型着色,与 cockpit 的单一强调色并存,
  因为二者位置/含义不同(徽标在卡顶、强调在 viz/胶囊),不冲突。

验收:cockpit 屏在 §9 清单之外,还应做到——底盘近黑、单签名色克制、等宽数字、
bar-spark/分段表、终端报头;明暗两版都 ≥30/35 且零 P0。
