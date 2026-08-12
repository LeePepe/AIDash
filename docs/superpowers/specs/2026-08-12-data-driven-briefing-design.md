# AIDash 数据驱动 Briefing 设计

**日期：** 2026-08-12  
**状态：** 待用户书面复核  
**目标：** 首屏 2 分钟扫读，完整 briefing 不超过宪法规定的 5 分钟；消除空白大卡和孤立数据，增加 token/cost、outcome、返工与质量的交叉信号。

## 1. 已确认的产品原则

1. 不以固定模板先选卡或先选图。
2. CardType 由数据语义决定，size 由数据量/丰富度决定，visualization 由数据关系决定。
3. AIDashUI 负责响应式显示和安全降级，不在视图层猜测业务语义。
4. 字体由 CardType 决定，size 只控制几何与可见数量，不用缩小字体解决空间问题。
5. 内容不足时 `hero → wide → medium → small` 只降级不升级；不保留空白占位。
6. 无变化、无异常、无行动价值的详细指标默认不发卡；但信息预算追求“少而强的交叉信号”，不是机械减少交叉指标。
7. 每个交叉信号必须带比较基线、时间窗、样本量和口径；观察性相关不得表述为因果。

## 2. 数据到卡片的决策链

```text
数据语义
  → CardType
  → 数据量 / 丰富度
  → CardSize 上限
  → 数据关系
  → visualization
  → UI 响应式适配 + effective-size 降级
```

### 2.1 CardType 选择

| 数据语义 | CardType | 例子 |
|---|---|---|
| 单个或多个关联指标 | `metric` | 一次通过率、token/成功结果 |
| 排名或 Top-N | `barList` | 返工 workspace、失败根因 |
| 构成份额 | `stackedBar` | finish reason、model tier mix |
| 二维关系/矩阵 | `relationship`（新） | 成本×质量、项目×日期 |
| 可采取的解释 | `insight` | 返工主因、缓存未回本 |
| 行动集合 | `todoList` | 最多 3 个今日行动 |
| 编辑性摘要 | `digest` | 今日总结 |

`relationship` 是“数据关系”语义，不是“某种图”。它的 payload 使用受控 `visualization` 枚举：

- `scatter`：两个连续变量，如 cost × pass rate。
- `heatmap`：两个分类/时间维度，如 project × day 的 rework tokens。
- `slope`：多个对象的 before/after 变化。

时间趋势继续属于 `metric` 的 series，不为折线图新建 CardType。

### 2.2 CardSize 选择

size 是作者上限，不是必须填满的目标。

| 丰富度 | 建议 size | 显示密度 |
|---|---|---|
| 1 个标量/单状态 | `small` | 一个值 + 迷你趋势/比率 |
| 2–4 个强相关项 | `medium` | 一个主结论 + 有限分解 |
| 5+ 项或真正的二维交叉 | `wide` | 主图 + 结论 + 样本/图例 |
| 需要强调且内容足够的编辑性内容 | `hero` | 仅一个主题，不用于填空 |

数量只是阈值之一。如果 8 项数据彼此无关，应拆分或只发 Top-N，而不是自动 wide。

## 3. Briefing 信息预算

### 首屏（2 分钟）

- 4–6 张高信息卡。
- 先结果，再异常，再行动。
- 必须至少有一个 outcome × resource 交叉信号。
- 行动最多 3 项。

### 完整页（最多 5 分钟）

- 建议 8–10 张卡上限；数据不足时更少。
- 详细归因和参考/新闻位于首屏之后。
- 不以 provider 或采集源组织容器；按结果、效率×质量、异常根因、行动和参考组织。

## 4. 首批交叉信号

### 4.1 Outcome × Tokens

- 当前可计算：`completed tasks / 1M tokens`、`tokens / completed task`、首次完成代理。
- 显式标记 `completion proxy`，不命名为“质量”。
- 未来有 objective eval 后升级为 `passed outcomes / 1M tokens`。

### 4.2 Rework × Root Cause × Workspace

- 使用现有 rework rate/token、root cause 和 workspace 数据。
- 展示 Top-N 返工来源，并将 token 损失与原因绑定。
- 样本小于可靠阈值时不给出强结论。

### 4.3 Cache × Cost × Latency

- 优先 token-weighted hit rate，不用 request hit rate 代替。
- 净收益 = 未缓存反事实成本 - provider/model 实际计价成本。只在供应商存在相应费用时计入 cache write/storage；不伪造不存在的费用。
- 没有完整计价/遥测时，文案限定为“估算”，并保留 request hit rate 作为负载诊断辅助指标。

### 4.4 Cost × Quality

- 第一版只展示 cost × completion/rework proxy。
- 没有 objective eval 前不称为 Pareto frontier。
- 引入 eval 后，`relationship.scatter` 展示 cost per passed outcome × pass rate，气泡可表示样本量。

## 5. 分层实现边界

### aidata

- L4 产出口径明确的交叉查询，不在 L5 临时拼接不可追溯指标。
- L5 使用纯函数选择 CardType/size/visualization，保留选择 reason 供测试与调试。
- 每日应用信息预算；低价值卡被省略而非只是排到底部。

### AIDashCore

- 为 `relationship` 定义锁定 payload，严格校验 visualization 枚举、轴、点/单元数据与样本量。
- CLI schema list/help 与 XPC 广告同步更新。
- 加入 encode/decode、验证失败和 public API 测试。

### AIDashUI

- 渲染 `relationship` 的 scatter/heatmap/slope，使用 Apple Charts/SwiftUI 和现有 DesignKit token。
- wide 采用“主图 + 结论 + 样本/图例”横向结构；窄屏变为纵向堆叠。
- 不内联颜色/字号/间距，不按 size 改字体。
- 当数据不支持 relationship 或丰富度不足时优雅回退，不画误导图。

### DesignKit

- 为 `relationship` 增加独立 `Classification` token，使其 32×32 badge 与现有 CardType 在深/浅色中均可区分。
- 通用图形原语仅消费 `theme.chart(index)`、semantic 与 neutral token；不为 relationship 另建调色板。
- 继续保持零本地依赖和 Apple-framework-only。

### AGENTS.md

- 将“Running tests: don't”改为“不手工重复跑测试；正常 commit/push 必须让 hooks 执行相应测试和构建”。
- 保留本地 host-based `AIDashAppTests` 禁令。
- 明确 hook 失败必须按失败路径回到对应 layer 修复。

## 6. 错误与降级

- 任一数据源缺失不得使 digest 失败；交叉信号不足时整卡省略。
- 分母为零、样本不足或两轴无可比性时，不输出比率/关系图。
- 不支持的 visualization 由 Core/CLI 拒绝，不在 UI 默默猜测。
- UI 解码失败显示无崩溃 fallback，不伪造图表。

## 7. 验证方案

- 实现使用 TDD；各层的测试由正常 commit/push 触发 hooks 执行，不手工重复跑整套测试。
- aidata：数据形状→卡片决策表、信息预算、缺失源、零分母、小样本与 golden briefing。
- Core：`relationship` payload round-trip、schema list/help、错误字段和未知 visualization 拒绝。
- UI：每个 visualization 至少两个 size preview，动态字体、深/浅色和窄/宽视口截图。
- 设计门：生产截图由 design-reviewer 对 `design/north-star.md` 打分，零 P0，分数至少 30/35。

## 8. 范围与分层 commit

实现拆成独立可验证提交：

1. `docs:` 研究、设计、AGENTS.md 测试表述修正。
2. `feat(aidata):` 交叉查询、选卡决策与信息预算。
3. `feat(AIDashCore):` `relationship` schema 与合同。
4. `feat(DesignKit):` relationship 分类 token 与通用图形原语。
5. `feat(AIDashUI):` relationship 图表和 wide 自适应结构。

若实施时发现需要修改 App/CLI 层的非 schema 逻辑，记录为新任务，不扩大当前层 commit。

## 9. 非目标

- 不在 App 侧调用 LLM。
- 不把 completion/end_turn 重命名为质量真值。
- 不在第一版建立完整的通用 eval 平台。
- 不为每种图表新建 CardType。
- 不用更小字体、截断主信息或更多装饰填充 wide 空白。
