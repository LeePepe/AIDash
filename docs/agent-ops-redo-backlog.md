# agent-ops-dashboard 重做 · Backlog

> 创建于 2026-06-23，AIDash grill session 期间。
>
> **用户原话**：「我也需要重做 agent-ops-dashboard」
>
> 本文档**仅占位**，正式规划需要另起一次 grill session。

## 当前 agent-ops-dashboard 状态

- 路径：`~/Development/agent-ops-dashboard/`
- 技术栈：FastAPI + React + Vite，launchd 跑在 port 47823
- 主要数据源：
  - `~/.hermes/state.db`（session/cost/token 数据）
  - Multica daemon 日志
  - Symphony Hub（PR 数据，via MonitorSelf）
  - `agent_ops.db`（agent register/heartbeat/task/workflow）
- 主要功能：
  - 每个 agent 的 status card（registry.yaml 注册）
  - Daily fleet report + per-agent report
  - KPI cards + line graphs（per-agent report_template）
  - Workflow transitions 时间线
  - PR Analyzer / Crash Pipeline 等专用页面

## 为什么需要重做（grill 期间用户的暗示）

- 现版本是「监控 / 运维」气质，UI 密度高，为 debug 优化
- 跟新做的 AIDash（个人简报气质）边界模糊，需要重新定位
- 没有明确产品 mission，功能堆积式增长

## 重做时需要 grill 的核心问题（占位）

1. **重新定位**：agent-ops 究竟是「运维监控」（与 Datadog / Grafana 类）还是
   「个人 agent 工作台」（跟 AIDash 互补，agent-ops 是后台/debug 视角，
   AIDash 是前台/briefing 视角）？
2. **数据源策略**：继续聚合多个外部数据源（Hermes/Multica/Symphony），
   还是收敛到自有 schema？
3. **agent registry 的边界**：跟 AIDash 的 agent author 关系怎么处理？
   AIDash 的 agent 要在 agent-ops 里也注册吗？
4. **保留 / 砍 / 迁移哪些现有功能**：PR Analyzer、Crash Pipeline 是不是
   应该独立成专用 app？
5. **是否仍是 web，还是也走 native？**

## 决议

**本次 grill session 不展开**。AIDash 完成 spec/plan/tasks 阶段后，
另起独立 grill session 处理 agent-ops 重做。

如果在此期间发现 AIDash 与 agent-ops 的边界争议（比如某个数据应该
属于谁），先记录到本文档「待澄清」章节，**不修改 AIDash constitution**。

## 待澄清

（空）
