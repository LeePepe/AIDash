#!/usr/bin/env bash
# AIDash 自动 code review —— 在 self-hosted runner 上用本地 `claude` CLI 跑。
#
# 由 .github/workflows/claude-review.yml 调用。设计成确定性门:
#   - 无 blocker           → 贴一条 sticky comment,exit 0(check 绿)
#   - 有 blocker(P0/严重) → 更新 sticky comment,exit 1(check 红 → 挡 auto-merge)
#   - fork PR              → 不执行 PR 代码,贴提示,exit 0(留人工)
#   - 任何工具异常          → exit 1(fail closed,宁可卡住也不放行未审的 diff)
#
# 依赖:git, gh(runner 环境自带 GITHUB_TOKEN), jq, claude(已登录订阅)。
# 需要的环境变量(workflow 注入):
#   PR_NUMBER, BASE_SHA, HEAD_SHA, HEAD_REPO, BASE_REPO, GH_TOKEN

set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

: "${PR_NUMBER:?}"; : "${BASE_SHA:?}"; : "${HEAD_SHA:?}"
: "${HEAD_REPO:?}"; : "${BASE_REPO:?}"

STICKY="<!-- aidash-claude-review -->"

post_sticky() {
    # 维护同一条 sticky 评论(避免每次 synchronize 刷屏)。$1=正文。
    # 用 REST 直接按 marker 找本 bot 已发的那条并 PATCH;没有则新建。
    local body="$1" id
    id="$(gh api "repos/$BASE_REPO/issues/$PR_NUMBER/comments" --paginate \
        --jq "[.[] | select(.body | contains(\"$STICKY\"))] | last | .id" 2>/dev/null || true)"
    if [ -n "$id" ] && [ "$id" != "null" ]; then
        gh api -X PATCH "repos/$BASE_REPO/issues/comments/$id" -f body="$body" >/dev/null \
            && return 0
    fi
    gh pr comment "$PR_NUMBER" --body "$body" >/dev/null
}

# ---- fork PR:不在本机执行其代码 ---------------------------------------
if [ "$HEAD_REPO" != "$BASE_REPO" ]; then
    post_sticky "$STICKY
🔒 **自动 review 已跳过 —— 这是来自 fork 的 PR。**

出于 self-hosted runner 安全考虑,fork PR 不在维护者机器上执行。请人工 review。"
    echo "[claude-review] fork PR ($HEAD_REPO != $BASE_REPO); skipped, exit 0"
    exit 0
fi

# ---- 取 diff ------------------------------------------------------------
git fetch --no-tags --depth=100 origin "$BASE_SHA" "$HEAD_SHA" 2>/dev/null || true
DIFF="$(git diff "$BASE_SHA...$HEAD_SHA" 2>/dev/null || git diff "$BASE_SHA..$HEAD_SHA")"
CHANGED="$(git diff --name-only "$BASE_SHA...$HEAD_SHA" 2>/dev/null || git diff --name-only "$BASE_SHA..$HEAD_SHA")"

if [ -z "$DIFF" ]; then
    post_sticky "$STICKY
✅ 无代码 diff,自动 review 通过。"
    echo "[claude-review] empty diff; pass"
    exit 0
fi

# diff 过大时截断(保护 CLI 上下文;截断本身在 prompt 里声明)。
MAX_BYTES=200000
TRUNCATED=""
if [ "$(printf %s "$DIFF" | wc -c)" -gt "$MAX_BYTES" ]; then
    DIFF="$(printf %s "$DIFF" | head -c "$MAX_BYTES")"
    TRUNCATED="（diff 已截断至 ${MAX_BYTES} 字节；未覆盖部分请人工留意）"
fi

# ---- verdict schema -----------------------------------------------------
SCHEMA='{
  "type":"object","additionalProperties":false,
  "required":["verdict","summary","blockers","notes"],
  "properties":{
    "verdict":{"type":"string","enum":["pass","changes"]},
    "summary":{"type":"string"},
    "blockers":{"type":"array","items":{"type":"object","additionalProperties":false,
      "required":["file","severity","why"],
      "properties":{"file":{"type":"string"},"line":{"type":["integer","null"]},
        "severity":{"type":"string","enum":["critical","high"]},"why":{"type":"string"}}}},
    "notes":{"type":"array","items":{"type":"object","additionalProperties":false,
      "required":["file","note"],
      "properties":{"file":{"type":"string"},"line":{"type":["integer","null"]},"note":{"type":"string"}}}}
  }
}'

# ---- review prompt(贴合 AGENTS.md / 分层约定)---------------------------
PROMPT="你是 AIDash 仓库的自动 code reviewer。这是一个分层的 Swift/macOS 项目
(SPM 包分层:Core / UI / App / CLI)。只 review 下面的 diff,按仓库约定判定。

判 blocker(critical/high,会挡合并)的维度,按优先级:
1. 分层反向依赖:UI 不得反向依赖 App;CLI 不得 import UI;下层不得 import 上层。
   新增的 import 越界 = critical。
2. 明显 bug / 崩溃 / 数据破坏 / 并发错误 / 资源泄漏。
3. 安全:硬编码密钥、注入、未校验的外部输入。
4. 改了 .swift 源码却完全没有对应测试改动(除非 diff 里有 commit 说明 Allow-No-Tests)。

非阻塞(notes,不挡合并):命名、可读性、小的可维护性问题、可选优化。

只依据 diff 事实,不臆测未展示的代码。宁缺毋滥:只有真正确定的问题才进 blockers。

改动文件:
$CHANGED
$TRUNCATED

DIFF:
$DIFF"

echo "[claude-review] running claude on PR #$PR_NUMBER ($(printf %s "$CHANGED" | wc -l | tr -d ' ') files)..."

RAW="$(printf %s "$PROMPT" | claude -p \
    --output-format json \
    --json-schema "$SCHEMA" 2>/tmp/claude-review.err)"
CLI_RC=$?

if [ "$CLI_RC" -ne 0 ] || [ -z "$RAW" ]; then
    echo "[claude-review] ❌ claude CLI 失败 (rc=$CLI_RC)"; cat /tmp/claude-review.err >&2 || true
    post_sticky "$STICKY
⚠️ 自动 review 未能完成(claude CLI 异常)。为安全起见 **暂不放行**,请人工检查或重跑。"
    exit 1
fi

# .structured_output 是已解析对象;.result 是同内容的 JSON 字符串,做兜底。
VERDICT_JSON="$(printf %s "$RAW" | jq -c '.structured_output // (.result | fromjson)' 2>/dev/null)"
if [ -z "$VERDICT_JSON" ] || [ "$VERDICT_JSON" = "null" ]; then
    echo "[claude-review] ❌ 无法解析 verdict"; printf %s "$RAW" | head -c 2000 >&2
    post_sticky "$STICKY
⚠️ 自动 review 输出无法解析。为安全起见 **暂不放行**,请人工检查或重跑。"
    exit 1
fi

VERDICT="$(printf %s "$VERDICT_JSON" | jq -r '.verdict')"
SUMMARY="$(printf %s "$VERDICT_JSON" | jq -r '.summary')"
N_BLOCK="$(printf %s "$VERDICT_JSON" | jq -r '.blockers | length')"

# 渲染评论正文
render() {
    printf '%s\n' "$STICKY"
    if [ "$VERDICT" = "changes" ]; then
        printf '## 🔴 自动 review:需要修改（%s 个阻塞项）\n\n' "$N_BLOCK"
    else
        printf '## ✅ 自动 review:通过\n\n'
    fi
    printf '%s\n' "$SUMMARY"
    if [ "$N_BLOCK" -gt 0 ]; then
        printf '\n### 阻塞项\n'
        printf %s "$VERDICT_JSON" | jq -r \
            '.blockers[] | "- **\(.severity)** `\(.file)\(if .line then ":\(.line)" else "" end)` — \(.why)"'
    fi
    local n_notes
    n_notes="$(printf %s "$VERDICT_JSON" | jq -r '.notes | length')"
    if [ "$n_notes" -gt 0 ]; then
        printf '\n### 建议（不阻塞）\n'
        printf %s "$VERDICT_JSON" | jq -r \
            '.notes[] | "- `\(.file)\(if .line then ":\(.line)" else "" end)` — \(.note)"'
    fi
    printf '\n\n<sub>由本地 claude 自动生成。critical/high = 阻塞合并。</sub>\n'
}
BODY="$(render)"

if [ "$VERDICT" = "changes" ] && [ "$N_BLOCK" -gt 0 ]; then
    post_sticky "$BODY"
    echo "[claude-review] ❌ verdict=changes, blockers=$N_BLOCK → exit 1"
    exit 1
fi

post_sticky "$BODY"
echo "[claude-review] ✅ verdict=pass → exit 0"
exit 0
