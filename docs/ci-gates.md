# CI 门禁与自动化(gates & automation)

本仓库的合并门禁分三层:**本地 hooks**(快、可绕)、**GitHub Actions**(服务端、
不可绕)、**GitHub ruleset**(把关键 check 变成合并硬门)。

## 一图

```
建 PR ──► auto-merge.yml         → 立即挂上 squash auto-merge(draft 除外)
       └► build + test (macOS 26) → SPM/App/CLI 构建+测试、frontmatter、tests-with-code
       └► claude-review           → self-hosted 本机跑 claude,发 review;critical→红
                                      │
        ruleset「main protection」要求:上面两个 check 全绿 + 分支与 main 同步
                                      ▼
                            两门皆绿 → 自动 squash 合并 + 删分支
```

## 三层门

| 层 | 文件 | 触发 | 可绕? |
|---|---|---|---|
| pre-commit / pre-push | `scripts/hooks/*` | 本地 git | `--no-verify` 可绕 |
| CI 构建测试 | `.github/workflows/build.yml` | PR / push main | 否(服务端) |
| 自动 review | `.github/workflows/claude-review.yml` + `scripts/ci/claude-review.sh` | PR | 否 |
| 自动合并 | `.github/workflows/auto-merge.yml` | PR | — |
| ruleset(硬门) | `scripts/rulesets/main-protection.json` | main | admin 可 bypass |

## 自动 review 是怎么工作的

- 跑在**维护者本机的 self-hosted runner**(标签 `aidash-mac`)。
- 用你**已登录订阅**的本地 `claude` CLI,**不需要 ANTHROPIC_API_KEY**。
- `claude -p --json-schema` 产出确定性 verdict:发现 **critical/high** → 脚本 `exit 1`
  → 该 check 变红 → auto-merge 被 ruleset 挡住。仅 notes → 通过。
- **runner 离线 = 该 check 不上报 = PR 卡住不合并**(设计如此:没机器 review 过就不合)。

### 首次安装 runner
```bash
./scripts/ci/setup-runner.sh
# 然后随登录自启:
cd ~/actions-runner-aidash && ./svc.sh install && ./svc.sh start
```

### 安全(public repo)
- fork PR 的代码**不在本机执行**(脚本内 no-op),避免 self-hosted 被滥用跑任意代码。
- 建议 GitHub → Settings → Actions → General →「Fork pull request workflows from
  outside collaborators」设为 **Require approval for all external contributors**。

## ruleset 即代码
`scripts/rulesets/main-protection.json` 是唯一真相,改后重跑 `scripts/rulesets/apply`
(幂等 create-or-update)同步到服务端。**先让 `claude-review` check 至少成功上报过一次,
再把它加进 required 并 apply**,否则新门会把所有 PR 卡死。
