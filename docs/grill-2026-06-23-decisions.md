# AIDash · Design Decision Log

> 这份文档记录了 2026-06-23 grill session（使用 `mp-grill-with-docs` skill）
> 期间敲定的所有产品 + 架构决策。Constitution 是这些决策的浓缩版；本文档
> 保留 trade-off rationale 和被否决的选项，作为后续 spec/plan 阶段的
> reference。

## 决策时间线

| # | 决策 | 选项 | 拍板 | Rationale |
|---|---|---|---|---|
| D1 | 与 agent-ops-dashboard 的关系 | A 替代 / B 复用后端 native client / C 独立轻量 | **C + agent-ops 另起重做** | agent-ops 偏运维监控（高密度表格），AIDash 偏个人简报（卡片留白）。两者气质完全不同，并存合理 |
| D2 | 产品定位 | 个人 AI 助理 / 个人数据看板 / 每日仪式感 | **看板 + 仪式感混合**，自动更新的个人简报 | 用户纯 consumer，agent 单向推内容 |
| D3 | 平台 | macOS only / macOS+iPadOS / 含 iPhone | **macOS + iPadOS + iPhone** | "早上打开看"最自然的设备是手机；SwiftUI 一套代码 adaptive |
| D4 | 数据所有权 | App 维护业务逻辑 / Agent 维护 / 共享 | **Agent 是唯一 author**，app 是纯 reader + event 收集器 | 干净边界；CLI 是 agent 的公共 API |
| D5 | 数据单位 | Daily Briefing / Card Stream | **Daily Briefing**：`Briefing(date) → Container → Card` | 匹配"早上看完今天就关"的仪式感；天然历史归档 |
| D6 | 反向通道（done/star/hide） | 纯只读 / 完整反向 / 轻量事件 | **方案 3：轻量事件信号** | App 立刻 optimistic 反馈；event append-only；agent 离线 pull 自行决定如何用 |
| D7 | Storage | iCloud Drive / CloudKit / User-chosen folder | **CloudKit Private DB** | 用户有 paid dev 账号；CloudKit 不暴露文件系统；秒级 push；structured records；两 record type 独立 |
| D8 | Container 锁定 enum 还是泛型 | 6 个 fixed section / 泛型 container | **泛型 Container**，agent 自定义 title/subtitle/order/layout | App 完全无产品语义；最大化 agent 表达力 |
| D9 | Container nesting | 不嵌套 / 1 层 nesting / 任意深 | **不嵌套**（调研支持，Apple HIG 上限 2 层） | 所有 glanceable briefing 类产品都是扁平的；要分组用 `sectionHeader` card |
| D10 | Card type | 强类型 enum / 弱类型 JSON / 强类型 + markdown 兜底 | **强类型 enum，无 markdown 兜底**，schema 锁死 | Agent 必须按白名单推；CLI help 是 schema 唯一来源 |
| D11 | Container layout | 仅 auto / 多 layout 可选 | **4 选：auto / list / grid / hero** | 给 agent 渲染指令空间 |
| D12 | 项目名 + 路径 | Dash / Briefing / AIDash | **AIDash**，`~/Development/AIDash/` | 用户指定 |
| D13 | OS / Swift | OS 18+ / OS 26 | **OS 26 + Swift 6** | 用户指定；可用 FoundationModels（v1 不使用，保留扩展） |
| D14 | Dependency policy | Zero deps / case-by-case | **case-by-case**，新引入要写 ADR | 用户拒绝硬性 zero；保留弹性 |
| D15 | HTTP client | Alamofire / URLSession | **URLSession**（不写死禁止 Alamofire，未来评估） | 现阶段无 HTTP use case；CloudKit 不走 HTTP |
| D16 | Integration | hermes / claude / 多个 | **Spec Kit 用 hermes 写 spec/plan/tasks；Multica 执行 implement** | tasks.md → Multica issues |

## 数据模型 (Schema v1)

### Briefing

```jsonc
{
  "date": "2026-06-23",                  // YYYY-MM-DD，主键
  "generatedAt": "2026-06-23T06:30:00Z", // agent 最后更新时间
  "generatedBy": "morning-briefer",      // agent 名（人类可读）
  "containers": [ Container, ... ]
}
```

### Container

```jsonc
{
  "id": "uuid",              // agent 生成，update/delete 用
  "title": "agent 自由文本",  // required
  "subtitle": "可选副标题",   // optional
  "order": 20,               // sparse int (10/20/30...)，agent 控制顺序
  "layout": "auto",          // auto | list | grid | hero
  "style": "neutral",        // 复用 card style enum
  "cards": [ Card, ... ]
}
```

### Card

```jsonc
{
  "id": "uuid",              // agent 生成，update/delete 用
  "type": "metric",          // 强类型 enum，见下
  "size": "medium",          // small | medium | wide | hero
  "style": "neutral",        // neutral | success | warning | accent
  "payload": { ... }         // 按 type 强类型 struct，schema 锁死
}
```

### Card Types (v1 白名单)

| type | payload shape | size 渲染规则 |
|---|---|---|
| `metric` | `{items: [{label, value, unit?, trend?}]}` | small: 1, medium: 2-3, wide: 6-8, hero: featured 1 |
| `insight` | `{title, body, citations?: [{label, url}]}` | small: title only, medium: 截断, wide/hero: 全文 |
| `agentSummary` | `{agentName, completed: [{title, ref?}], stats?}` | size 决定 completed 显示几条 |
| `todoList` | `{items: [{title, priority?, due?, ref?}]}` | size 决定显示前 N 个 |
| `trending` | `{topic, items: [{title, url, score?}]}` | wide 起步 |
| `digest` | `{title, body, sections?: [{heading, paragraphs}]}` | 全文叙事；hero 主推 |
| `sectionHeader` | `{title, subtitle?}` | 容器内分组视觉，无 size 区别 |

### UserEvent

```jsonc
{
  "id": "uuid",
  "timestamp": "2026-06-23T09:15:23Z",
  "device": "iPhone-15",     // 触发设备，agent 分析时去重用
  "cardId": "uuid",          // 哪张卡
  "action": "done"           // done | star | hide | open (后期可扩展)
}
```

UserEvent 是 append-only；agent 通过 `aidash events pull` 拉取，自行 dedup
和决定如何影响明天的 briefing。

## 模块依赖图

```
            ┌──────────────────┐
            │    AIDashCore    │   models, CloudKit client, schema validation
            └────────┬─────────┘
                     │ depends on
        ┌────────────┴────────────┐
        ▼                         ▼
┌───────────────┐         ┌──────────────┐
│   AIDashUI    │         │  aidash CLI  │   (Swift binary, macOS only)
│ (SwiftUI views)         │              │
└───────┬───────┘         └──────────────┘
        │
        ▼
┌───────────────┐
│   AIDashApp   │   macOS / iPadOS / iPhone
└───────────────┘
```

## 后续步骤

1. **Constitution v1.0.0** ✅ 已落地（`.specify/memory/constitution.md`）
2. **下一步**：跑 `/speckit-specify`，把上面 schema 写成详细 spec
3. **再下一步**：`/speckit-plan` 决定具体技术细节（CloudKit 用 `NSPersistentCloudKitContainer`
   还是直接 `CKDatabase`、XcodeGen project.yml、CI 配置等）
4. **再下一步**：`/speckit-tasks` 拆成 Multica issues 可消费的任务
5. **Implementation 不用 `/speckit-implement`**：tasks → multica-quick-issue → TL pipeline

## 待处理（不阻塞 AIDash）

- **agent-ops-dashboard 重做**：用户在本次 session 提到，但本次 grill 范围之外。
  另起独立的 grill session 处理，要重新走一遍 mp-grill-with-docs。本次只记录
  「agent-ops 需要重做」这个 fact，不展开。
