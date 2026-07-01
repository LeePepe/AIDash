#!/usr/bin/env bash
# require-tests.sh — "改代码必带测试" 门
#
# 对一段 diff 范围(BASE..HEAD)检查:若改动了产品源码(Sources/**/*.swift)
# 却没有同时改动任何测试文件(Tests/**/*.swift 或 *Tests.swift),则失败。
# 目的:阻止"改代码不带 UT"的提交裸奔进 main。
#
# 用法:
#   scripts/quality/require-tests.sh <base_sha> <head_sha>
#
# 逃生舱(仅限确有正当理由,如纯文案/资源改动):
#   1. 在 push 范围内任一 commit message 里写一行:  Allow-No-Tests: <原因>
#   2. 或设环境变量:  REQUIRE_TESTS=0 git push
#
# 豁免清单:仓库根的 .require-tests-ignore(每行一个 glob,# 开头为注释)。
# 命中清单的源码文件不计入"需要测试"。默认豁免见文件末尾。

set -euo pipefail

BASE="${1:-}"
HEAD="${2:-}"
if [ -z "$BASE" ] || [ -z "$HEAD" ]; then
    echo "[require-tests] usage: require-tests.sh <base_sha> <head_sha>" >&2
    exit 2
fi

if [ "${REQUIRE_TESTS:-1}" = "0" ]; then
    echo "[require-tests] REQUIRE_TESTS=0 → 跳过(逃生舱)。"
    exit 0
fi

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

# --- 逃生舱:commit message 里的 Allow-No-Tests: ---
if git log --format='%B' "$BASE..$HEAD" 2>/dev/null | grep -qiE '^Allow-No-Tests:'; then
    echo "[require-tests] 检测到 Allow-No-Tests: 声明 → 放行。"
    exit 0
fi

changed="$(git diff --name-only "$BASE..$HEAD" -- '*.swift' || true)"
if [ -z "$changed" ]; then
    echo "[require-tests] 本次无 .swift 改动 → 放行。"
    exit 0
fi

# --- 加载豁免 glob ---
ignore_globs=()
if [ -f ".require-tests-ignore" ]; then
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        case "$line" in \#*) continue ;; esac
        ignore_globs+=("$line")
    done < ".require-tests-ignore"
fi

is_ignored() {
    local f="$1"
    for g in "${ignore_globs[@]:-}"; do
        # shellcheck disable=SC2053
        [ -n "$g" ] && [[ "$f" == $g ]] && return 0
    done
    return 1
}

is_test_file() {
    case "$1" in
        */Tests/*|*Tests/*|*Tests.swift|*Test.swift|*Spec.swift) return 0 ;;
        *) return 1 ;;
    esac
}

prod_changed=()
test_changed=0
while IFS= read -r f; do
    [ -z "$f" ] && continue
    if is_test_file "$f"; then
        test_changed=1
        continue
    fi
    # 只关心产品源码目录
    case "$f" in
        */Sources/*|Sources/*) ;;
        *) continue ;;
    esac
    is_ignored "$f" && continue
    prod_changed+=("$f")
done <<<"$changed"

if [ "${#prod_changed[@]}" -eq 0 ]; then
    echo "[require-tests] 改动的源码均被豁免或无产品源码改动 → 放行。"
    exit 0
fi

if [ "$test_changed" -eq 1 ]; then
    echo "[require-tests] ✅ 改了 ${#prod_changed[@]} 个源码文件,且带了测试改动。"
    exit 0
fi

echo "[require-tests] ❌ 改了产品源码但没有任何测试改动:" >&2
for f in "${prod_changed[@]}"; do echo "    - $f" >&2; done
cat >&2 <<'EOF'

  每次改代码请同时补/改测试(哪怕只是补一个断言)。
  确有正当理由跳过(纯文案/资源/生成代码)时,二选一:
    • commit message 里加一行:  Allow-No-Tests: <原因>
    • 或临时:  REQUIRE_TESTS=0 git push
  长期豁免某类文件:编辑 .require-tests-ignore
EOF
exit 1
