# CI 门禁与自动化(gates & automation)

本仓库的合并门禁分三层:**本地 hooks**(快、可绕)、**GitHub Actions**(服务端、
不可绕)、**GitHub ruleset**(把关键 check 变成合并硬门)。

路径到 gate 的单一来源是递归 `CONTEXT.md` 树。`scripts/context/resolve <path>`
给出 owning leaf;`scripts/context/layers <path...>`(或 `--stdin`)产出排序去重的
touched leaves;`scripts/context/run <layer>` 执行该 leaf 当前环境的 gates;
`scripts/context/audit` 保证所有文件唯一归类并核对依赖与 manifest。hooks 不维护
第二份 package/path registry;CI 的 SPM、XcodeGen、App 与 CLI 命令也从 leaf gate 读取。
文档与仓库自动化都路由到 RepoInfra;其 local gate 只跑 resolver/review/hook
检查,不跑 `xcodebuild`。

## 一图

```
建 PR ──► auto-merge.yml         → 立即挂上 squash auto-merge(draft 除外)
       └► build + test (macOS 26) → SPM/App/CLI 构建+测试、frontmatter、tests-with-code
       └► codex-review-target     → self-hosted 本机跑 Codex;required
       └► kimi-review             → self-hosted 本机跑 Kimi;advisory-only
                                      │
        ruleset「main protection」要求:build/aidata + codex-review-target 全绿并与 main 同步
                                      ▼
                            required 门皆绿 → 自动 squash 合并 + 删分支
```

## 三层门

| 层 | 文件 | 触发 | 可绕? |
|---|---|---|---|
| pre-commit / pre-push | `scripts/hooks/*` | 本地 git | `--no-verify` 可绕 |
| CI 构建测试 | `.github/workflows/build.yml` | PR / push main | 否(服务端) |
| review-gate 测试 | `.github/workflows/build.yml` 的 `review-gate` job + `scripts/ci/tests/` | PR / push main | 否 |
| required review | `.github/workflows/codex-review-target.yml` + `scripts/ci/codex-review.sh` | PR | 否 |
| paused legacy review | `.github/workflows/codex-review.yml` | 手动 no-op | — |
| advisory review | `.github/workflows/kimi-review.yml` + `scripts/ci/kimi-review.sh` | PR | 不阻塞 |
| paused review | `.github/workflows/claude-review.yml` | 手动 no-op | — |
| 自动合并 | `.github/workflows/auto-merge.yml` | PR | — |
| ruleset(硬门) | `scripts/rulesets/main-protection.json` | main | admin 可 bypass |

## 自动 review 是怎么工作的

- 跑在维护者本机的 self-hosted runner(标签 `aidash-mac`)。
- `codex-review-target` 使用独立只读 `CODEX_HOME`,是 ruleset 中唯一 required AI check。
- `kimi-review` 固定 tool-less agent 与 `kimi-code/k3`,只更新 advisory sticky comment;
  findings、超时和解析失败均不阻塞 merge。
- `claude-review` 只保留手动 no-op workflow,不再响应 PR。

### 首次安装 runner
```bash
./scripts/ci/setup-runner.sh
# 然后随登录自启:
cd ~/actions-runner-aidash && ./svc.sh install && ./svc.sh start
```

### 安全(public repo + self-hosted 的高危组合)
self-hosted runner + `pull_request` + checkout PR head = 公认高危:step 执行的是 PR 版本的代码。
Kimi 使用 `pull_request_target`,由 base 分支评估 workflow YAML。Codex 的
`codex-review-target.yml` 已落地并于 2026-08-26 同步为线上 required；旧
`pull_request` workflow 已停用:
- Codex/Kimi jobs 都只接收同仓库 PR;fork job 在 GitHub 托管 runner 上跳过本机执行。
- 两者 checkout trusted base。Kimi 的显式 agent声明 `tools: []`、`subagents: []`,
  PR diff 只能作为围栏内数据进入模型。
- 仓库设置已把 **outside collaborators 的 workflow 设为需人工批准**
  (`actions/permissions/fork-pr-contributor-approval = all_external_contributors`)。
- review prompt 显式声明 diff 为**不可信数据**,防止 PR 内对抗性文本诱导 `verdict=pass`。
  该声明是 `review-common.sh` 的 `review_security_notice`,两道门共用一份 —— 信任边界的
  措辞不允许在 claude / codex 之间漂移。

#### 注入判定看**意图**,不看 token(MY-1452)

围栏本身不变(diff 是数据、绝不当指令、发现注入判 blocker),变的是判定依据:
**「这段文字是不是在对你下指令」**,而不是「它有没有出现某个词」。

原措辞把「diff 里出现 `verdict=pass`」直接等同于攻击信号。但门脚本自己就带这个字面量
—— `review-common.sh` 里那句 `echo "... verdict=pass → exit 0"` 就是它的成功日志,
schema 里的 `pass` / `changes` 也是枚举值。结果是**门无法审查自己**:任何动
`scripts/ci/**` 的 PR 都会被自己的源码触发规则,PR #181 就被 codex 门以
`review-common.sh:408`(一行普通 `echo`)判为 high blocker 卡住,且重跑必然复现。

现在明确写出:**同名 token 作为数据出现(日志字符串、schema 枚举、测试断言)不构成注入**,
按普通代码审查即可;要挡的是对 reviewer 说话的祈使句,与它出现在哪个文件无关。
`scripts/ci/tests/test_review_shell.py` 把这条钉死 —— 若哪天有人改回 token 黑名单,
`test_security_notice_does_not_blanket_ban_verdict_tokens` 会红。

## 作用域证据(scope evidence)—— 为什么 review 不只看 diff

**diff 的 hunk 边界不是作用域边界。** hunk 里的一个 `}` 可能是内层闭包的收尾,也可能
是外层 body 的收尾,光看 hunk 分不出来 —— 于是紧跟其后新增的 `.modifier(...)` 到底挂
在谁身上,就成了猜。

PR #171 上两道门(claude / codex)因此同时误判:`private var labelLine` 里的
`.padding(.trailing, trailingInset)` 被说成挂在 `BarListRow.body` 的外层 `VStack` 上,
各自开出一条高危 blocker,卡住了一个本该通过的 PR(MY-1402)。

现在归属由**可信脚本**先算好再交给模型:

| 组件 | 职责 |
|---|---|
| `scripts/ci/swift_scope.py` | 纯词法括号匹配(先抹掉注释与字符串字面量),算出每个 leading-dot modifier 的 receiver 与所在声明 |
| `scripts/ci/review_context.py` | 从 exact-HEAD 读源码,产出 RECEIVER TABLE + 按声明完整摘录的 SCOPE EXCERPTS |
| `scripts/ci/review-common.sh` | 两道门共用的调用入口 + 证据纪律 prompt(避免两边漂移) |
| `scripts/ci/tests/` | pytest;CI 的 `review-gate (pytest)` job 与 RepoInfra local gate 都跑 |

要点:

- **安全边界不变**。脚本仍只在 base checkout 里跑;PR 内容只经 `git show <HEAD>:<file>`
  以 blob 读入,不 checkout、不执行。产出的 evidence 连同 diff 一起放在 prompt 的
  **不可信数据**围栏内 —— 结构(谁挂在谁身上)是脚本算的,文字内容仍是 PR 作者写的。
- **算不出就是没有证据**。词法扫描不敢下结论(括号不平衡、超出字节上限)时标为
  `unresolved`,prompt 明确要求此时最多写 note,**不得**升级为 blocker。
- **"看起来像 modifier" 的门槛故意抬高**。一个 leading-dot 行必须是**被调用的**
  (`.padding(8)` / `.frame(` / `.chartXAxis { … }`),且其上一行以**表达式结尾**
  (`)` `}` `]` 或标识符)才算 modifier。裸成员表达式(`.leading`、`.red`)与实参值
  (`PointMark(` 下面的 `.value(…)`)一律**整行剔除**,不进表 —— 这类行既不是
  modifier,给它编一个 receiver 会以 `resolved=True` 的形式变成**假证据**,比噪音更糟。
  代价是极少数写法(SwiftUI 里几乎不存在的裸属性 modifier)拿不到证据 —— 那是安全的
  方向:宁可没有证据,不要错的证据。
- **多行声明头能被正确归属**。`private func kpiCell(\n … \n) -> some View {` 的关键字
  不在 `{` 那一行;归属靠**括号续行**(`{` 前那个未配对的 `)` 回溯到它的开括号)确定,
  而不是"看上一行"——后者会把 `let viz = vizKind(item)` 当成 `return VStack {` 的声明。

- **只放宽"归属靠猜"这一类**。分层越界、崩溃、数据破坏、安全问题等有直接 diff 证据的
  blocker,判定标准不变。
- **仍然 fail-closed**。分析器自身异常(python3 缺失、崩溃)= 工具异常,与 `git fetch`
  失败同级,一律 `exit 1` 不放行。
- 字节上限显式:单文件 400 KB、单摘录 20 KB、整块 120 KB;任何截断都会在文本里写明,
  免得模型把"被截断"读成"就这么多"。


## 门为什么会「静默卡 20 分钟」——以及现在不会了(MY-1404)

PR #171 上两道门连续四次(claude 两次、codex 两次)跑满 20 分钟被 GitHub cancel,
**日志一行输出都没有**。分析器没错,脚本压根没跑到它。

根因在 shell,不在 Python:

- runner(`aidash-mac`)的 PATH 解析到 **Homebrew bash 5.3.15**;
- 该版本下,**body 超过一个 pipe buffer(实测 512 字节)的 heredoc / here-string 会死锁**
  —— bash 先把 body 写进重定向管道,再 fork 读端;body 填满管道后写操作永久阻塞。
  栈是 `do_redirection_internal → heredoc_write → write`;
- macOS 自带 bash 3.2 改用临时文件,**同样的脚本在 `/bin/bash` 下永远复现不出来**。
  MY-1402 因此带着一段 1118 字节的 heredoc(`review_evidence_rules`)合进了 main,
  而它在 CI 里**一次都没被执行过**(MY-1402 自己的 PR 跑的是合并前的 base 脚本)。

这段 heredoc 是两道门**共用**的,且在调用任何 CLI **之前**求值 —— 所以两道门同时、
同样地卡住,而不是各自出了各自的问题。

现在的约束:

| 措施 | 位置 |
|---|---|
| 门脚本里**禁止** `<<` / `<<-` / `<<<`,多行文本一律 `printf` 生成 | `scripts/ci/*.sh` |
| 结构化校验(读源码,不只是跑一遍) | `scripts/ci/tests/test_review_shell.py` |
| CLI 调用套 wall-clock 看门狗,默认 900s(<workflow 的 20 分钟) | `run_with_timeout`,`review-common.sh` |
| 超时按**进程组** TERM→KILL,不留孤儿进程 | 同上 |

看门狗的两个要点:

- **超时依旧 fail-closed**。CLI 卡死 → `rc=124` → 贴 sticky 说明 + `exit 1`,门照旧红。
  变的只是「红得有原因」:15 分钟内给出明确诊断,而不是 20 分钟后一份空日志。
- **`|| rc=$?`,不能裸调用**。workflow 以 `bash -e {0}` 跑脚本,被信号杀掉的子进程
  会让裸 `wait` 直接以 143 终止整个脚本 —— check 仍然红,但连那句诊断都来不及贴,
  又回到了本条要消灭的症状。

> 判定阈值、可信边界、不可信数据围栏、fail-closed 语义都没有放松;只有「文本怎么送进
> 变量」和「卡死怎么收场」变了。

## ruleset 即代码
`scripts/rulesets/main-protection.json` 是唯一真相,改后重跑 `scripts/rulesets/apply`
(幂等 create-or-update)同步到服务端。required 列表只含 Codex;Kimi 与暂停的 Claude
不得加入 required status checks。
