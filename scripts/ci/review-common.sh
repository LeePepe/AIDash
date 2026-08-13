#!/usr/bin/env bash
# Shared helper for the two automated review gates (claude / codex).
#
# Sourced — never executed — by scripts/ci/claude-review.sh and
# scripts/ci/codex-review.sh so both gates get identical scope evidence and can
# never drift apart on the one thing that caused a false blocker.
#
# Security: this file lives in the base-branch checkout, exactly like its two
# callers, so the trusted-script boundary is unchanged. It reads PR content only
# through `git show <HEAD_SHA>:<path>` (blob reads) and hands it to a stdlib-only
# Python analyzer. No PR code is checked out and none is executed.

# Byte caps for the evidence block. Explicit, and every trim is announced in the
# emitted text — a silent cut would read to the model as "that's all there is".
REVIEW_SCOPE_MAX_FILE_BYTES="${REVIEW_SCOPE_MAX_FILE_BYTES:-400000}"
REVIEW_SCOPE_MAX_EXCERPT_BYTES="${REVIEW_SCOPE_MAX_EXCERPT_BYTES:-20000}"
REVIEW_SCOPE_MAX_TOTAL_BYTES="${REVIEW_SCOPE_MAX_TOTAL_BYTES:-120000}"

# build_scope_evidence <head_sha> <diff_file> <changed_files_newline_separated>
#
# Prints the evidence block on stdout (possibly empty — most PRs touch no Swift
# modifier lines, and empty is a normal success). Returns non-zero ONLY when the
# analyzer itself fails, so callers can fail closed on a broken tool rather than
# reviewing with silently missing context.
build_scope_evidence() {
    local head_sha="$1" diff_file="$2" changed="$3"
    local count=0
    local -a args=()

    command -v python3 >/dev/null 2>&1 || {
        echo "[review-scope] python3 not found" >&2
        return 1
    }

    while IFS= read -r file; do
        [ -z "$file" ] && continue
        case "$file" in
            *.swift)
                args[count]="--changed-file"
                count=$((count + 1))
                args[count]="$file"
                count=$((count + 1))
                ;;
        esac
    done <<<"$changed"

    # No Swift files changed → nothing to resolve; empty output, success.
    # Checked with a plain counter (not ${#args[@]}) and returned BEFORE any
    # "${args[@]}" expansion, because bash 3.2 — the macOS system bash this
    # runner may use — errors on expanding an empty array under `set -u`.
    [ "$count" -eq 0 ] && return 0

    python3 "$REPO_ROOT/scripts/ci/review_context.py" \
        --head-sha "$head_sha" \
        --diff-file "$diff_file" \
        --max-file-bytes "$REVIEW_SCOPE_MAX_FILE_BYTES" \
        --max-excerpt-bytes "$REVIEW_SCOPE_MAX_EXCERPT_BYTES" \
        --max-total-bytes "$REVIEW_SCOPE_MAX_TOTAL_BYTES" \
        "${args[@]}"
}

# The evidence-discipline clause both prompts share. Printed inside the trusted
# (pre-untrusted-fence) region of the prompt, so it is an instruction, not data.
review_evidence_rules() {
    cat <<'RULES'
【证据纪律 —— Swift modifier 归属】
diff 的 hunk 边界**不是**作用域边界:hunk 里出现的 `}` 未必是外层 body 的收尾,
更常见的是内层闭包(HStack / ForEach / GeometryReader …)的收尾。因此仅凭 hunk
无法判断一个新增的 `.modifier(...)` 挂在谁身上。

所以:
- 任何关于「这个 modifier 作用在哪个视图 / 影响哪块布局」的 **blocker**,必须引用
  下方 SCOPE EVIDENCE 里该行的 receiver + 所在声明,或引用 SCOPE EXCERPTS 里的具体
  行。给不出这种具体证据,就**不能**判 blocker。
- SCOPE EVIDENCE 里标为 `unresolved` 的行 = 没有证据,不是有问题的证据。此时最多写
  成 note(说明无法确定归属),**不得**升级为 blocker。
- 若某文件因超出字节上限未包含在 SCOPE EVIDENCE 中,对该文件的 modifier 归属同样
  不得下 blocker 结论。
- 不确定一律降级为 note。这条只放宽「归属靠猜」的这一类判断;分层越界、崩溃、数据
  破坏、安全问题等有直接 diff 证据的 blocker,判定标准不变,照旧 fail-closed。
RULES
}
