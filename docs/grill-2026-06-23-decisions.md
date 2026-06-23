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
| D17 | UserEvent actions v1 | done+star+hide / done+star / done+hide | **done + star（无 hide）**，star 视觉 prominent | done = 完成；star = 正向放大信号；hide 砍掉避免 user 进入"管理"心态 |
| D18 | Past-date briefings v1 | UI 支持 / UI 不支持 / 模糊 | **UI 不支持**（CLI 接受 past dates） | "glanceable today" 是 v1 唯一体验；v2 加历史 navigation 零 schema 变更 |
| D19 | events 排序 tie-breaker | unspecified / timestamp+device / timestamp+device+cardId | **`(timestamp, device, cardId)` lexicographic** | deterministic across runs/machines |
| D20 | CloudKit SLA | 当作硬保证 / 当作目标 | **当作目标，非 SLA** | Apple 不提供 sync 延迟保证；real-world 超出可在 v1.x amendment 中放宽，不作为 defect |

## Plan 阶段决策 (PL-*)

Plan grill 钉死的技术选型，详细 rationale 见 `specs/001-core-briefing-cli/research.md`。

| # | 决策 | 选项 | 拍板 | Rationale |
|---|---|---|---|---|
| PL-1 | CloudKit API + 进程架构 | 两进程各自连 CloudKit / App 单一 author / 混合 | **App-as-service + CLI-as-thin-XPC-client** | 单进程拥有 CloudKit identity，零 sync 冲突；CLI 启动毫秒级；schema 一处 |
| PL-A | XPC 协议形态 | per-method @objc / 单 method JSON-RPC | **单 method `execute(Data)→Data` + Codable envelope** | schema 演进零阻力；CLI/App 升级解耦 |
| PL-A.1 | Schema validation 时机 | App 端唯一 / CLI 本地优先 + App 兜底 | **CLI 本地先验，错误立即返回；App 端再验作为 defense-in-depth** | agent 快速反馈环；CLI 版本漂移防护 |
| PL-B | App lifecycle | LaunchAgent / LaunchDaemon | **LaunchAgent**（user 身份，可访问 iCloud） |
| PL-B.1 | KeepAlive | bare true / dict | **dict + SuccessfulExit=false** | user 可主动 quit |
| PL-B.2 | App 形态 | Dock app / menubar app | **LSUIElement=true 纯 menubar** | "打开看一眼"使用习惯 |
| PL-B.3 | 关 window 行为 | quit / hide | **hide** |
| PL-B.4 | plist 安装 | app 自装 / Makefile / settings 按钮 | **app 首次启动自检 + SMAppService 安装** | 用户零摩擦；Apple 现代化推荐 API |
| PL-C | CLI 兜底 | 失败放弃 / 自动拉起 app | **NSWorkspace.openApplication + poll 5s** | 5s 硬编码（不可配），4 exit codes |
| PL-C.1 | CLI exit codes | 自定义 | **0/1/2/3** | 对应 agent 三类 retry 策略 |
| PL-3' | Card payload 多态 | 7 @Model / 巨型 @Model / payloadJSON Data | **payloadJSON Data + Codable dispatch** | SwiftData/CloudKit friendly；schema 在 Codable struct 唯一定义；forward-compat 天然 |
| PL-4 | 项目生成 | XcodeGen / Tuist / pure SPM | **XcodeGen** | 你既有 pattern 熟；YAML 简洁；支持 entitlements/signing |
| PL-5 | 测试框架 | XCTest / Swift Testing | **Swift Testing** | OS 26 + Swift 6 原生首选 |
| PL-6 | device 字段 | UUID / 名称 / 组合 | **`"<deviceName> [<UUID8>]"`** | 人可读 + 改名稳定 |
| PL-7 | CI | GH Actions hosted / self-hosted / Xcode Cloud / git hook / public repo | **GH Actions hosted (A+) + self-hosted 预案** | 免费额度足够 (~40 PR/月)，超额备案 |
| PL-8 | History retention | 永久 / 30 / 90 / 可配置 | **90 天硬编码，app 自动 cleanup** | 季度回看合理；v2 history navigation 直接可用；CloudKit quota 毫无压力 |

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
  "device": "iPhone-15",     // 触发设备
  "cardId": "uuid",          // 哪张卡
  "action": "done"           // v1 白名单: done | star
                             // hide 砍掉（D17），v2 可加，不需要 schema 变更
}
```

UserEvent 是 append-only；agent 通过 `aidash events pull` 拉取，自行 dedup
和决定如何影响明天的 briefing。

排序规则（D19）：`(timestamp, device, cardId)` lexicographic tie-breaker，
保证 deterministic output。

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
2. **Spec 001-core-briefing-cli** ✅ 已落地 + post-review 修订（D17-D20）
3. **Plan 001-core-briefing-cli** ✅ 已落地 + 5 个 sub-artifacts
   - `plan.md` 主文档（含 Constitution Check pass + Complexity Tracking）
   - `research.md` (R-1 ~ R-10)
   - `data-model.md`（SwiftData @Model + Codable struct + dispatch）
   - `contracts/cli-surface.md`、`contracts/xpc-protocol.md`、`contracts/cardtype-payloads.md`
   - `quickstart.md`（5 分钟 agent recipe）
4. **下一步**: `/speckit-tasks` 把 plan 转换为 Multica-ready 任务列表
5. **再下一步**：通过 `multica-quick-issue` skill 批量灌进 Multica 由 TL → Planner → Fullstack → Reviewer 执行
6. **Implementation 不用 `/speckit-implement`**：tasks → Multica

## 待处理（不阻塞 AIDash）

- **agent-ops-dashboard 重做**：用户在本次 session 提到，但本次 grill 范围之外。
  另起独立的 grill session 处理，要重新走一遍 mp-grill-with-docs。本次只记录
  「agent-ops 需要重做」这个 fact，不展开。
