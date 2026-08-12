# Token 效率与 AI 结果评估调研

> 调研深度：standard · 渠道：web / GitHub / academic / 官方工程指南
> 时间：2026-08-11–12 · 主题：个人 AI agent 工作流的 token 效率、结果质量与 dashboard 表达

## 执行摘要

Token 下降不等于效率提升：缓存、压缩、小模型路由都必须在固定质量底线下评估。AI 结果也不能用 `completed` 或 `end_turn` 代替正确性；应分开 objective outcome、首次通过、返工、人类信号与 eval 覆盖率。对 AIDash 而言，最有价值的改造不是再增加原始指标卡，而是把 outcome、token/cost、返工与缓存交叉成少量可决策信号。

## 分级发现

### HIGH：成本优化必须与结果质量联合评估

- OpenAI 的 eval 工作流要求代表性样本、明确 grader 与持续回归；线上 token、时延和状态遥测不足以证明输出正确 [1][2]。
- Anthropic 建议 agent eval 优先评估最终结果或环境状态，而不是强制固定工具调用路径 [3]。
- FrugalGPT 与 RouteLLM 显示模型级联/路由能在特定 benchmark 上降成本且维持质量；这些是特定模型、价格和数据集的结果，不能直接当作 AIDash 收益承诺 [4][5]。

**AIDash 结论**：首要交叉指标是 `successful outcomes / 1M billed-equivalent tokens`，必须同时展示质量底线、样本量和 eval 覆盖率。在 objective grader 尚未建立前，只能命名为 `completed-task proxy`。

### HIGH：LLM-as-judge 可扩展，但不能作为未校准的单一真值

- MT-Bench 报告强 LLM judge 与人类偏好较高一致，同时记录了 position、verbosity 和 self-enhancement bias [6]。
- FairEval 显示交换候选答案位置可显著改变评价结果 [7]。
- OpenAI 与 Anthropic 均建议用人工标签校准自动 grader，且优先可判定的 pass/fail 或 pairwise 任务 [1][3]。

**AIDash 结论**：如引入 judge，aidata 需保存 rubric、judge model/version、候选顺序、理由、重跑方差和人工抽检。UI 展示“已校准/未校准”、样本量和一致率，不显示无上下文的 0–100 总分。

### HIGH：缓存应看 token 加权复用率和 provider-aware 净收益

- OpenAI、Anthropic 和 Google 均为缓存读取/写入提供 usage 或计费语义；仅统计“命中请求数”会高估大量短前缀的价值 [8][9][10]。
- 缓存是前缀复用机制；静态 system/tool/reference 宜放前，动态输入放后 [8][9][10]。
- 净收益必须使用 provider/model 的真实计价语义：Anthropic 等有显式 cache write/read，部分方案还有 storage/TTL 费用；OpenAI 自动 prompt caching 主要表现为 cached-input 折扣，不应伪造写入/存储费。价格会变化，不能在 UI 或 SQL 硬编码长期常数。

**AIDash 结论**：主指标为 `cache_read_tokens / cache_eligible_tokens` 与 provider-aware `counterfactual_uncached_cost - actual_cache_cost`，辅以 request hit rate、重用间隔和 miss reason。

### HIGH：任务完成不等于结果正确

- NIST AI RMF 将 TEVV 与部署后反馈放在持续风险管理循环，而不是一次性总分 [11]。
- `end_turn` 是运行信号，`completed` 是 pipeline 状态；它们可以帮助发现截断、失败和重试，但不能证明 spec 满足或事实正确。
- `pass@k` 与 `pass^k` 衡量相反属性：前者是 k 次至少一次成功，后者是 k 次全部成功 [12][13]。普通 retry 不是受控独立采样，不应误标为 pass@k。

**AIDash 结论**：在评测事实表建立前，显示“首次完成率 / 重试后完成率 / 一致性未评测”，不制造虚假精度。

### MEDIUM：上下文压缩只有在质量保持时才有意义

- LLMLingua/LongLLMLingua 在特定 benchmark 报告高压缩率与加速，但结果受模型、数据集和任务影响，不能外推为生产保证 [14][15]。
- 上下文工程实践建议保留决策、未解问题和关键事实，丢弃冗余工具输出 [16]。这是工程经验，不是对所有 agent 的受控实验。

**AIDash 结论**：将 `compression_ratio` 与 `critical_fact_recall / task_success_delta / post-compaction failure` 成对展示；不做单独的“压缩榜”。

## 与当前 aidata 的对照

### 已可计算

- token、成本、模型、时延、请求量、finish reason。
- cache hit/savings（覆盖受数据源限制）。
- pipeline completion/failure/cancel、返工率、返工 token、失败根因。
- PR/issue outcome proxy、项目/模型/工具成本归因。
- star/done 等行为信号的计数。

### 尚不可计算

- objective outcome pass rate、rubric-level pass/fail、事实性与 spec compliance。
- 严格 pass@k/pass^k。
- judge-human agreement、顺序翻转率、judge 重跑方差。
- star/hide/done rate，因为当前缺少稳定的 impression 分母。
- 真正的 cost-quality Pareto frontier，因为质量轴尚缺 objective eval。

## 产品综合

AIDash 首屏应用少而强的交叉信号，在 2 分钟内回答四个问题，完整 briefing 不超过 5 分钟：

1. 完成了什么？
2. token/cost 是否转化成可验证结果？
3. 质量或返工异常集中在哪里？
4. 今天最多三个行动是什么？

首屏不以 provider 或原始数据源分区，而是以结果、效率×质量、异常线索和行动组织。每个交叉信号必须有基线、时间窗、样本量与口径；观察性相关不得写成因果。无变化、无异常、无行动价值的详细指标不发卡。

## 局限性

- provider 定价、cache TTL 和 usage 字段会变化，实现必须从受控配置或已归一化遥测读取，不把调研时的价格硬编码为永久规则。
- 论文中的成本降低和压缩收益未在 AIDash 个人工作负载上复现。
- 当前大部分“质量”指标是运行或结果代理，必须在 UI 明确标注。

## 参考来源

1. [OpenAI Evals](https://platform.openai.com/docs/guides/evals) — 官方文档。
2. [OpenAI Graders](https://platform.openai.com/docs/guides/graders) — 官方文档。
3. [Demystifying evals for AI agents](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents) — Anthropic Engineering, 2026-01-09。
4. [FrugalGPT](https://arxiv.org/abs/2305.05176) — Chen, Zaharia, Zou, 2023。
5. [RouteLLM](https://arxiv.org/abs/2406.18665) — Ong et al., 2024/2025。
6. [Judging LLM-as-a-Judge with MT-Bench and Chatbot Arena](https://arxiv.org/abs/2306.05685) — Zheng et al., 2023。
7. [Large Language Models are not Fair Evaluators](https://arxiv.org/abs/2305.17926) — Wang et al., 2023。
8. [OpenAI Prompt Caching](https://platform.openai.com/docs/guides/prompt-caching) — 官方文档。
9. [Anthropic Prompt Caching](https://docs.anthropic.com/en/docs/build-with-claude/prompt-caching) — 官方文档。
10. [Gemini Context Caching](https://ai.google.dev/gemini-api/docs/caching) — Google 官方文档。
11. [NIST AI Risk Management Framework](https://www.nist.gov/itl/ai-risk-management-framework) — NIST, 2023。
12. [Evaluating Large Language Models Trained on Code](https://arxiv.org/abs/2107.03374) — Chen et al., 2021。
13. [τ-bench](https://arxiv.org/abs/2406.12045) — Yao et al., 2024。
14. [LLMLingua](https://arxiv.org/abs/2310.05736) — Jiang et al., 2023。
15. [LongLLMLingua](https://arxiv.org/abs/2310.06839) — Jiang et al., 2023/2024。
16. [Effective context engineering for AI agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents) — Anthropic Engineering, 2025。
