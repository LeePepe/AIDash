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

# No heredocs, here-strings, or `<<<` anywhere in the review gates (MY-1404)
# ---------------------------------------------------------------------------
# The gates run under the runner's PATH bash — Homebrew bash 5.3.15 on the
# `aidash-mac` runner — where a heredoc or here-string whose body exceeds one
# pipe buffer (512 bytes measured) DEADLOCKS: bash writes the body into the
# redirection pipe itself before forking the reader, so once the pipe fills,
# the write blocks forever and nothing ever drains it. The stack is literally
#
#     do_redirection_internal → heredoc_write → write (blocked)
#
# It is a silent hang, not an error: no output, no exit code, no diagnostic —
# the step simply sits until the job's 20-minute cap cancels it. That is how
# PR #171 burned four consecutive 20-minute review attempts (runs 31661368515
# and 31661368524) with an empty log, and why BOTH gates failed identically:
# the shared `review_evidence_rules` heredoc below (1118 bytes) is reached
# before either CLI is invoked. macOS system bash 3.2 spools the same body to
# a temp file instead, so this never reproduces under /bin/bash.
#
# Fix, and the standing rule for these scripts: build multi-line text with
# `printf` into a variable and redirect that. Anything above ~512 bytes fed
# through `<<`, `<<-`, or `<<<` is a latent 20-minute stall. The pytest suite
# in scripts/ci/tests/test_review_shell.py enforces this on every push.

# Byte caps for the evidence block. Explicit, and every trim is announced in the
# emitted text — a silent cut would read to the model as "that's all there is".
REVIEW_SCOPE_MAX_FILE_BYTES="${REVIEW_SCOPE_MAX_FILE_BYTES:-400000}"
REVIEW_SCOPE_MAX_EXCERPT_BYTES="${REVIEW_SCOPE_MAX_EXCERPT_BYTES:-20000}"
REVIEW_SCOPE_MAX_TOTAL_BYTES="${REVIEW_SCOPE_MAX_TOTAL_BYTES:-120000}"

# Wall-clock budget for one reviewer CLI call, seconds. Deliberately under the
# workflow's own `timeout-minutes: 20`, so a stuck CLI is caught by US — with a
# log line and a fail-closed exit — instead of by GitHub, which cancels the step
# and leaves an empty log that says nothing about what stalled (MY-1404).
REVIEW_CLI_TIMEOUT_SECONDS="${REVIEW_CLI_TIMEOUT_SECONDS:-900}"

# run_with_timeout <seconds> <command...>
#
# Runs the command with a wall-clock cap, returning its real exit status — or
# `REVIEW_TIMEOUT_RC` (124, matching GNU coreutils `timeout`) when the cap is
# hit. There is no `timeout`/`gtimeout` binary on the `aidash-mac` runner, so
# the watchdog is built from a background sleep rather than assumed present.
#
# The child is killed with TERM, then KILL after a short grace period: the
# runner logged "Terminate orphan process" for exactly these leftovers when
# GitHub cancelled the step, and a gate that leaks CLI processes onto the
# maintainer's own machine each run is its own problem.
#
# Fail-closed contract is unchanged: callers treat any non-zero — timeout very
# much included — as a tool failure that blocks the merge.
REVIEW_TIMEOUT_RC=124

run_with_timeout() {
    local seconds="$1"; shift
    local child_pid watchdog_pid status=0

    # Job control ON for the launch, so the child becomes a PROCESS GROUP
    # LEADER (pgid == pid). Signalling `-$child_pid` then reaches the CLI *and
    # everything it spawned*. Without this, killing the reviewer CLI leaves its
    # helper processes alive on the maintainer's own machine — which is what
    # the runner's "Terminate orphan process" lines were reporting.
    set -m
    "$@" &
    child_pid=$!
    set +m

    # Watchdog: wait out the budget, then escalate TERM → KILL on the group.
    # `kill -0` first so a finished child is never signalled (its pid may have
    # been recycled by then).
    (
        local waited=0
        while [ "$waited" -lt "$seconds" ]; do
            kill -0 "$child_pid" 2>/dev/null || exit 0
            sleep 1
            waited=$((waited + 1))
        done
        kill -0 "$child_pid" 2>/dev/null || exit 0
        kill -TERM "-$child_pid" 2>/dev/null || kill -TERM "$child_pid" 2>/dev/null
        local grace=0
        while [ "$grace" -lt 10 ]; do
            kill -0 "$child_pid" 2>/dev/null || exit 0
            sleep 1
            grace=$((grace + 1))
        done
        kill -KILL "-$child_pid" 2>/dev/null || kill -KILL "$child_pid" 2>/dev/null
    ) &
    watchdog_pid=$!

    # `|| status=$?`, never a bare `wait`: these scripts run under the
    # workflow's `bash -e {0}`, where a bare `wait` on a killed child exits the
    # WHOLE SCRIPT with 143 — before the timeout branch below can post its
    # sticky comment. The gate would still be red, but for an unexplained
    # reason, which is the failure mode MY-1404 is about.
    wait "$child_pid" || status=$?

    # Watchdog outlived its usefulness the moment the child exited.
    kill -KILL "$watchdog_pid" 2>/dev/null || true
    wait "$watchdog_pid" 2>/dev/null || true

    # 143 = 128+SIGTERM, 137 = 128+SIGKILL — i.e. the watchdog fired. Reported
    # as 124 so callers get one unambiguous "timed out" code to message on.
    if [ "$status" -eq 143 ] || [ "$status" -eq 137 ]; then
        return "$REVIEW_TIMEOUT_RC"
    fi
    return "$status"
}

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
    # Process substitution, NOT `<<<"$changed"`: a here-string carries the same
    # deadlock as a heredoc under bash 5.3, and this one is fed the PR's changed
    # -file list — attacker-influenced in LENGTH, which is all that is needed to
    # cross the 512-byte pipe buffer. A PR touching ~10 nested Swift paths gets
    # there, so the old form was a hang waiting for a big enough PR.
    done < <(printf '%s\n' "$changed")

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

# build_coverage_context <head_sha> <base_sha> <diff_file> <changed_files_newline_separated>
#
# When tests are removed in the diff, searches HEAD for existing test functions
# that cover the same production symbols. Returns empty on success when no tests
# were removed (the common case). Returns non-zero ONLY on analyzer failure.
build_coverage_context() {
    local head_sha="$1" base_sha="$2" diff_file="$3" changed="$4"
    local count=0
    local -a args=()

    command -v python3 >/dev/null 2>&1 || {
        echo "[review-coverage] python3 not found" >&2
        return 1
    }

    while IFS= read -r file; do
        [ -z "$file" ] && continue
        args[count]="--changed-file"
        count=$((count + 1))
        args[count]="$file"
        count=$((count + 1))
    done < <(printf '%s\n' "$changed")

    [ "$count" -eq 0 ] && return 0

    python3 "$REPO_ROOT/scripts/ci/coverage_context.py" \
        --head-sha "$head_sha" \
        --base-sha "$base_sha" \
        --diff-file "$diff_file" \
        "${args[@]}"
}

# The evidence-discipline clause both prompts share. Printed inside the trusted
# (pre-untrusted-fence) region of the prompt, so it is an instruction, not data.
#
# Emitted with `printf`, not a heredoc: at 1118 bytes this body is the exact
# thing that deadlocked both gates on PR #171 (see the MY-1404 note at the top
# of this file). The text is unchanged — only the transport is.
review_evidence_rules() {
    printf '%s\n' \
'【证据纪律 —— Swift modifier 归属】' \
'diff 的 hunk 边界**不是**作用域边界:hunk 里出现的 `}` 未必是外层 body 的收尾,' \
'更常见的是内层闭包(HStack / ForEach / GeometryReader …)的收尾。因此仅凭 hunk' \
'无法判断一个新增的 `.modifier(...)` 挂在谁身上。' \
'' \
'所以:' \
'- 任何关于「这个 modifier 作用在哪个视图 / 影响哪块布局」的 **blocker**,必须引用' \
'  下方 SCOPE EVIDENCE 里该行的 receiver + 所在声明,或引用 SCOPE EXCERPTS 里的具体' \
'  行。给不出这种具体证据,就**不能**判 blocker。' \
'- SCOPE EVIDENCE 里标为 `unresolved` 的行 = 没有证据,不是有问题的证据。此时最多写' \
'  成 note(说明无法确定归属),**不得**升级为 blocker。' \
'- 若某文件因超出字节上限未包含在 SCOPE EVIDENCE 中,对该文件的 modifier 归属同样' \
'  不得下 blocker 结论。' \
'- 不确定一律降级为 note。这条只放宽「归属靠猜」的这一类判断;分层越界、崩溃、数据' \
'  破坏、安全问题等有直接 diff 证据的 blocker,判定标准不变,照旧 fail-closed。'
}

# Coverage-discipline clause (MY-1456): prevents false "missing test coverage"
# blockers when tests are removed but equivalent coverage exists at HEAD.
# Matches are ADVISORY candidates — reviewer must verify branch equivalence.
review_coverage_rules() {
    printf '%s\n' \
'【证据纪律 —— 测试覆盖判定】' \
'diff 移除旧测试时,不代表覆盖丢失:被删的测试可能已过时(测旧 throw 路径),而当前' \
'HEAD 中已有新测试覆盖同一条生产分支。仅凭 diff 看到「删了 testX」就判为 blocker' \
'是错误的——必须先检查 COVERAGE CONTEXT(若存在)或 full-HEAD 源码确认该生产路径' \
'确实无其他测试。' \
'' \
'所以:' \
'- COVERAGE CONTEXT 中列出的候选测试基于符号共现检索,是 advisory candidates。' \
'  Reviewer 必须验证候选测试确实测试了相同生产分支后,才能判定覆盖未丢失。' \
'  但若无法确认,结论是降级为 note,**不是升级为 blocker**。' \
'- 要报「移除测试后覆盖丢失」的 blocker,你**必须**提供具体证据:指出哪条生产分支/函数' \
'  在 full-HEAD 中已无任何 test 调用。给不出 file:line 证据 = 不得报 blocker,最多 note。' \
'- 被移除的测试如果测试的是**已不存在的 API**(如旧的 throw 路径被 refactor 掉),其移除' \
'  不构成覆盖降级——这是清理死代码,不是删保护网。' \
'- COVERAGE CONTEXT 中标注 "declaration absent from HEAD" 的 removed tests 已由可信脚本' \
'  验证确实从 HEAD 中消失(不是仅修改)。若一个 test function 仅被修改而非删除,' \
'  它不会出现在 REMOVED TESTS 列表中。' \
'- 不确定一律降级为 note。'
}
