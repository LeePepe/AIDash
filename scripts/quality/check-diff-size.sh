#!/usr/bin/env bash
# check-diff-size.sh — "大提交拆分提醒" 门(默认警告,不阻塞)
#
# 对一段 diff 范围(BASE..HEAD)统计改动行数与文件数,超阈值时提醒拆分。
# 默认是 advisory(exit 0),避免误伤合法的大重构;把 DIFF_SIZE_ENFORCE=1
# 打开后超阈值会失败(exit 1)。
#
# 用法:
#   scripts/quality/check-diff-size.sh <base_sha> <head_sha>
#
# 阈值(可用环境变量覆盖):
#   MAX_LINES  (默认 600)   改动行数(增+删)上限
#   MAX_FILES  (默认 15)    改动文件数上限
#   DIFF_SIZE_ENFORCE (默认 0)  设 1 则超阈值失败
#
# 豁免:范围内任一 commit message 含  Allow-Large-Diff: <原因>  则放行。
# 生成/锁文件类改动会被扣除后再比(见 GENERATED_GLOBS)。

set -euo pipefail

BASE="${1:-}"
HEAD="${2:-}"
if [ -z "$BASE" ] || [ -z "$HEAD" ]; then
    echo "[diff-size] usage: check-diff-size.sh <base_sha> <head_sha>" >&2
    exit 2
fi

MAX_LINES="${MAX_LINES:-600}"
MAX_FILES="${MAX_FILES:-15}"
ENFORCE="${DIFF_SIZE_ENFORCE:-0}"

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

if git log --format='%B' "$BASE..$HEAD" 2>/dev/null | grep -qiE '^Allow-Large-Diff:'; then
    echo "[diff-size] 检测到 Allow-Large-Diff: 声明 → 放行。"
    exit 0
fi

# 生成/依赖/资源类文件不计入体量(拆不拆无意义)
GENERATED_GLOBS='(\.pbxproj$|\.xcworkspace|Package\.resolved$|\.lock$|xcuserdata/|\.strings$|\.xcstrings$|/generated/|\.pb\.swift$)'

# numstat: 每行 "增\t删\t文件"
stat="$(git diff --numstat "$BASE..$HEAD" || true)"
if [ -z "$stat" ]; then
    echo "[diff-size] 无改动 → 放行。"
    exit 0
fi

lines=0
files=0
while IFS=$'\t' read -r add del path; do
    [ -z "${path:-}" ] && continue
    # 二进制文件 numstat 是 "-\t-"
    [ "$add" = "-" ] && add=0
    [ "$del" = "-" ] && del=0
    if echo "$path" | grep -qE "$GENERATED_GLOBS"; then
        continue
    fi
    lines=$((lines + add + del))
    files=$((files + 1))
done <<<"$stat"

echo "[diff-size] 有效改动:${lines} 行 / ${files} 文件(阈值 ${MAX_LINES} 行 / ${MAX_FILES} 文件,不含生成文件)"

over=0
[ "$lines" -gt "$MAX_LINES" ] && over=1
[ "$files" -gt "$MAX_FILES" ] && over=1

if [ "$over" -eq 0 ]; then
    echo "[diff-size] ✅ 体量正常。"
    exit 0
fi

cat <<EOF

  ⚠️  本次 push 改动偏大(${lines} 行 / ${files} 文件)。
      大提交难 review、易夹带未测代码。建议拆成更小的、单一关注点的 commit/PR。
      确需一次性提交(如整包引入工具链)时,在 commit message 里加:
        Allow-Large-Diff: <原因>
EOF

if [ "$ENFORCE" = "1" ]; then
    echo "[diff-size] DIFF_SIZE_ENFORCE=1 → 判为失败。" >&2
    exit 1
fi
echo "[diff-size] (advisory,仅提醒,不阻塞)"
exit 0
