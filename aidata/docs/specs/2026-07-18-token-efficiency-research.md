# Token 效率 / AI coding ROI 指标 — 研究结论（deep-research 2026-07-18）

**来源**: deep-research harness（104 agent，5 search angle，对抗式验证）
**用途**: aidata digest "值不值 / 效率" 指标设计的依据
**关联**: [分层指标设计](2026-07-17-layered-metrics-design.md)

---

## 核心结论（颠覆 naive 假设）

> 没有干净的 AI coding 花费 ROI 倍数。最强、来源最好的结论是：成本由
> **输入/上下文 token 主导**，token 用量**高度随机**（同任务跑不同次差最多 30x），
> 且**更多 token 不买更高准确率**（准确率在中等成本见顶，之后饱和/下降）。
> naive 的 volume/output 指标（LOC、PR 数、commit、"cost per issue closed"）
> 现在**主动误导**——output 几乎免费，LOC 本质追踪 token 花费而非工程价值。

## 五条 high-confidence 发现

1. **成本由 input/context token 主导，不是 output**
   Stanford Digital Economy Lab + Microsoft Research（arXiv 2026）：agentic 任务
   比 code chat 烧 ~1000x token，**input token 驱动成本**。到第 30 轮累计 input
   达 25k-35k token/请求。→ **cache-read ratio 和 input 计量是一等公民**。

2. **更多 token ≠ 更高准确率，且花费随机**
   同任务不同次跑 token 差**最多 30x**；准确率在中等成本见顶后饱和/下降。
   → 单次/单日成本是噪声，**必须滚动窗口聚合 + 配对 outcome 信号**。

3. **便宜的模型可能更贵（overthinking tax）**
   OckBench：某 7B 模型每 token 便宜 50%，但多烧 3.13x token，每任务反而贵 57%。
   → **per-token 价格是陷阱**，正确轴是 **cost/tokens per completed task**。
   ⚠️ 直接修正了我们"降级省 $X"的断言——降级到便宜模型不一定省。

4. **volume/output 指标主动误导**
   LOC、PR、commit、issue 计数追踪的是 token 花费/工具，不是工程价值。
   高 AI 团队 PR 多 98%，但 review 时间涨 91%、bug 涨 9%、org DORA 持平。
   → **验证了"只算 issue 数会误导"的担忧**。

5. **Amdahl 天花板**：coding 只占 SDLC 25-35%，即便 coding 大幅提速，
   org 级影响被稀释到 ~15-25% 上限。→ 别追单一 ROI 数字。

## 推荐的可算指标（用现有数据）

| 指标 | 公式 | 揭示 | 盲点 |
|---|---|---|---|
| **cost-per-completed-task** | Σcost(所有对话，含失败) / count(completed) | 真实单任务成本 | **必须含失败任务花费**，否则低估 |
| **cache-read ratio** | cache_read / (input + cache_creation + cache_read) | 上下文复用效率（主成本杠杆） | 需要 cache 字段分列 |
| **output-token share** | output / total_tokens | 低 = 上下文臃肿主导 | 不反映质量 |
| **accuracy-per-token** | OckScore=Acc−10·log(T/10000)；TAR=Acc/(α·#I+β·#O) | 每 token 的正确性，罚啰嗦 | OckScore 只算 output token（忽略主导成本的 input）；学术指标，非工业标准 |

**质量调整**：outcome 要用 rework 率、review 迭代次数、incident 率调整，
而非裸计数。追踪 spend-per-engineer vs 观测到的影响，而非追一个 ROI 数字。

## 对 aidata 数据的适配

我们现有 `fact_request` 有：input_tokens / output_tokens / cache_read / cache_write /
cost_usd / model / session / tool_call_count / latency，`fact_task` 有 status（含 failed）。
→ **cost-per-completed-task、cache-read ratio、output-share 都能直接算**。
accuracy-per-token 需要"任务成功率"作为 accuracy 代理（fact_task.status）。

## 设计决策（据此修正 M1）

- **"可改进·成本"卡改口径**：不断言"降级省 $X"（overthinking tax），改中性
  "opus 占 X% 花费 + N 次小输出请求"，让用户判断。
- **"值不值"卡不用 naive 比值**：改 cost-per-completed-task（含失败）+ cache-read
  ratio + output-share，滚动窗口而非单日。
