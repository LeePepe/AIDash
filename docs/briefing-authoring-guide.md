# AIDash Briefing 数据模板 (给生成数据的 AI 的规格书)

> 你的任务：为用户生成**每日 briefing** 的结构化数据。UI 是**纯数据驱动**的——
> 界面好不好看，100% 取决于你在这里选的 `layout / size / style / type` 和 payload 是否丰富。
> **黄金法则见文末「反单调清单」。** 违反它，界面就会退回"单列、全一样、无颜色"。

---

## 0. 三层结构

```
Briefing (一天一个)
 └─ Container (分区, 多个)  ← 有 title + layout
     └─ Card (卡片, 多个)   ← 有 type + size + style + payload
```

- **Briefing**：一天一个，`date` + `generatedBy`。
- **Container**：一个分区(如 "Overview" / "Today")。有 `title`、`order`(10/20/30 稀疏排序)、`layout`。
- **Card**：一张卡。三个正交维度 `type`(内容种类) × `size`(几何大小) × `style`(状态色) + `payload`(内容)。

---

## 1. 四个可选值枚举 (只能用这些)

| 维度 | 合法值 | 含义 |
|---|---|---|
| **container.layout** | `grid` `hero` `list` `auto` | 卡片怎么排 |
| **card.type** | `metric` `insight` `digest` `todoList` `trending` `agentSummary` `sectionHeader` | 内容种类 |
| **card.size** | `small` `medium` `wide` `hero` | 几何大小(决定占几列) |
| **card.style** | `neutral` `success` `warning` `accent` | 状态色(只加左侧彩色竖条) |

### layout 怎么选 (决定是不是多列)
- `grid` → **多列自适应网格**。宽屏最多 4 列。**KPI 小卡、并列卡片必用这个。**
- `hero` → 大卡主导，小卡填缝。适合"头条 + 补充"。
- `list` → **强制单列**，每张卡占满整行。适合榜单、长列表。**别滥用——全用 list 就是"单列"病根。**
- `auto` → 按卡片各自 size 自动排。

### size 怎么选 (决定占几列 + 卡多大)
| size | 占列 | 最小高 | 用途 |
|---|---|---|---|
| `small` | 1 列 | 96pt | 单个 KPI 数字 |
| `medium` | 2 列 | 140pt | 2-3 个指标 / 中等卡 |
| `wide` | 占满整行 | 140pt | 列表、需要横向空间 |
| `hero` | 占满整行, 双倍高 | 280pt | 当天头条叙事 |

### style 怎么选 (状态色, 只影响左竖条)
- `neutral` → 无竖条。默认/纯信息。
- `success` → 绿条。正向结果(PR merged、达标、下降的成本)。
- `warning` → 橙条。需注意(卡住、临期、上升的故障数)。
- `accent` → 蓝条。聚焦/亮点/CTA。
> **一个分区里混用 style**,别全 neutral。

---

## 2. 每种 card.type 的 payload schema + 何时用

### `metric` — KPI 大数字 (配 sparkline / 环形图)
**这是最出效果的卡。数字旁必配可视化。**
```json
{"items":[
  {"label":"PRs merged","value":12,"unit":"","trend":"up","higherIsBetter":true,"context":"Sapphire · this week","series":[4,6,5,8,7,10,9,12]},
  {"label":"Coverage","value":87,"unit":"%","ratio":0.87,"context":"Sapphire"}
]}
```
| 字段 | 类型 | 说明 |
|---|---|---|
| `items` | 数组(≥1) | 每个是一个指标 |
| `label` | string | 指标名 |
| `value` | number | 大数字 |
| `unit` | string? | 单位(`%` `h` `s`…),可省 |
| `trend` | `up`/`down`/`flat`? | 渲染成彩色趋势胶囊(颜色见 `higherIsBetter`) |
| **`higherIsBetter`** | bool? | **语义色关键**:数值高/上升是不是好事。决定 sparkline/胶囊配色按"好坏"而非"升降"。见下方⚠️ |
| **`context`** | string? | **上下文小字**:这个数字是哪个项目/什么时间范围(如 `Sapphire · 本周`)。渲染在标签下方。**强烈建议填**,否则用户不知道数字指什么 |
| **`series`** | number[]? | **时间序列 → 迷你 sparkline**(至少 6-8 个点才好看) |
| **`ratio`** | number? (0~1) | **比率 → 环形进度图**(替代 sparkline) |

⚠️ **`higherIsBetter` 决定颜色语义(很重要,别弄反)**:
- 配色按**结果好坏**上色,不是按方向:好=绿、坏=红、无判断=蓝。
- `PRs merged` 越多越好 → `higherIsBetter:true`,上升配绿。
- `Build time` 越低越好 → `higherIsBetter:false`,**下降配绿**(降是好事)。
- `Open incidents` 越低越好 → `higherIsBetter:false`,**上升配红**(升是坏事)。
- 不填 `higherIsBetter` → 不作好坏判断,配中性蓝。
- 比率型(`ratio`)一般不填,走中性蓝环形。

- **绝对值指标**(计数、时长) → 给 `series`,出折线。
- **比率指标**(完成率、覆盖率) → 给 `ratio`,出环形。
- `small` size = 1 个指标独立成卡(推荐,配 grid → KPI 墙)。`medium`+ 可放多个。

### `digest` — 当天叙事散文
```json
{"title":"A strong, incident-light day",
 "subtitle":"All repos · yesterday",
 "body":"Twelve PRs merged... build times trending down.",
 "sections":[
   {"heading":"Shipped","paragraphs":["SAP-301 crash fix.","Cache cut CI 30%."]},
   {"heading":"Blocking today","paragraphs":["Perf review due 5pm."]}
 ]}
```
| 字段 | 类型 | 说明 |
|---|---|---|
| `title` | string | 头部标题 |
| **`subtitle`** | string? | 上下文小字(范围/时间,如 `All repos · yesterday`)。渲染在标题下 |
| `body` | string | 正文段落 |
| `sections` | 数组? | 可选小节(heading + paragraphs[]) |
- **必用 `size:hero`**(它是当天头条)。`layout:hero` 分区里放。
- 渲染成**文章式**(标题+分节段落)。

### `insight` — 单条洞察/观察
```json
{"title":"Build-cache rework is paying off",
 "subtitle":"Sapphire CI · this week",
 "body":"Median CI dropped 180s→124s. Consider extending to integration suite.",
 "citations":[{"label":"CI dashboard","url":"https://..."}]}
```
| `title` | string | 标题 |
| **`subtitle`** | string? | 上下文小字(项目/时间)。渲染在标题下 |
| `body` | string | 正文(渲染成**引言块式**:竖线+大号引言体,一眼区别于 digest) |
| `citations` | 数组? | 引用(label + url,https-only) |
- 适合 `size:wide` + `style:accent`。

### `todoList` — 待办(优先级彩色胶囊)
```json
{"items":[
  {"title":"Reply to perf review","priority":"high"},
  {"title":"Review changelog","priority":"medium","due":"2026-07-08T17:00:00Z"},
  {"title":"Archive branches","priority":"low","ref":"github.com/..."}
]}
```
| `title` | string | 事项 |
| `priority` | `high`/`medium`/`low`? | 渲染成胶囊(high=红/med=橙/low=蓝) |
| `due` | ISO8601 date? | 截止(显示在行尾) |
| `ref` | string? | 关联链接/引用 |
- **混用不同 priority**,胶囊颜色才丰富。`size:wide`。

### `trending` — 榜单(分数胶囊 + sparkline)
```json
{"topic":"Swift / iOS","items":[
  {"title":"Swift 6.1 macro caching","url":"https://...","score":487},
  {"title":"SwiftData refactor","url":"https://...","score":312}
]}
```
| `topic` | string | 榜单主题 |
| `items[].title` | string | 条目 |
| `items[].url` | string | 链接 |
| `items[].score` | number? | 分数(渲染成胶囊;≥2 个有分 → 顶部出分布 sparkline) |
- `size:hero` 时顶部有分数 sparkline。`layout:list`。

### `agentSummary` — 某 agent 今日战果
```json
{"agentName":"Multica",
 "completed":[{"title":"Merged 3 Sapphire PRs","ref":"SAP-297..301"},
              {"title":"Regenerated changelog"}],
 "stats":[{"label":"PRs","value":3},{"label":"Reviews","value":9}]}
```
| `agentName` | string | agent 名 |
| `completed` | 数组 | 完成项(title + ref?) |
| `stats` | 数组? | 统计(label + value) |
- 多 agent 时,每个 agent 一张,放同一 "Agents" 分区。`size:medium`。

### `sectionHeader` — 纯文字分隔符 (无卡片外壳)
```json
{"title":"Afternoon","subtitle":"Post-standup"}
```
- 在一个 container 内分组用,渲染成裸标题,无边框无图标。少用。

---

## 3. 一份"好看" briefing 的推荐骨架

```
Briefing (today)
├─ Container "Overview"      layout: grid    ← KPI 墙
│   ├─ metric small success  (series → 绿 sparkline)
│   ├─ metric small neutral  (series → sparkline)
│   ├─ metric small accent   (ratio  → 环形图)
│   └─ metric small warning  (series → sparkline)
├─ Container "Yesterday"     layout: hero    ← 头条叙事
│   ├─ digest  hero  neutral (带 sections)
│   └─ insight wide  accent  (带 citations)
├─ Container "Today"         layout: grid
│   ├─ todoList wide  warning (混合 priority)
│   └─ agentSummary medium success
└─ Container "Trending"      layout: list
    └─ trending hero  neutral (≥5 条带 score)
```

---

## 4. 反单调清单 (每次生成前自检 —— 违反=界面变丑)

- [ ] **至少 2 个 container 用 `grid` 或 `hero`**,不是全 `list`(否则全单列)。
- [ ] **size 混用**:同屏要有 small(KPI) + hero/wide(叙事),不要全 wide。
- [ ] **style 混用**:出现 ≥3 种 style,不要全 neutral(否则全无色)。
- [ ] **type 混用**:一屏至少 4 种 type(否则"每张都一样")。
- [ ] **每个 metric 都带 `series` 或 `ratio`**(否则数字旁光秃秃没图)。
- [ ] **每个 metric 都带 `context`**(项目/时间范围),digest/insight 带 `subtitle`——否则用户不知道数字/内容指什么。
- [ ] **metric 的 `higherIsBetter` 填对**(越低越好的指标填 `false`),否则语义色会反。
- [ ] **KPI 用 `small` + `grid`**,组成多列指标墙。
- [ ] todoList 的 `priority`、trending 的 `score` 尽量填(才有彩色胶囊)。
- [ ] 语义色对号入座:好事=success、风险=warning、聚焦=accent。

---

## 5. 发布命令 (agent 侧)

```bash
ID() { uuidgen | tr 'A-Z' 'a-z'; }

aidash briefing put --date today --generated-by "my-agent"

C=$(ID)
aidash container put --briefing-date today --id "$C" \
  --title "Overview" --order 10 --layout grid

aidash card put --container-id "$C" --id $(ID) \
  --type metric --size small --style success \
  --payload '{"items":[{"label":"PRs merged","value":12,"trend":"up","series":[4,6,5,8,7,10,9,12]}]}'

# ... 更多卡 ...

aidash briefing publish --date today   # 原子发布,只有此刻才可见
```

- **幂等**:同一逻辑卡用固定 UUID(如 `UUIDv5(name="overview-prs-2026-07-07")`),重跑覆盖不重复。
- **payload 也可 `--payload @file.json`** 从文件读。
- 校验:`ratio` 必须 0~1;payload ≤ 256KB;枚举值只能用第 1 节列的。
