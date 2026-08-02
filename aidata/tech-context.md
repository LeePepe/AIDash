---
layer: aidata
kind: python                        # 非 SPM 包;不参与 Swift 包依赖图
role: 上游数据生产。L1 采集 → L2 归一 → L3 合并 → L4 查询 → L5 digest,产出每日 briefing 的卡片 payload,经 aidash CLI 的 XPC 单向推给 App。
depends_on: []                      # 不依赖任何 Swift 层
depended_by: []                     # 无 Swift 层依赖它;耦合点是 CLI 的 XPC 契约(数据流,非编译期依赖)
red_lines:
  - 一律 layer-through:改卡片必须从数据真正产生的那一层往下改,禁止只补 L5 的 aidash.py 或只改渲染器(会产出无上游数据的"空心卡")
  - L1 只追加、只读外部源:采集永不改写数据源;raw 分片 append-only 且过 redaction 红线
  - 严禁提交数据层:L1_collect/raw、L2_normalize/clean、L3_merge/*.db、state.json 均已 gitignore
  - 严禁提交身份标识:账号 / 雇主 / workspace 标识符只放 git-ignored 的 config_local.py;config.py 里默认空字符串(本仓库是 public)
  - 降级不崩(ADR-23):任一源缺失 / 未配置 / 超时都返回 0,digest 照常产出并在 health 里标注
  - 单向依赖:L(n) 只能读 L(n-1);L1 适配器禁止 import L5
test: /usr/bin/python3 -m pytest aidata/tests/ -q
owns: [collect, normalize, merge, serve, build_briefing, push_briefing, warehouse.db, fact_turn, fact_issue, fact_task, fact_pr, fact_ado_pr, dim_model]
---

# aidata Tech Context

## 职责

AIDash 每日 briefing 的**唯一内容生产方**。把散落在本机的 AI 使用遥测
(Claude 会话、Multica issue/run、GitHub/ADO PR、Hermes session、浏览器历史、
新闻源等 20 个源)采集、归一、合并成一个星型数仓,再由 L5 组装成卡片 payload
推给 App。

**AIDash 是"读"侧,aidata 是"写"侧。** Constitution 原则 I(agent 撰写、用户
阅读)在此落地:aidata 就是那个 agent。

## 在整体架构中的位置

```
aidata (本层,Python)
  L1_collect   adapters/<source>.py      → L1_collect/raw/<source>/<date>.jsonl   (append-only,已脱敏)
  L2_normalize (同一个 adapter 清洗)      → L2_normalize/clean/<source>.db        (每源独立)
  L3_merge     merge.py + schema/warehouse.sql → L3_merge/warehouse.db (fact_*/dim_*;仅可合并的源)
  L4_serve     L4_serve/queries/*.sql     → 具名查询
  L5_apps      L5_apps/digest/sources.py  → fetch_* → dataclass 序列/bundle
               L5_apps/digest/aidash.py   → ★ build_briefing() 映射成 Container/Card payload
                                             push_briefing()  → best-effort XPC 推送
        │
        │  ── XPC 缝(aidash CLI 是瘦客户端)──
        ▼
AIDash (Swift 侧)
  aidash CLI → AIDashCore(schema 单源)→ AIDashApp(独占 CloudKit)→ AIDashUI(渲染)
```

依赖是**单向数据流**,不是编译期依赖:aidata 不 import 任何 Swift 代码,Swift
侧也不 import Python。两者的契约是**卡片 payload 的形状**——由
`AIDashCore/Models/Payloads/` 定义,aidata 必须产出匹配的 JSON。

## 契约漂移(最大风险)

payload 形状在两种语言里各写一遍,没有编译器能跨语言校验。防线:

1. `.claude/skills/aidash-content/` —— 改任何 briefing 内容都走它的 layer-through 路由。
2. `.claude/skills/aidash-content/scripts/contract_check.sh` —— lint 四处必须一致:
   aidata 的 mapper、Core 的 `CardType` enum、`XPCHandlers.payloadSchemas`、UI 的 `CardRouter`。
   它是 lint 不是证明,过了仍要看真实渲染。

**并入同一 repo 的收益就在这里**:现在改一张卡可以在一个 commit 里同时改
Python 产出端和 Swift 渲染端,契约不再跨 repo 漂移。

## 配置与身份(重要)

- `config.py` 是**唯一路径来源**,`AIDATA_HOME = Path(__file__).resolve().parent`
  ——整个目录搬迁后自动正确,不要改成绝对路径。
- **本仓库是 public**。账号 / 雇主 / workspace 标识符一律放 `config_local.py`
  (已 gitignore);`config.py` 里默认空字符串。`config.py` 最后一行
  `from config_local import *` 做覆盖,所以本地文件只需写要改的项。
- 没有 `config_local.py` 的机器(全新 clone / CI)也能跑:相关源降级为 0,
  测试全绿。模板见 `config_local.example.py`。

## 测试

```bash
/usr/bin/python3 -m pytest aidata/tests/ -q
```

**注意 Python 版本**:测试用 `/usr/bin/python3`(系统 3.13,装了 pytest);
04:00 的 cron 链用 `python3`(homebrew 3.14,**没装 pytest**)。两者都能
`import config`。

测试全部 hermetic ——不依赖 `config_local.py`、不打网络。`@pytest.mark.integration`
标记的会读已构建的 warehouse.db,不存在时优雅跳过。

> 已知:`test_digest_golden`、`test_warehouse_integrity`、`test_work_by_project_card`
> 三个用例在迁入前即为失败状态(与本次迁移无关),尚未修复。

## 运维:04:00 cron 链

`scripts/aidata_digest_run.sh` 串起 collect → normalize → merge → digest(--llm --aidash)。
由 Hermes cron job `aidata-digest`(`0 4 * * *`)触发。

⚠️ **双维护点**:cron 实际执行的是 `~/.hermes/scripts/aidata_digest_run.sh`,
那是一份**独立拷贝**而非软链。改了 repo 里的版本必须同步过去:

```bash
cp aidata/scripts/aidata_digest_run.sh ~/.hermes/scripts/aidata_digest_run.sh
```

历史上这条链**静默失败过**(见 `docs/daily-digest-and-aidash-push-chain.md`),
所以改完要手动跑一次全链验证,不要等第二天。

## 分层路由(agent 工作范围)

- 改采集 → `aidata/adapters/<source>.py`(同一文件里 collect + normalize)
- 改仓库 schema → `aidata/schema/warehouse.sql` + `aidata/merge.py`
- 改查询 → `aidata/L4_serve/queries/**.sql`
- 改卡片内容 → 先问"这个值在 L1–L4 存在吗":不存在就从上游开始改,
  **不要**只补 `aidata/L5_apps/digest/aidash.py`
- 改渲染 → 那是 Swift 侧,读 `Packages/AIDashUI/tech-context.md`

## 与 local_git 源的自指

`config.LOCAL_GIT_SCAN_ROOTS` 扫 `~/Development` 统计我的提交产出。aidata 并入
AIDash 后不再是独立 git repo,所以它的提交自然归入 AIDash 仓库统计,**不会双计**
——但历史上 aidata 独立时的提交仍记在旧统计里,两段数据不连续。
