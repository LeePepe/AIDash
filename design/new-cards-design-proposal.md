# AIDash 新数据卡片设计方案（L5 呈现层）

> **设计 lead：my-designer**（工具：dataviz 出图表形态）。锚定 `design/north-star.md`。
> 本方案不含 Swift 代码——实现由数据/呈现层负责。设计 review gate 在实现出截图后补跑 design-reviewer。

## 0. 核心设计判断（lead 的取舍）

菜单栏弹窗宽 320–480pt、垂直滚动——**空间是最稀缺资源。不是 9 项新数据全塞**。判据：
- **每日会变、能驱动行动** → 上屏
- **月度/静态、或纯参考** → 略过或折叠进"深钻"入口（CLI 可查，不占菜单栏）
- **AI 效能因果度量（cache/返工/失败根因）是这个 dashboard 的差异化护城河**（2025-2026 DORA/DX 框架强调、商业工具都没打通个人层）→ **给它专属 section 和视觉重量**

## 1. 信息架构（新老 section 统一排序）

菜单栏日报的阅读优先级 = 顶部先放"今天要不要采取行动"，往下是"发生了什么"，最后"参考/探索"。

| order | Section | 内容 | 新增? |
|---|---|---|---|
| 10 | 🎯 **今日要点**（digest 头 + TODO 融合） | 点评 + 阈值触发的行动项 | 现有微调 |
| 20 | ⚡ **Trending** | 成本/token/请求/浪费/自动化占比 日环比 | 现有 |
| 30 | 🧠 **AI 效能**（新 section，差异化核心） | 缓存命中率、返工率、失败根因、会话质量 | **新增** |
| 40 | ⏱ **时间与产出**（新 section） | app 焦点时长、跨仓 commit | **新增** |
| 50 | 🗂 昨日汇总 | 现有 | 现有 |
| 60 | 🔍 可改良 | 现有 + 模型分层浪费 | 现有增强 |
| 70 | 🛰 GitHub 工具雷达 | 现有 | 现有 |
| 80 | 📰 **新闻雷达**（新 section） | 6 主题新闻标题 | **新增** |

**未上屏（有意略过，理由）**：
- `planner-gap` / `rework-threads` 的**逐 issue 明细清单** → 明细太长，菜单栏放不下；只把**聚合数**（"N 个 issue 跳过了 spec"）放进 🧠AI效能 的 insight，明细留 CLI `aidata query`。
- `browser_history` 域名分布 → 价值偏"生活审计"，与"AI+生产力"定位弱相关，**本轮不上**（数据已采，随时可加）。
- `hermes_tools` 工具调用分布 → 有价值但与会话结构重叠，**折进 🧠AI效能 的次要位置**或本轮略过。

## 2. 每张新卡片（形态 by dataviz + 内容 + 为什么值得）

### 🧠 AI 效能 section（差异化，视觉重量最高）

**卡 A — 缓存命中率**（形态：大数字 stat tile + 迷你 sparkline）
- 主数字 `89.8%`（`.system(34, .bold, .rounded)`），副行"省 80.8% token 成本"，右侧 7 天 sparkline
- 语义色：高命中=绿。sparkline 单主色 `theme.primary`
- **为什么值得**：cache 是头号成本杠杆（省 80%），每日会变，一眼看健康度。这是业界都在追但个人层没人做的指标。

**卡 B — 返工率**（形态：大数字 stat tile + 迷你 sparkline，极性）
- 主数字 `9.1%`（本周），趋势箭头**向下=绿**（返工少是好事）
- 语义色：低绿高红。**为什么值得**：DORA 2024 官方新增指标，衡量"AI 加速是否以质量为代价"。

**卡 C — 失败根因**（形态：水平条形，降序，top 标值）
- 6 类降序：`runtime-offline 39%` / codex-init-fail / queue-timeout…top 直接标百分比
- `runtime-offline`（基础设施问题）用语义色 + 图标（不靠颜色单独区分）
- **为什么值得**：本会话最大洞察——失败绝大多是**基础设施抖动不是 agent 逻辑错**。这个图一眼点破，独一份。

**卡 D — 会话质量**（形态：水平堆叠单条 + 警报）
- 一根横条分 end_turn / tool_use / **max_tokens 截断**，截断段用语义警告色跳出
- **为什么值得**：max_tokens 截断 = 回答没写完/上下文爆了，是隐藏质量警报，堆叠条里一眼可见。

（可选）**insight 文字条**：planner-gap 聚合——"⚠️ N 个 issue 有 Engineer 干活但没走 Planner（该 spec 却跳过）"，点击可 CLI 深钻。

### ⏱ 时间与产出 section

**卡 E — app 焦点时长**（形态：水平条形，降序，标 min）
- top apps：cmux 4.4min / Chrome 1.4min / Outlook 1.3min（今天时间花在哪）
- **为什么值得**：gecko 新采，回答"注意力去哪了"——现有数据完全没有的维度。窄空间用横条不用环形（app 名长）。

**卡 F — 跨仓 commit**（形态：水平条形，降序）
- VitalStride 144 / aidata 98 / AIDash 48（每日编码产出 by repo）
- **为什么值得**：local_git 新采，"PR 是结果、commit 是过程"，补上过程维度。

### 📰 新闻雷达 section

**卡 G — 新闻雷达**（形态：分类标题列表，非图表——沿用 GitHub 雷达的 trending 形态）
- 按 6 主题分组（finance/ai-tech/us-china/china/world），主题用 `theme.chart(i)` 胶囊，每主题 top 2-3 标题
- **为什么值得**：news 新采，把"世界发生了什么"带进日报。dataviz 判定：新闻是文字身份数据，列表对，图表反而错。

### 🔍 可改良 section（增强现有）

**并入 — 模型分层占比**（形态：水平堆叠单条）
- 一根横条：opus-4.6-1m 73.5% / opus-4.7 / gpt-5.4，识别"用大模型干小活"
- **为什么值得**：model-tier-usage，成本浪费信号，融进现有"可改良"而非独立卡（省空间）。

## 3. CardType 需求（给实现层）

| 卡 | 复用现有 CardType | 需新增 |
|---|---|---|
| A/B 缓存/返工率 | `metric`（若支持 sparkline slot）| 若不支持 → metric 加 sparkline 子视图 |
| C/E/F 失败根因/app/commit | — | **新 `barList`**（水平条形+值，降序）——这是最该加的新形态 |
| D/模型分层 会话质量 | — | **新 `stackedBar`**（单条堆叠+段标签+语义警报段）|
| G 新闻雷达 | `trending`（分类列表已支持）| 复用，加主题胶囊 |
| planner-gap insight | `insight` | 复用 |

**建议新增 2 个 CardType**：`barList`（水平条形排行，覆盖 C/E/F/工具分布）+ `stackedBar`（构成占比，覆盖 D/模型分层）。这两个形态覆盖了大部分新数据，是最高杠杆的 UI 投资。

## 4. 差异化如何在视觉上突出（lead 的强调）

🧠 AI 效能 section 是护城河，设计上给它最高重量：
- 放在 Trending **之后、其它之前**（order 30，靠上）
- section 标题可带一句副标"AI 效能因果度量 · 业界少见"
- 卡 A/B 用**最大字号**（34pt rounded）——缓存命中率和返工率是两个"别人没有"的头条数
- 卡 C 失败根因的"基础设施 vs 逻辑"洞察，可在卡底加一行 insight 点破

## 5. 落地顺序建议（给实现层）

1. **先做能直接产出的**（A/B/C/D + 模型分层）——7 个 L4 查询已建，只差 build_briefing 映射 + CardType
2. **新增 `barList` + `stackedBar` 两个 CardType**（最高杠杆，覆盖多卡）
3. **给 5 个无查询源建 L4 查询**（E app焦点/F commit/G 新闻 优先，browser/tools 缓做）
4. 每卡实现后**渲染截图 → design-reviewer 打分**（补跑本方案欠的 review gate）
