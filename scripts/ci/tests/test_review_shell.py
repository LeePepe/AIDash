#!/usr/bin/env python3
"""Deterministic coverage for the review gates' shell layer (MY-1404).

Why this file exists
--------------------
PR #171 burned four consecutive 20-minute review attempts — two claude, two
codex — that produced **no output at all** before GitHub cancelled the step.
Nothing in the Python analyzer was wrong; the scripts never reached it.

The cause was in the shell. Under the runner's PATH bash (Homebrew bash 5.3.15
on `aidash-mac`), a heredoc or here-string whose body exceeds one pipe buffer
(512 bytes, measured) **deadlocks**: bash writes the body into the redirection
pipe before forking the process that drains it, so a body larger than the
buffer blocks forever in `heredoc_write`. macOS system bash 3.2 spools to a
temp file instead, so it never reproduces under `/bin/bash` — which is exactly
why MY-1402 shipped a 1118-byte heredoc (`review_evidence_rules`) that had
never once executed in CI.

That single shared heredoc is why BOTH gates hung identically: it is evaluated
before either CLI is invoked.

What is pinned here
-------------------
1. No `<<` / `<<-` / `<<<` survives anywhere in the gate scripts. This is the
   structural rule, checked by reading the sources — a test that merely ran the
   current scripts would pass again the day someone adds a new heredoc.
2. The shared prompt clause still emits its exact text, under the SAME bash the
   runner uses. Byte-for-byte: transport changed, wording must not.
3. `run_with_timeout` returns the child's real status, and 124 on timeout,
   killing the whole process group rather than leaking grandchildren.
4. A timed-out CLI still FAILS CLOSED — the property a reviewer gate cannot
   lose while being made more forgiving of hangs.

Every test that spawns a shell picks the same interpreter the workflow does
(`bash -e {0}` off the runner PATH), preferring a Homebrew bash when present:
running these under bash 3.2 would pass while the real gate deadlocks.
"""

from __future__ import annotations

import pathlib
import re
import shutil
import subprocess

import pytest

CI_DIR = pathlib.Path(__file__).resolve().parents[1]
COMMON = CI_DIR / "review-common.sh"
CLAUDE = CI_DIR / "claude-review.sh"
CODEX = CI_DIR / "codex-review.sh"
KIMI = CI_DIR / "kimi-review.sh"
KIMI_AGENT = CI_DIR / "kimi-review-agent.md"
WORKFLOWS = CI_DIR.parents[1] / ".github" / "workflows"

GATE_SCRIPTS = (COMMON, CLAUDE, CODEX)


def test_kimi_is_toolless_advisory_and_claude_is_paused() -> None:
    """Kimi may report findings but cannot execute PR-driven tools or gate merge."""

    kimi_source = KIMI.read_text()
    agent_source = KIMI_AGENT.read_text()
    kimi_workflow = (WORKFLOWS / "kimi-review.yml").read_text()
    codex_target_workflow = (WORKFLOWS / "codex-review-target.yml").read_text()
    codex_legacy_workflow = (WORKFLOWS / "codex-review.yml").read_text()
    claude_workflow = (WORKFLOWS / "claude-review.yml").read_text()
    ruleset = (CI_DIR.parents[1] / "scripts" / "rulesets" / "main-protection.json").read_text()

    assert "tools: []" in agent_source
    assert "subagents: []" in agent_source
    assert '--agent-file "$SCRIPT_DIR/kimi-review-agent.md"' in kimi_source
    assert "--output-format stream-json" in kimi_source
    assert "Advisory only: this check and its findings are not required for merge" in kimi_source
    untrusted_begin = kimi_source.index("===== BEGIN UNTRUSTED PR DIFF")
    changed_paths = kimi_source.index("Changed paths:")
    untrusted_end = kimi_source.index("===== END UNTRUSTED PR DIFF")
    assert untrusted_begin < changed_paths < untrusted_end
    assert not re.search(r"(^|\s)(--yolo|--auto)(\s|$)", kimi_source)
    assert "pull_request_target:" in kimi_workflow
    assert "branches: [main]" in kimi_workflow
    assert "ref: ${{ github.event.pull_request.base.sha }}" in kimi_workflow
    assert "ref: ${{ github.event.pull_request.head.sha }}" not in kimi_workflow
    assert "pull_request_target:" in codex_target_workflow
    assert "codex-review-target:" in codex_target_workflow
    assert "branches: [main]" in codex_target_workflow
    assert "ref: ${{ github.event.pull_request.base.sha }}" in codex_target_workflow
    assert "ref: ${{ github.event.pull_request.head.sha }}" not in codex_target_workflow
    assert "workflow_dispatch:" in codex_legacy_workflow
    assert "pull_request:" not in codex_legacy_workflow
    assert "workflow_dispatch:" in claude_workflow
    assert "pull_request:" not in claude_workflow
    assert '"context": "codex-review-target"' in ruleset
    assert '"context": "claude-review"' not in ruleset
    assert '"context": "kimi-review"' not in ruleset

# The exact clause MY-1402 introduced and MY-1404 re-plumbed. Kept as the head
# and tail of the expected text so a silent truncation cannot pass.
RULES_FIRST_LINE = "【证据纪律 —— Swift modifier 归属】"
RULES_LAST_LINE = (
    "  破坏、安全问题等有直接 diff 证据的 blocker,判定标准不变,照旧 fail-closed。"
)

# A body comfortably past the 512-byte pipe buffer that triggered the deadlock.
OVERSIZED_BODY = "x" * 4096


def _bash() -> str:
    """The bash the gates actually run under.

    Homebrew bash first: that is what the `aidash-mac` runner's PATH resolves
    and the only one that exhibits the deadlock. Falling back to whatever
    `bash` is on PATH keeps the suite runnable elsewhere.
    """
    for candidate in ("/opt/homebrew/bin/bash", "/usr/local/bin/bash"):
        if pathlib.Path(candidate).exists():
            return candidate
    found = shutil.which("bash")
    if found is None:                                   # pragma: no cover
        pytest.skip("no bash available")
    return found


def _run(script: str, timeout: int = 60) -> subprocess.CompletedProcess[str]:
    """Run `script` under the gate's bash with the workflow's `-e` flag.

    A hang here is the very defect under test, so the subprocess timeout is the
    assertion mechanism: `subprocess.TimeoutExpired` propagates and fails the
    test loudly rather than stalling the suite forever.
    """
    return subprocess.run(
        [_bash(), "-e", "-c", script],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=timeout,
        cwd=CI_DIR,
        check=False,
    )


# --------------------------------------------------------------------------
# 1. Structural rule: the construct itself is banned from the gate scripts.
# --------------------------------------------------------------------------

# `<<` opens a heredoc, `<<<` a here-string; both deadlock. `<<=` is the
# compound-assignment operator and is unrelated, so it is excluded rather than
# matched and then hand-waved away.
_REDIRECT_RE = re.compile(r"<<[<-]?(?!=)")


def _code_lines(path: pathlib.Path) -> list[tuple[int, str]]:
    """Lines with comment tails removed, so prose about `<<<` is not a hit.

    Crude but adequate: these are the gate scripts, and the MY-1404 comments
    necessarily *name* the banned operators while explaining them.
    """
    out: list[tuple[int, str]] = []
    for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        code = raw.split("#", 1)[0]
        if code.strip():
            out.append((number, code))
    return out


@pytest.mark.parametrize("path", GATE_SCRIPTS, ids=lambda p: p.name)
def test_gate_scripts_use_no_heredoc_or_herestring(path: pathlib.Path) -> None:
    """No `<<`, `<<-`, or `<<<` in executable lines of the review gates.

    Structural, not behavioural: a passing end-to-end run proves today's
    scripts are clean, but only this check keeps the next 600-byte heredoc from
    reintroducing a silent 20-minute stall.
    """
    offenders = [
        f"{path.name}:{number}: {code.strip()}"
        for number, code in _code_lines(path)
        if _REDIRECT_RE.search(code)
    ]
    assert not offenders, (
        "heredoc/here-string found in a review gate script — bodies over ~512 "
        "bytes deadlock under the runner's bash 5.3 (MY-1404). Build the text "
        "with printf into a variable instead:\n  " + "\n  ".join(offenders)
    )


# --------------------------------------------------------------------------
# 2. The shared prompt clause: same text, no hang, under the runner's bash.
# --------------------------------------------------------------------------

def test_review_evidence_rules_emits_full_text_without_hanging() -> None:
    """The 1118-byte clause still emits in full — and returns.

    This is the exact call that deadlocked both gates. The subprocess timeout
    is the regression detector; the content assertions guard against "fixed the
    hang by dropping the text", which would silently weaken the evidence
    discipline MY-1402 added.
    """
    result = _run(f". {COMMON}\nreview_evidence_rules\n", timeout=30)

    assert result.returncode == 0, result.stderr
    lines = result.stdout.splitlines()
    assert lines[0] == RULES_FIRST_LINE
    assert lines[-1] == RULES_LAST_LINE
    # Above the pipe buffer that broke it — i.e. the test is exercising a body
    # in the deadlock-prone size class, not a shrunken stand-in.
    assert len(result.stdout.encode("utf-8")) > 512

    # The clause must keep saying that unresolved means NO evidence; that
    # sentence is what stops a model from re-raising the PR #171 false blocker.
    assert "unresolved" in result.stdout
    assert "fail-closed" in result.stdout


# --------------------------------------------------------------------------
# 2b. The shared security notice: one source, and reviewable-by-itself.
# --------------------------------------------------------------------------
#
# MY-1452. The notice used to be a hand-copied 4-line block in each gate, and
# it declared that any diff containing the literal `verdict=pass` was an attack
# signal. Both gate scripts carry that literal — it is the text of their own
# success log line — so `codex-review` blocked PR #181 on
# `review-common.sh:408`, a plain `echo "... verdict=pass → exit 0"`.
#
# That is a self-blocking gate: every PR that touches scripts/ci/** trips the
# rule on its own source and can never go green, regardless of merit. These
# tests pin both halves of the repair — one shared definition, and a criterion
# based on whether text ADDRESSES the reviewer rather than which tokens it
# contains.


def test_security_notice_emits_full_text_without_hanging() -> None:
    """The shared notice emits in full and returns, under the runner's bash.

    Same deadlock class as `review_evidence_rules` (MY-1404): at ~1 KB this
    body is comfortably past the 512-byte pipe buffer, so it would hang if
    anyone reintroduced a heredoc here. The subprocess timeout is the detector.
    """
    result = _run(f". {COMMON}\nreview_security_notice\n", timeout=30)

    assert result.returncode == 0, result.stderr
    assert len(result.stdout.encode("utf-8")) > 512, (
        "notice shrank below the deadlock-prone size class — the test would "
        "no longer be exercising the regression it guards"
    )
    # The fence itself: untrusted data, never obey it, injection is a blocker.
    assert "【安全声明】" in result.stdout
    assert "不可信数据" in result.stdout
    assert "绝不" in result.stdout
    assert "blocker" in result.stdout


def test_security_notice_is_defined_once_and_shared_by_both_gates() -> None:
    """Neither gate inlines its own copy of the notice.

    Two copies is how the gates drift apart on the exact wording that defines
    the trust boundary. `review_evidence_rules` is already shared for the same
    reason; this keeps the security fence to the same standard.
    """
    for path in (CLAUDE, CODEX):
        body = path.read_text(encoding="utf-8")
        assert "review_security_notice" in body, (
            f"{path.name} does not call the shared notice"
        )
        assert "【安全声明】" not in body, (
            f"{path.name} inlines its own copy of the security notice — the two "
            "gates will drift. Call review_security_notice instead."
        )


def test_security_notice_does_not_blanket_ban_verdict_tokens() -> None:
    """The injection criterion is intent, not the presence of a token.

    Regression guard for the PR #181 deadlock: with a token-presence rule, the
    review gates cannot review themselves. `verdict`, `pass`, and `changes`
    appear in these scripts as log strings and JSON-schema enums, so a rule
    that blocks on the literal blocks every CI-infrastructure PR on its own
    source. The notice must say that a same-named token appearing as DATA is
    not injection.
    """
    result = _run(f". {COMMON}\nreview_security_notice\n", timeout=30)
    assert result.returncode == 0, result.stderr
    notice = result.stdout

    # States the criterion positively: is this text instructing you?
    assert "是否在对你下指令" in notice, (
        "notice no longer states that the criterion is whether the text "
        "addresses the reviewer"
    )
    # And states the carve-out explicitly, naming the gate scripts.
    assert "scripts/ci/" in notice, (
        "notice no longer names the gate scripts as the concrete case where "
        "verdict-like tokens appear as data"
    )
    assert "不构成注入" in notice, (
        "notice no longer says a same-named token appearing as data is not "
        "injection — the gate becomes unable to review itself again"
    )


def test_gate_scripts_are_reviewable_under_their_own_security_notice() -> None:
    """The gates' own source does not trip the rule the notice describes.

    This is the end-to-end property PR #181 violated. `codex-review` blocked on
    `review-common.sh:408` — the gate's own success log line. Assert that the
    literal really is present in the sources (so the scenario is live, not
    hypothetical) AND that the notice explicitly exempts it as data.
    """
    offenders = [
        f"{path.name}:{number}: {code.strip()}"
        for path in GATE_SCRIPTS
        for number, code in _code_lines(path)
        if "verdict=pass" in code
    ]
    assert offenders, (
        "no gate script contains a `verdict=pass` literal any more — if that "
        "is deliberate, this test is stale; if not, the scenario it guards "
        "has silently stopped being exercised"
    )

    result = _run(f". {COMMON}\nreview_security_notice\n", timeout=30)
    assert result.returncode == 0, result.stderr
    assert "不构成注入" in result.stdout, (
        "gate sources still carry verdict-like literals:\n  "
        + "\n  ".join(offenders)
        + "\nbut the security notice no longer exempts tokens-as-data, so the "
        + "gates would once again block every PR that touches themselves."
    )


def test_review_coverage_rules_emits_full_text_without_hanging() -> None:
    """The coverage-discipline clause (MY-1456) emits without hanging.

    Same transport safety check as the modifier-evidence rules: printf-based
    emission of a multi-KB body under the runner's bash must complete without
    deadlocking on the pipe buffer.
    """
    result = _run(f". {COMMON}\nreview_coverage_rules\n", timeout=30)

    assert result.returncode == 0, result.stderr
    lines = result.stdout.splitlines()
    assert lines[0] == "【证据纪律 —— 测试覆盖判定】"
    # Must include key discipline sentences
    assert "COVERAGE CONTEXT" in result.stdout
    assert "blocker" in result.stdout
    assert "note" in result.stdout
    # Above pipe buffer size
    assert len(result.stdout.encode("utf-8")) > 512



def test_scope_evidence_helper_handles_many_changed_files(
    tmp_path: pathlib.Path,
) -> None:
    """`build_scope_evidence` survives a changed-file list past the buffer.

    Its loop used to read `<<<"$changed"`. The list is PR-controlled in length,
    so a PR touching enough nested Swift paths would have crossed 512 bytes and
    hung the gate — the same deadlock, reached by a different door.

    `git` is stubbed to fail every blob read, so each file resolves to "no
    evidence" — the analyzer's normal empty-output success. What is under test
    is that the loop TERMINATES, with no network and no repository needed.
    """
    paths = [
        f"Packages/AIDashUI/Sources/AIDashUI/CardView/Generated{n:04d}.swift"
        for n in range(100)
    ]
    assert sum(len(path.encode("utf-8")) for path in paths) > 512

    changed_file = tmp_path / "changed_paths.bin"
    changed_file.write_bytes(b"\0".join(path.encode("utf-8") for path in paths) + b"\0")

    stub_dir = tmp_path / "bin"
    stub_dir.mkdir()
    (stub_dir / "git").write_text("#!/bin/sh\nexit 1\n", encoding="utf-8")
    (stub_dir / "git").chmod(0o755)

    empty_diff = tmp_path / "empty.patch"
    empty_diff.write_text("", encoding="utf-8")

    script = (
        f". {COMMON}\n"
        f'REPO_ROOT="{CI_DIR.parent.parent}"\n'
        f'export PATH="{stub_dir}:$PATH"\n'
        f'CHANGED_FILE="{changed_file}"\n'
        "rc=0\n"
        "build_scope_evidence 0000000000000000000000000000000000000000 "
        f'"{empty_diff}" "$CHANGED_FILE" >/dev/null || rc=$?\n'
        'echo "completed rc=$rc"\n'
    )
    result = _run(script, timeout=60)

    assert "completed rc=0" in result.stdout, result.stderr


# --------------------------------------------------------------------------
# 3. The watchdog.
# --------------------------------------------------------------------------

def test_run_with_timeout_passes_through_success() -> None:
    """A fast command's own exit status survives the wrapper."""
    result = _run(
        f". {COMMON}\n"
        "run_with_timeout 30 /bin/sh -c 'printf ran; exit 0' || rc=$?\n"
        'echo "|rc=${rc:-0}"\n',
        timeout=45,
    )
    assert result.returncode == 0, result.stderr
    assert "ran|rc=0" in result.stdout


def test_run_with_timeout_passes_through_failure() -> None:
    """A real CLI failure is reported as itself, not masked as a timeout.

    The two must stay distinguishable: they produce different sticky comments,
    and conflating them would make a broken CLI look like a slow one.
    """
    result = _run(
        f". {COMMON}\n"
        "rc=0\n"
        "run_with_timeout 30 /bin/sh -c 'exit 3' || rc=$?\n"
        'echo "rc=$rc"\n',
        timeout=45,
    )
    assert result.returncode == 0, result.stderr
    assert "rc=3" in result.stdout


def test_run_with_timeout_reports_timeout_rc() -> None:
    """A command that outlives its budget comes back as 124, promptly."""
    result = _run(
        f". {COMMON}\n"
        "rc=0\n"
        "run_with_timeout 2 /bin/sh -c 'sleep 120' || rc=$?\n"
        'echo "rc=$rc expected=$REVIEW_TIMEOUT_RC"\n',
        timeout=60,
    )
    assert result.returncode == 0, result.stderr
    assert "rc=124 expected=124" in result.stdout


def test_run_with_timeout_kills_the_whole_process_group(
    tmp_path: pathlib.Path,
) -> None:
    """Grandchildren die with the CLI, not after it.

    The reviewer CLIs spawn helpers. Killing only the direct child left those
    running on the maintainer's own machine — the runner logged them as
    "Terminate orphan process" on every cancelled attempt.

    The grandchild records its own pid rather than being matched by name:
    a `pgrep -f <marker>` would also match the outer test script, whose argv
    necessarily contains that marker, and so would report a leak every run.
    """
    pidfile = tmp_path / "grandchild.pid"
    inner = tmp_path / "inner.sh"
    inner.write_text(
        f'#!/bin/sh\nsh -c \'echo $$ > "{pidfile}"; exec sleep 120\' &\nwait\n',
        encoding="utf-8",
    )
    inner.chmod(0o755)

    result = _run(
        f". {COMMON}\n"
        "rc=0\n"
        f"run_with_timeout 2 {inner} || rc=$?\n"
        "sleep 3\n"
        f'GRANDCHILD="$(cat "{pidfile}" 2>/dev/null)"\n'
        'if [ -z "$GRANDCHILD" ]; then echo NO-PID; \n'
        'elif kill -0 "$GRANDCHILD" 2>/dev/null; then echo LEAKED; \n'
        "else echo CLEAN; fi\n",
        timeout=90,
    )

    assert "NO-PID" not in result.stdout, "grandchild never started; test is vacuous"
    assert "CLEAN" in result.stdout, (
        f"orphaned grandchild survived the timeout: {result.stdout}"
    )


def test_run_with_timeout_cleans_up_descendants_after_leader_exits_zero(
    tmp_path: pathlib.Path,
) -> None:
    """Leader exits 0 while descendants linger: cleanup is bounded and fast."""
    pidfile = tmp_path / "grandchild.pid"
    inner = tmp_path / "inner.sh"
    inner.write_text(
        f'#!/bin/sh\n'
        'sh -c \'echo $$ > "'
        f"{pidfile}"
        '"; exec sleep 120\' &\n'
        'exit 0\n',
        encoding="utf-8",
    )
    inner.chmod(0o755)

    result = _run(
        f". {COMMON}\n"
        "rc=0\n"
        f"run_with_timeout 2 {inner} || rc=$?\n"
        'echo "rc=$rc"\n'
        f'GRANDCHILD="$(cat "{pidfile}" 2>/dev/null)"\n'
        'if [ -n "$GRANDCHILD" ] && kill -0 "$GRANDCHILD" 2>/dev/null; then echo LEAKED; else echo CLEAN; fi\n',
        timeout=30,
    )

    assert result.returncode == 0, result.stderr
    assert "rc=0" in result.stdout, result.stdout
    assert "CLEAN" in result.stdout, result.stdout


def test_run_with_timeout_prefers_watchdog_when_term_trap_exits_zero(
    tmp_path: pathlib.Path,
) -> None:
    """The watchdog wins even when the leader traps TERM and exits 0."""
    pidfile = tmp_path / "grandchild.pid"
    inner = tmp_path / "inner.sh"
    inner.write_text(
        f'#!/bin/sh\n'
        'sh -c \'trap "" TERM; echo $$ > "'
        f"{pidfile}"
        '"; exec sleep 120\' &\n'
        'trap "exit 0" TERM\n'
        'sleep 120\n',
        encoding="utf-8",
    )
    inner.chmod(0o755)

    result = _run(
        f". {COMMON}\n"
        "rc=0\n"
        f"run_with_timeout 2 {inner} || rc=$?\n"
        'echo "rc=$rc"\n'
        f'GRANDCHILD="$(cat "{pidfile}" 2>/dev/null)"\n'
        'if [ -n "$GRANDCHILD" ] && kill -0 "$GRANDCHILD" 2>/dev/null; then echo LEAKED; else echo CLEAN; fi\n',
        timeout=90,
    )

    assert result.returncode == 0, result.stderr
    assert "rc=124" in result.stdout, result.stdout
    assert "CLEAN" in result.stdout, result.stdout


def test_emit_failure_metadata_rejects_untrusted_payloads() -> None:
    """Only allowlisted fields survive in stderr diagnostics."""
    result = _run(
        f". {COMMON}\n"
        'emit_failure_metadata "timeout" 124 "timeout" "bad$(printf HACK)" "1234567890123" 8 9 1>&2\n'
        'echo "done"\n',
        timeout=30,
    )

    assert result.returncode == 0, result.stderr
    assert "bad$(printf" not in result.stderr
    assert "HACK" not in result.stderr
    assert "terminal_reason=timeout" in result.stderr
    assert "subtype=n/a" in result.stderr
    assert "num_turns=n/a" in result.stderr


def test_run_with_timeout_does_not_abort_caller_under_errexit() -> None:
    """A timeout must not kill the script before it can explain itself.

    The workflow runs these gates as `bash -e {0}`. A bare `wait` on a
    signalled child exits the whole script with 143, skipping the branch that
    posts the sticky comment: the check goes red with an empty log, which is
    the MY-1404 symptom rather than a fix for it.
    """
    result = _run(
        f". {COMMON}\n"
        "rc=0\n"
        "run_with_timeout 2 /bin/sh -c 'sleep 120' || rc=$?\n"
        'echo "still-running-after-timeout rc=$rc"\n',
        timeout=60,
    )
    assert result.returncode == 0, (
        "caller aborted on the timeout instead of continuing: " + result.stderr
    )
    assert "still-running-after-timeout rc=124" in result.stdout


# --------------------------------------------------------------------------
# 4. The property that must never regress: a hang still blocks the merge.
# --------------------------------------------------------------------------

@pytest.mark.parametrize(
    ("script", "cli_name", "stub"),
    [
        (CLAUDE, "claude", "#!/bin/sh\nsleep 120\n"),
        (CODEX, "codex", "#!/bin/sh\nsleep 120\n"),
    ],
    ids=["claude", "codex"],
)
def test_timed_out_gate_fails_closed(
    tmp_path: pathlib.Path,
    script: pathlib.Path,
    cli_name: str,
    stub: str,
) -> None:
    """A CLI that never returns → exit 1 with a timeout diagnostic.

    Fail-closed is the whole point of the gate; making it tolerant of hangs
    must not make it tolerant of unreviewed diffs.

    `gh` and `git` are both stubbed, so the test posts no comment and opens no
    network connection. The `git` stub answers only the handful of read-only
    queries the gate makes before the CLI call, and reports a one-file Swift
    diff so the run reaches the CLI rather than short-circuiting on "empty
    diff → pass" — which would make this assertion vacuous.
    """
    stub_dir = tmp_path / "bin"
    stub_dir.mkdir()

    (stub_dir / cli_name).write_text(stub, encoding="utf-8")
    # Swallow every comment/API call: the gate must not post during tests.
    (stub_dir / "gh").write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
    (stub_dir / "git").write_text(
        "#!/bin/sh\n"
        "case \"$1\" in\n"
        f'  rev-parse) printf "%s\\n" "{CI_DIR.parent.parent}" ;;\n'
        "  fetch|cat-file) exit 0 ;;\n"
        "  diff)\n"
        '    case "$*" in\n'
        '      *--name-only*) printf "%s\\n" "Sources/Only.swift" ;;\n'
        '      *) printf "%s\\n" "diff --git a/Sources/Only.swift b/Sources/Only.swift" ;;\n'
        "    esac ;;\n"
        "  show) exit 1 ;;\n"
        "  *) exit 0 ;;\n"
        "esac\n",
        encoding="utf-8",
    )
    for name in (cli_name, "gh", "git"):
        (stub_dir / name).chmod(0o755)

    env_prefix = (
        f'export PATH="{stub_dir}:$PATH"\n'
        "export REVIEW_CLI_TIMEOUT_SECONDS=2\n"
        "export PR_NUMBER=1 BASE_REPO=LeePepe/AIDash GH_TOKEN=stub\n"
        "export BASE_SHA=HEAD HEAD_SHA=HEAD\n"
        f'export CODEX_BIN="{stub_dir}/codex"\n'
        "rc=0\n"
        f"{script} || rc=$?\n"
        'echo "gate-rc=$rc"\n'
    )
    result = _run(env_prefix, timeout=120)

    assert "gate-rc=0" not in result.stdout, (
        "gate passed despite the reviewer CLI never returning — fail-closed "
        "was lost:\n" + result.stdout
    )


def test_oversized_printf_body_round_trips() -> None:
    """The replacement transport is itself safe well past the buffer.

    Guards the fix rather than the bug: `printf` into a redirect must handle a
    body several times the pipe buffer that broke the heredoc.
    """
    result = _run(
        f'BODY="{OVERSIZED_BODY}"\n'
        'OUT="$(mktemp)"\n'
        'printf %s "$BODY" > "$OUT"\n'
        'echo "bytes=$(wc -c <"$OUT" | tr -d " ")"\n',
        timeout=30,
    )
    assert result.returncode == 0, result.stderr
    assert f"bytes={len(OVERSIZED_BODY)}" in result.stdout


# --------------------------------------------------------------------------
# 5. MY-1452: the claude CLI must be turn-bounded and phase-timed.
# --------------------------------------------------------------------------

def test_claude_review_passes_max_turns_and_disables_tools() -> None:
    """The shared gate function includes --max-turns 2 AND --tools "".

    --max-turns 2 (not 1): with --json-schema the CLI needs turn 1 (model
    response) + turn 2 (structured output extraction). --max-turns 1 causes
    exit with error_max_turns before producing structured_output. Runner probe
    confirmed --max-turns 2 returns schema-valid verdict in ~7s.

    --tools "" disables all built-in tools (Read, Edit, Bash, etc.) per
    `claude --help`, preventing any tool call from exhausting the 900s
    watchdog (MY-1452).

    This is a behavioural check restricted to executable lines (comments
    stripped): removing the real CLI flags while leaving them in comments must
    fail the test.
    """
    # The flags are in review-common.sh's run_claude_review_gate function.
    executable_lines = _code_lines(COMMON)
    executable_text = "\n".join(code for _, code in executable_lines)

    assert "--max-turns 2" in executable_text, (
        "review-common.sh run_claude_review_gate must pass --max-turns 2 to "
        "`claude -p` to bound agentic turns (MY-1452)"
    )
    assert '--tools ""' in executable_text, (
        'review-common.sh run_claude_review_gate must pass --tools "" to '
        "`claude -p` to deterministically disable all built-in tools (MY-1452)"
    )


def test_claude_review_emits_phase_timing() -> None:
    """Phase timing helpers are defined and invoked for the three phases.

    MY-1452 requires actionable phase-specific evidence: when a future timeout
    occurs, the log must say WHERE it stalled (diff / scope-evidence /
    claude-cli), not just that 900 seconds elapsed.

    This check uses _code_lines (comments stripped) so that commenting out a
    _phase_start/_phase_end call while keeping a comment mentioning it will
    correctly fail the test. Phase calls may be in claude-review.sh or
    review-common.sh (the shared function).
    """
    claude_exec = "\n".join(code for _, code in _code_lines(CLAUDE))
    common_exec = "\n".join(code for _, code in _code_lines(COMMON))
    combined = claude_exec + "\n" + common_exec

    for phase in ("diff", "scope-evidence", "claude-cli"):
        assert f'_phase_start "{phase}"' in combined, (
            f"Missing _phase_start for phase {phase!r} in executable code (MY-1452)"
        )
        assert f'_phase_end "{phase}"' in combined, (
            f"Missing _phase_end for phase {phase!r} in executable code (MY-1452)"
        )


def test_claude_review_structured_output_path() -> None:
    """The structured_output extraction path in the shared function.

    Contract: the production function must include --output-format json,
    --json-schema, .structured_output extraction, and .result fallback.
    Removing any of these from the real function breaks the test.
    """
    executable_lines = _code_lines(COMMON)
    executable_text = "\n".join(code for _, code in executable_lines)

    assert "--output-format json" in executable_text, (
        "review-common.sh must pass --output-format json to get "
        "structured_output in the response envelope (MY-1452)"
    )
    assert "--json-schema" in executable_text, (
        "review-common.sh must pass --json-schema to enforce the verdict "
        "schema on the CLI response (MY-1452)"
    )
    assert ".structured_output" in executable_text, (
        "review-common.sh must extract .structured_output from the CLI "
        "response for the verdict envelope (MY-1452)"
    )

# --------------------------------------------------------------------------
# 5. Nonce-based untrusted-data fence (MY-1456 security fix).
# --------------------------------------------------------------------------


def test_gate_scripts_use_nonce_fence_not_static_delimiters() -> None:
    """Both review gate scripts must use nonce-based FENCE_OPEN/FENCE_CLOSE
    variables instead of hardcoded static untrusted-data markers.

    A static delimiter allows PR-controlled content (test source embedded via
    COVERAGE_CONTEXT) to inject the exact closing marker and escape the
    untrusted region. The nonce makes the boundary unpredictable.
    """
    executable_lines = _code_lines(COMMON)
    executable_text = "\n".join(code for _, code in executable_lines)

    for script_name in ("claude-review.sh", "codex-review.sh"):
        path = CI_DIR / script_name
        content = path.read_text(encoding="utf-8")

        # Must contain nonce generation and variable usage
        assert "FENCE_NONCE" in content, (
            f"{script_name} missing FENCE_NONCE generation"
        )
        assert "FENCE_OPEN" in content, (
            f"{script_name} missing FENCE_OPEN variable"
        )
        assert "FENCE_CLOSE" in content, (
            f"{script_name} missing FENCE_CLOSE variable"
        )
        assert "/dev/urandom" in content, (
            f"{script_name} must use /dev/urandom for nonce generation"
        )

        # The prompt must reference $FENCE_OPEN and $FENCE_CLOSE, not
        # hardcoded static delimiters. Check that the prompt area uses the
        # variable (the prompt is in a string assigned to PROMPT="...")
        assert "$FENCE_OPEN" in content, (
            f"{script_name} prompt must use $FENCE_OPEN variable"
        )
        assert "$FENCE_CLOSE" in content, (
            f"{script_name} prompt must use $FENCE_CLOSE variable"
        )
    assert ".result" in executable_text, (
        "review-common.sh must have a .result fallback path for verdict "
        "extraction (MY-1452)"
    )


def test_claude_review_error_max_turns_diagnostic() -> None:
    """The shared function extracts structured diagnostic on error_max_turns.

    MY-1452 requirement: non-zero CLI exit must surface terminal_reason,
    subtype, and num_turns from the JSON output so operators can distinguish
    error_max_turns from genuine crashes without leaking sensitive content.
    """
    executable_lines = _code_lines(COMMON)
    executable_text = "\n".join(code for _, code in executable_lines)

    assert "terminal_reason" in executable_text, (
        "review-common.sh must extract terminal_reason from CLI JSON on "
        "non-zero exit for actionable diagnostics (MY-1452)"
    )
    assert "num_turns" in executable_text, (
        "review-common.sh must extract num_turns from CLI JSON on non-zero "
        "exit (MY-1452)"
    )


def test_timeout_kills_nested_env_bash_wrapper(tmp_path: pathlib.Path) -> None:
    """The `env VAR=... bash -c '...'` wrapper used by claude-review is killed.

    The claude gate wraps the CLI call in `env CLAUDE_REVIEW_PROMPT=... bash -c
    '...'`, which creates an extra shell layer between `run_with_timeout` and
    the actual CLI. This test verifies that the watchdog's process-group kill
    reaches through the env→bash→child chain, and that the wrapper's stderr
    redirect (`2>/tmp/...`) does not keep the write end of a pipe open past the
    kill (the pipe-dangle that MY-1404 identified as a hang risk).
    """
    inner = tmp_path / "fake-claude"
    pidfile = tmp_path / "claude.pid"
    inner.write_text(f"#!/bin/sh\necho $$ >\"{pidfile}\"; exec sleep 120\n",
                     encoding="utf-8")
    inner.chmod(0o755)

    result = _run(
        f". {COMMON}\n"
        "rc=0\n"
        f'run_with_timeout 2 env FOO=bar bash -c \'{inner} "$@"\' _ arg1 '
        "2>/dev/null || rc=$?\n"
        "sleep 3\n"
        f'PID="$(cat "{pidfile}" 2>/dev/null)"\n'
        'if [ -z "$PID" ]; then echo NO-PID\n'
        'elif kill -0 "$PID" 2>/dev/null; then echo LEAKED\n'
        "else echo CLEAN; fi\n"
        'echo "rc=$rc"\n',
        timeout=90,
    )

    assert "NO-PID" not in result.stdout, "inner process never started; test is vacuous"
    assert "CLEAN" in result.stdout, (
        f"orphaned process survived the nested env→bash→child kill: {result.stdout}"
    )
    assert "rc=124" in result.stdout


# --------------------------------------------------------------------------
# 6. MY-1452: End-to-end gate contract — calls the REAL production function.
#
# These tests call `run_claude_review_gate` from review-common.sh with a fake
# `claude` binary on PATH. The function is the SAME code path that
# claude-review.sh uses — there is no copied logic that can drift. Mutating
# the real extractor, flag plumbing, diagnostic, or threshold in
# review-common.sh will break these tests.
# --------------------------------------------------------------------------

# The full production schema from claude-review.sh (must match exactly).
_PRODUCTION_SCHEMA = (
    '{"type":"object","additionalProperties":false,'
    '"required":["verdict","summary","blockers","notes"],'
    '"properties":{'
    '"verdict":{"type":"string","enum":["pass","changes"]},'
    '"summary":{"type":"string"},'
    '"blockers":{"type":"array","items":{"type":"object","additionalProperties":false,'
    '"required":["file","severity","why"],'
    '"properties":{"file":{"type":"string"},"line":{"type":["integer","null"]},'
    '"severity":{"type":"string","enum":["critical","high"]},"why":{"type":"string"}}}},'
    '"notes":{"type":"array","items":{"type":"object","additionalProperties":false,'
    '"required":["file","note"],'
    '"properties":{"file":{"type":"string"},"line":{"type":["integer","null"]},"note":{"type":"string"}}}}'
    '}}'
)


def _make_fake_claude(
    tmp_path: pathlib.Path, output: str, exit_code: int = 0
) -> pathlib.Path:
    """Create a fake claude binary that logs argv and outputs controlled JSON."""
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir(exist_ok=True)
    argv_file = tmp_path / "claude_argv.txt"
    fake = bin_dir / "claude"
    # The fake reads stdin (to consume the pipe) and writes output to stdout.
    fake.write_text(
        f'#!/bin/sh\n'
        f'cat > /dev/null\n'  # consume stdin to prevent SIGPIPE
        f'printf "%s\\n" "$@" > "{argv_file}"\n'
        f'printf "%s" \'{output}\'\n'
        f'exit {exit_code}\n',
        encoding="utf-8",
    )
    fake.chmod(0o755)
    return bin_dir


def _run_real_gate(
    tmp_path: pathlib.Path, bin_dir: pathlib.Path, schema: str = _PRODUCTION_SCHEMA
) -> subprocess.CompletedProcess[str]:
    """Call the REAL run_claude_review_gate function with fake claude on PATH.

    This sources review-common.sh and calls the production function directly.
    No copied logic — any drift in the real function is caught here.
    """
    raw_file = tmp_path / "raw.json"
    err_file = tmp_path / "err.log"
    sticky_log = tmp_path / "sticky.log"

    # Script that sources the real production helper and calls the real function.
    script = (
        f'. "{COMMON}"\n'
        f'STICKY="<!-- test-marker -->"\n'
        f'post_sticky() {{ printf "%s\\n" "$1" >> "{sticky_log}"; }}\n'
        f'PROMPT="test review prompt content"\n'
        f'run_claude_review_gate \'{schema}\' "{raw_file}" "{err_file}"\n'
    )

    import os
    env = {**os.environ, "PATH": f"{bin_dir}:{os.environ['PATH']}"}

    return subprocess.run(
        [_bash(), "-c", script],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=60,
        cwd=CI_DIR,
        check=False,
        env=env,
    )


class TestRealGateContract:
    """End-to-end contract: calls the REAL run_claude_review_gate function."""

    def test_argv_flag_value_adjacency(self, tmp_path: pathlib.Path) -> None:
        """Real gate passes correct flag/value pairs to the claude binary.

        Verifies flag-value adjacency: --tools followed by "", --max-turns
        followed by 2, --output-format followed by json, and --json-schema
        followed by the full production schema.
        """
        valid_output = (
            '{"structured_output":{"verdict":"pass","summary":"ok",'
            '"blockers":[],"notes":[]}}'
        )
        bin_dir = _make_fake_claude(tmp_path, valid_output, exit_code=0)
        result = _run_real_gate(tmp_path, bin_dir)

        assert result.returncode == 0, f"gate failed: {result.stdout}\n{result.stderr}"

        argv_file = tmp_path / "claude_argv.txt"
        argv_lines = argv_file.read_text(encoding="utf-8").strip().splitlines()

        # Flag-value adjacency checks
        assert "-p" in argv_lines, f"missing -p: {argv_lines}"

        of_idx = argv_lines.index("--output-format")
        assert argv_lines[of_idx + 1] == "json", (
            f"--output-format not followed by json: {argv_lines[of_idx:of_idx+2]}"
        )

        mt_idx = argv_lines.index("--max-turns")
        assert argv_lines[mt_idx + 1] == "2", (
            f"--max-turns not followed by 2: {argv_lines[mt_idx:mt_idx+2]}"
        )

        tools_idx = argv_lines.index("--tools")
        assert argv_lines[tools_idx + 1] == "", (
            f"--tools not followed by empty string: {argv_lines[tools_idx:tools_idx+2]!r}"
        )

        schema_idx = argv_lines.index("--json-schema")
        schema_val = argv_lines[schema_idx + 1]
        # Verify it's the full production schema by checking key fields
        import json as _json
        parsed_schema = _json.loads(schema_val)
        assert parsed_schema["required"] == ["verdict", "summary", "blockers", "notes"]
        assert "severity" in str(parsed_schema["properties"]["blockers"])

    def test_structured_output_pass(self, tmp_path: pathlib.Path) -> None:
        """Gate exits 0 and renders pass comment for .structured_output envelope."""
        valid_output = (
            '{"structured_output":{"verdict":"pass","summary":"all clear",'
            '"blockers":[],"notes":[{"file":"a.swift","line":1,"note":"nit"}]}}'
        )
        bin_dir = _make_fake_claude(tmp_path, valid_output, exit_code=0)
        result = _run_real_gate(tmp_path, bin_dir)

        assert result.returncode == 0, f"unexpected failure: {result.stdout}"
        assert "verdict=pass" in result.stdout
        # Verify rendering happened via sticky
        sticky = (tmp_path / "sticky.log").read_text(encoding="utf-8")
        assert "✅ 自动 review:通过" in sticky
        assert "all clear" in sticky
        assert "nit" in sticky  # note rendered

    def test_structured_output_changes_with_blockers_exits_1(
        self, tmp_path: pathlib.Path
    ) -> None:
        """verdict=changes + blockers enforces critical/high threshold → exit 1."""
        output = (
            '{"structured_output":{"verdict":"changes","summary":"issues",'
            '"blockers":[{"file":"x.swift","severity":"critical","line":10,"why":"bug"}],'
            '"notes":[]}}'
        )
        bin_dir = _make_fake_claude(tmp_path, output, exit_code=0)
        result = _run_real_gate(tmp_path, bin_dir)

        assert result.returncode == 1, "gate must exit 1 on changes+blockers"
        assert "verdict=changes" in result.stdout
        assert "blockers=1" in result.stdout
        sticky = (tmp_path / "sticky.log").read_text(encoding="utf-8")
        assert "🔴 自动 review:需要修改" in sticky
        assert "bug" in sticky

    def test_result_fallback_path(self, tmp_path: pathlib.Path) -> None:
        """Gate extracts verdict from .result when .structured_output is absent."""
        import json as _json
        inner = {"verdict": "pass", "summary": "ok via fallback", "blockers": [], "notes": []}
        fallback_output = _json.dumps({"result": _json.dumps(inner)})
        bin_dir = _make_fake_claude(tmp_path, fallback_output, exit_code=0)
        result = _run_real_gate(tmp_path, bin_dir)

        assert result.returncode == 0, f"fallback failed: {result.stdout}"
        assert "verdict=pass" in result.stdout
        sticky = (tmp_path / "sticky.log").read_text(encoding="utf-8")
        assert "ok via fallback" in sticky

    def test_error_max_turns_diagnostic(self, tmp_path: pathlib.Path) -> None:
        """Non-zero + terminal_reason → structured, actionable diagnostic."""
        error_output = (
            '{"terminal_reason":"max_turns","subtype":"error_max_turns",'
            '"num_turns":2}'
        )
        bin_dir = _make_fake_claude(tmp_path, error_output, exit_code=1)
        result = _run_real_gate(tmp_path, bin_dir)

        assert result.returncode == 1
        assert "terminal_reason=max_turns" in result.stdout
        assert "subtype=error_max_turns" in result.stdout
        assert "num_turns=2" in result.stdout
        sticky = (tmp_path / "sticky.log").read_text(encoding="utf-8")
        assert "暂不放行" in sticky

    def test_malformed_nonzero_failclosed(self, tmp_path: pathlib.Path) -> None:
        """Non-zero + non-JSON → fail-closed with generic diagnostic + sticky."""
        bin_dir = _make_fake_claude(tmp_path, "not json at all", exit_code=1)
        result = _run_real_gate(tmp_path, bin_dir)

        assert result.returncode == 1
        assert "rc=1" in result.stdout
        # No structured diagnostic extracted
        assert "terminal_reason=" not in result.stdout
        sticky = (tmp_path / "sticky.log").read_text(encoding="utf-8")
        assert "暂不放行" in sticky

    def test_empty_output_failclosed(self, tmp_path: pathlib.Path) -> None:
        """CLI exits 0 but empty output → fail-closed with explicit diagnostic."""
        bin_dir = _make_fake_claude(tmp_path, "", exit_code=0)
        result = _run_real_gate(tmp_path, bin_dir)

        assert result.returncode == 1
        assert "rc=0" in result.stdout
        sticky = (tmp_path / "sticky.log").read_text(encoding="utf-8")
        assert "暂不放行" in sticky

    def test_no_sensitive_leak_on_failure(self, tmp_path: pathlib.Path) -> None:
        """Diagnostic output does not leak prompt content."""
        error_output = (
            '{"terminal_reason":"max_turns","subtype":"error_max_turns",'
            '"num_turns":1}'
        )
        bin_dir = _make_fake_claude(tmp_path, error_output, exit_code=1)
        result = _run_real_gate(tmp_path, bin_dir)

        combined = result.stdout + result.stderr
        assert "test review prompt content" not in combined, (
            "prompt content leaked in diagnostic output"
        )

    def test_unparseable_verdict_failclosed(self, tmp_path: pathlib.Path) -> None:
        """CLI exits 0 with JSON but no .structured_output/.result → fail-closed."""
        # Valid JSON but missing verdict envelope
        bin_dir = _make_fake_claude(tmp_path, '{"foo":"bar"}', exit_code=0)
        result = _run_real_gate(tmp_path, bin_dir)

        assert result.returncode == 1
        assert "无法解析 verdict" in result.stdout
        sticky = (tmp_path / "sticky.log").read_text(encoding="utf-8")
        assert "暂不放行" in sticky

    # ------------------------------------------------------------------
    # Negative schema validation: malformed envelopes must fail-closed.
    # ------------------------------------------------------------------

    def test_unknown_verdict_value_structured_output(
        self, tmp_path: pathlib.Path
    ) -> None:
        """Unknown verdict value in .structured_output → fail-closed."""
        output = (
            '{"structured_output":{"verdict":"bogus","summary":"x",'
            '"blockers":[],"notes":[]}}'
        )
        bin_dir = _make_fake_claude(tmp_path, output, exit_code=0)
        result = _run_real_gate(tmp_path, bin_dir)

        assert result.returncode == 1
        assert "schema" in result.stdout.lower() or "校验" in result.stdout
        sticky = (tmp_path / "sticky.log").read_text(encoding="utf-8")
        assert "暂不放行" in sticky

    def test_missing_verdict_field_structured_output(
        self, tmp_path: pathlib.Path
    ) -> None:
        """Missing verdict field in .structured_output → fail-closed."""
        output = (
            '{"structured_output":{"summary":"x","blockers":[],"notes":[]}}'
        )
        bin_dir = _make_fake_claude(tmp_path, output, exit_code=0)
        result = _run_real_gate(tmp_path, bin_dir)

        assert result.returncode == 1
        sticky = (tmp_path / "sticky.log").read_text(encoding="utf-8")
        assert "暂不放行" in sticky

    def test_missing_blockers_structured_output(
        self, tmp_path: pathlib.Path
    ) -> None:
        """Missing blockers array in .structured_output → fail-closed."""
        output = (
            '{"structured_output":{"verdict":"pass","summary":"x","notes":[]}}'
        )
        bin_dir = _make_fake_claude(tmp_path, output, exit_code=0)
        result = _run_real_gate(tmp_path, bin_dir)

        assert result.returncode == 1
        sticky = (tmp_path / "sticky.log").read_text(encoding="utf-8")
        assert "暂不放行" in sticky

    def test_non_array_blockers_structured_output(
        self, tmp_path: pathlib.Path
    ) -> None:
        """Non-array blockers in .structured_output → fail-closed."""
        output = (
            '{"structured_output":{"verdict":"changes","summary":"x",'
            '"blockers":"not-array","notes":[]}}'
        )
        bin_dir = _make_fake_claude(tmp_path, output, exit_code=0)
        result = _run_real_gate(tmp_path, bin_dir)

        assert result.returncode == 1
        sticky = (tmp_path / "sticky.log").read_text(encoding="utf-8")
        assert "暂不放行" in sticky

    def test_missing_notes_structured_output(
        self, tmp_path: pathlib.Path
    ) -> None:
        """Missing notes array in .structured_output → fail-closed."""
        output = (
            '{"structured_output":{"verdict":"pass","summary":"x","blockers":[]}}'
        )
        bin_dir = _make_fake_claude(tmp_path, output, exit_code=0)
        result = _run_real_gate(tmp_path, bin_dir)

        assert result.returncode == 1
        sticky = (tmp_path / "sticky.log").read_text(encoding="utf-8")
        assert "暂不放行" in sticky

    def test_malformed_blocker_severity_structured_output(
        self, tmp_path: pathlib.Path
    ) -> None:
        """Blocker with invalid severity in .structured_output → fail-closed."""
        output = (
            '{"structured_output":{"verdict":"changes","summary":"x",'
            '"blockers":[{"file":"a.swift","severity":"low","why":"bad"}],'
            '"notes":[]}}'
        )
        bin_dir = _make_fake_claude(tmp_path, output, exit_code=0)
        result = _run_real_gate(tmp_path, bin_dir)

        assert result.returncode == 1
        sticky = (tmp_path / "sticky.log").read_text(encoding="utf-8")
        assert "暂不放行" in sticky

    def test_malformed_blocker_missing_fields_structured_output(
        self, tmp_path: pathlib.Path
    ) -> None:
        """Blocker missing required fields in .structured_output → fail-closed."""
        output = (
            '{"structured_output":{"verdict":"changes","summary":"x",'
            '"blockers":[{"file":"a.swift"}],"notes":[]}}'
        )
        bin_dir = _make_fake_claude(tmp_path, output, exit_code=0)
        result = _run_real_gate(tmp_path, bin_dir)

        assert result.returncode == 1
        sticky = (tmp_path / "sticky.log").read_text(encoding="utf-8")
        assert "暂不放行" in sticky

    def test_unknown_verdict_value_result_fallback(
        self, tmp_path: pathlib.Path
    ) -> None:
        """Unknown verdict value via .result fallback → fail-closed."""
        import json as _json
        inner = {"verdict": "unknown", "summary": "x", "blockers": [], "notes": []}
        output = _json.dumps({"result": _json.dumps(inner)})
        bin_dir = _make_fake_claude(tmp_path, output, exit_code=0)
        result = _run_real_gate(tmp_path, bin_dir)

        assert result.returncode == 1
        sticky = (tmp_path / "sticky.log").read_text(encoding="utf-8")
        assert "暂不放行" in sticky

    def test_missing_blockers_result_fallback(
        self, tmp_path: pathlib.Path
    ) -> None:
        """Missing blockers via .result fallback → fail-closed."""
        import json as _json
        inner = {"verdict": "changes", "summary": "x", "notes": []}
        output = _json.dumps({"result": _json.dumps(inner)})
        bin_dir = _make_fake_claude(tmp_path, output, exit_code=0)
        result = _run_real_gate(tmp_path, bin_dir)

        assert result.returncode == 1
        sticky = (tmp_path / "sticky.log").read_text(encoding="utf-8")
        assert "暂不放行" in sticky

    def test_malformed_blocker_severity_result_fallback(
        self, tmp_path: pathlib.Path
    ) -> None:
        """Blocker with invalid severity via .result fallback → fail-closed."""
        import json as _json
        inner = {
            "verdict": "changes", "summary": "x",
            "blockers": [{"file": "a.swift", "severity": "medium", "why": "bad"}],
            "notes": [],
        }
        output = _json.dumps({"result": _json.dumps(inner)})
        bin_dir = _make_fake_claude(tmp_path, output, exit_code=0)
        result = _run_real_gate(tmp_path, bin_dir)

        assert result.returncode == 1
        sticky = (tmp_path / "sticky.log").read_text(encoding="utf-8")
        assert "暂不放行" in sticky

    # ------------------------------------------------------------------
    # Consistency and jq-error fail-closed tests (MY-1452 codex-review P0s)
    # ------------------------------------------------------------------

    def test_pass_with_blockers_inconsistency_failclosed(
        self, tmp_path: pathlib.Path
    ) -> None:
        """verdict=pass + non-empty blockers is inconsistent → fail-closed."""
        output = (
            '{"structured_output":{"verdict":"pass","summary":"looks good",'
            '"blockers":[{"file":"x.swift","severity":"critical","why":"oops"}],'
            '"notes":[]}}'
        )
        bin_dir = _make_fake_claude(tmp_path, output, exit_code=0)
        result = _run_real_gate(tmp_path, bin_dir)

        assert result.returncode == 1, (
            "verdict=pass + blockers must exit 1"
        )
        assert "inconsistent" in result.stdout.lower() or "不一致" in result.stdout
        sticky = (tmp_path / "sticky.log").read_text(encoding="utf-8")
        assert "暂不放行" in sticky

    def test_pass_with_blockers_result_fallback_failclosed(
        self, tmp_path: pathlib.Path
    ) -> None:
        """verdict=pass + blockers via .result fallback → fail-closed."""
        import json as _json
        inner = {
            "verdict": "pass", "summary": "ok",
            "blockers": [{"file": "b.swift", "severity": "high", "why": "leak"}],
            "notes": [],
        }
        output = _json.dumps({"result": _json.dumps(inner)})
        bin_dir = _make_fake_claude(tmp_path, output, exit_code=0)
        result = _run_real_gate(tmp_path, bin_dir)

        assert result.returncode == 1
        sticky = (tmp_path / "sticky.log").read_text(encoding="utf-8")
        assert "暂不放行" in sticky

    def test_non_object_blocker_jq_error_failclosed(
        self, tmp_path: pathlib.Path
    ) -> None:
        """Non-object element in blockers (e.g. string) causes jq error → fail-closed."""
        output = (
            '{"structured_output":{"verdict":"changes","summary":"x",'
            '"blockers":["not-an-object"],"notes":[]}}'
        )
        bin_dir = _make_fake_claude(tmp_path, output, exit_code=0)
        result = _run_real_gate(tmp_path, bin_dir)

        assert result.returncode == 1, (
            "non-object blockers element must fail-closed"
        )
        sticky = (tmp_path / "sticky.log").read_text(encoding="utf-8")
        assert "暂不放行" in sticky

    def test_non_object_blocker_result_fallback_failclosed(
        self, tmp_path: pathlib.Path
    ) -> None:
        """Non-object blocker via .result fallback → fail-closed."""
        import json as _json
        inner = {
            "verdict": "changes", "summary": "x",
            "blockers": [123, None],
            "notes": [],
        }
        output = _json.dumps({"result": _json.dumps(inner)})
        bin_dir = _make_fake_claude(tmp_path, output, exit_code=0)
        result = _run_real_gate(tmp_path, bin_dir)

        assert result.returncode == 1
        sticky = (tmp_path / "sticky.log").read_text(encoding="utf-8")
        assert "暂不放行" in sticky

    # ------------------------------------------------------------------
    # Notes item-level schema validation (MY-1452 full schema fail-closed)
    # ------------------------------------------------------------------

    def test_non_object_note_structured_output_failclosed(
        self, tmp_path: pathlib.Path
    ) -> None:
        """Non-object note element (e.g. string) → fail-closed."""
        output = (
            '{"structured_output":{"verdict":"pass","summary":"ok",'
            '"blockers":[],"notes":["bad-note"]}}'
        )
        bin_dir = _make_fake_claude(tmp_path, output, exit_code=0)
        result = _run_real_gate(tmp_path, bin_dir)

        assert result.returncode == 1, "non-object note must fail-closed"
        sticky = (tmp_path / "sticky.log").read_text(encoding="utf-8")
        assert "暂不放行" in sticky

    def test_non_object_note_result_fallback_failclosed(
        self, tmp_path: pathlib.Path
    ) -> None:
        """Non-object note via .result fallback → fail-closed."""
        import json as _json
        inner = {"verdict": "pass", "summary": "ok", "blockers": [], "notes": [42]}
        output = _json.dumps({"result": _json.dumps(inner)})
        bin_dir = _make_fake_claude(tmp_path, output, exit_code=0)
        result = _run_real_gate(tmp_path, bin_dir)

        assert result.returncode == 1
        sticky = (tmp_path / "sticky.log").read_text(encoding="utf-8")
        assert "暂不放行" in sticky

    def test_note_missing_file_failclosed(
        self, tmp_path: pathlib.Path
    ) -> None:
        """Note missing required 'file' field → fail-closed."""
        output = (
            '{"structured_output":{"verdict":"pass","summary":"ok",'
            '"blockers":[],"notes":[{"note":"nit"}]}}'
        )
        bin_dir = _make_fake_claude(tmp_path, output, exit_code=0)
        result = _run_real_gate(tmp_path, bin_dir)

        assert result.returncode == 1
        sticky = (tmp_path / "sticky.log").read_text(encoding="utf-8")
        assert "暂不放行" in sticky

    def test_note_missing_note_field_failclosed(
        self, tmp_path: pathlib.Path
    ) -> None:
        """Note missing required 'note' field → fail-closed."""
        output = (
            '{"structured_output":{"verdict":"pass","summary":"ok",'
            '"blockers":[],"notes":[{"file":"a.swift"}]}}'
        )
        bin_dir = _make_fake_claude(tmp_path, output, exit_code=0)
        result = _run_real_gate(tmp_path, bin_dir)

        assert result.returncode == 1
        sticky = (tmp_path / "sticky.log").read_text(encoding="utf-8")
        assert "暂不放行" in sticky

    def test_note_invalid_line_type_failclosed(
        self, tmp_path: pathlib.Path
    ) -> None:
        """Note with non-integer/non-null line → fail-closed."""
        output = (
            '{"structured_output":{"verdict":"pass","summary":"ok",'
            '"blockers":[],"notes":[{"file":"a.swift","note":"x","line":"bad"}]}}'
        )
        bin_dir = _make_fake_claude(tmp_path, output, exit_code=0)
        result = _run_real_gate(tmp_path, bin_dir)

        assert result.returncode == 1
        sticky = (tmp_path / "sticky.log").read_text(encoding="utf-8")
        assert "暂不放行" in sticky

    def test_blocker_invalid_line_type_failclosed(
        self, tmp_path: pathlib.Path
    ) -> None:
        """Blocker with non-integer/non-null line → fail-closed."""
        output = (
            '{"structured_output":{"verdict":"changes","summary":"x",'
            '"blockers":[{"file":"a.swift","severity":"critical","why":"bug","line":"ten"}],'
            '"notes":[]}}'
        )
        bin_dir = _make_fake_claude(tmp_path, output, exit_code=0)
        result = _run_real_gate(tmp_path, bin_dir)

        assert result.returncode == 1
        sticky = (tmp_path / "sticky.log").read_text(encoding="utf-8")
        assert "暂不放行" in sticky

    def test_note_unexpected_properties_failclosed(
        self, tmp_path: pathlib.Path
    ) -> None:
        """Note with extra properties not in schema → fail-closed."""
        output = (
            '{"structured_output":{"verdict":"pass","summary":"ok",'
            '"blockers":[],"notes":[{"file":"a.swift","note":"x","extra":"bad"}]}}'
        )
        bin_dir = _make_fake_claude(tmp_path, output, exit_code=0)
        result = _run_real_gate(tmp_path, bin_dir)

        assert result.returncode == 1
        sticky = (tmp_path / "sticky.log").read_text(encoding="utf-8")
        assert "暂不放行" in sticky

    def test_blocker_unexpected_properties_failclosed(
        self, tmp_path: pathlib.Path
    ) -> None:
        """Blocker with extra properties not in schema → fail-closed."""
        output = (
            '{"structured_output":{"verdict":"changes","summary":"x",'
            '"blockers":[{"file":"a.swift","severity":"critical","why":"bug","extra":true}],'
            '"notes":[]}}'
        )
        bin_dir = _make_fake_claude(tmp_path, output, exit_code=0)
        result = _run_real_gate(tmp_path, bin_dir)

        assert result.returncode == 1
        sticky = (tmp_path / "sticky.log").read_text(encoding="utf-8")
        assert "暂不放行" in sticky

    def test_note_invalid_line_result_fallback_failclosed(
        self, tmp_path: pathlib.Path
    ) -> None:
        """Note with invalid line via .result fallback → fail-closed."""
        import json as _json
        inner = {
            "verdict": "pass", "summary": "ok", "blockers": [],
            "notes": [{"file": "a.swift", "note": "x", "line": "bad"}],
        }
        output = _json.dumps({"result": _json.dumps(inner)})
        bin_dir = _make_fake_claude(tmp_path, output, exit_code=0)
        result = _run_real_gate(tmp_path, bin_dir)

        assert result.returncode == 1
        sticky = (tmp_path / "sticky.log").read_text(encoding="utf-8")
        assert "暂不放行" in sticky

    def test_valid_notes_with_line_pass(
        self, tmp_path: pathlib.Path
    ) -> None:
        """Well-formed notes with valid integer/null line still pass."""
        output = (
            '{"structured_output":{"verdict":"pass","summary":"ok",'
            '"blockers":[],"notes":['
            '{"file":"a.swift","note":"nit","line":42},'
            '{"file":"b.swift","note":"style","line":null}'
            ']}}'
        )
        bin_dir = _make_fake_claude(tmp_path, output, exit_code=0)
        result = _run_real_gate(tmp_path, bin_dir)

        assert result.returncode == 0, f"valid notes should pass: {result.stdout}"

    # ------------------------------------------------------------------
    # Top-level additionalProperties:false (MY-1452 full schema)
    # ------------------------------------------------------------------

    def test_toplevel_extra_property_structured_output_failclosed(
        self, tmp_path: pathlib.Path
    ) -> None:
        """Extra top-level property in .structured_output → fail-closed."""
        output = (
            '{"structured_output":{"verdict":"pass","summary":"ok",'
            '"blockers":[],"notes":[],"extra":"bad"}}'
        )
        bin_dir = _make_fake_claude(tmp_path, output, exit_code=0)
        result = _run_real_gate(tmp_path, bin_dir)

        assert result.returncode == 1, (
            "top-level extra property must fail-closed"
        )
        sticky = (tmp_path / "sticky.log").read_text(encoding="utf-8")
        assert "暂不放行" in sticky

    def test_toplevel_extra_property_result_fallback_failclosed(
        self, tmp_path: pathlib.Path
    ) -> None:
        """Extra top-level property via .result fallback → fail-closed."""
        import json as _json
        inner = {
            "verdict": "pass", "summary": "ok",
            "blockers": [], "notes": [], "injected": True,
        }
        output = _json.dumps({"result": _json.dumps(inner)})
        bin_dir = _make_fake_claude(tmp_path, output, exit_code=0)
        result = _run_real_gate(tmp_path, bin_dir)

        assert result.returncode == 1
        sticky = (tmp_path / "sticky.log").read_text(encoding="utf-8")
        assert "暂不放行" in sticky
# 5. Nonce-based untrusted-data fence (MY-1456 security fix).
# --------------------------------------------------------------------------


def test_gate_scripts_use_nonce_fence_not_static_delimiters() -> None:
    """Both review gate scripts must use nonce-based FENCE_OPEN/FENCE_CLOSE
    variables instead of hardcoded static untrusted-data markers.

    A static delimiter allows PR-controlled content (test source embedded via
    COVERAGE_CONTEXT) to inject the exact closing marker and escape the
    untrusted region. The nonce makes the boundary unpredictable.
    """
    for script_name in ("claude-review.sh", "codex-review.sh"):
        path = CI_DIR / script_name
        content = path.read_text(encoding="utf-8")

        # Must contain nonce generation and variable usage
        assert "FENCE_NONCE" in content, (
            f"{script_name} missing FENCE_NONCE generation"
        )
        assert "FENCE_OPEN" in content, (
            f"{script_name} missing FENCE_OPEN variable"
        )
        assert "FENCE_CLOSE" in content, (
            f"{script_name} missing FENCE_CLOSE variable"
        )
        assert "/dev/urandom" in content, (
            f"{script_name} must use /dev/urandom for nonce generation"
        )

        # The prompt must reference $FENCE_OPEN and $FENCE_CLOSE, not
        # hardcoded static delimiters. Check that the prompt area uses the
        # variable (the prompt is in a string assigned to PROMPT="...")
        assert "$FENCE_OPEN" in content, (
            f"{script_name} prompt must use $FENCE_OPEN variable"
        )
        assert "$FENCE_CLOSE" in content, (
            f"{script_name} prompt must use $FENCE_CLOSE variable"
        )


def test_nonce_generation_fail_closed() -> None:
    """Nonce generation failure must fail the gate (exit 1), not proceed with
    an empty or malformed nonce that would make the fence predictable."""
    for script_name in ("claude-review.sh", "codex-review.sh"):
        path = CI_DIR / script_name
        content = path.read_text(encoding="utf-8")

        # Must check nonce is non-empty and well-formed before use
        assert 'grep -qE' in content, (
            f"{script_name} must validate nonce format with grep"
        )
        # Must exit 1 on nonce failure
        assert "nonce" in content.lower() and "exit 1" in content, (
            f"{script_name} must exit 1 on nonce generation failure"
        )


# --------------------------------------------------------------------------
# 6. Nonce-bound coverage evidence inner markers (MY-1456 blocker repair).
# --------------------------------------------------------------------------


def test_coverage_evidence_uses_nonce_bound_inner_markers() -> None:
    """Both review gate scripts must wrap COVERAGE_CONTEXT with nonce-bound
    inner markers (COVERAGE_EVIDENCE_${FENCE_NONCE}_BEGIN/END).

    This prevents a forged static 'COVERAGE CONTEXT' header in the PR diff
    from being mistaken for trusted analyzer output — only the nonce-bound
    section is authoritative, and the nonce is unpredictable to the PR author.
    """
    for script_name in ("claude-review.sh", "codex-review.sh"):
        path = CI_DIR / script_name
        content = path.read_text(encoding="utf-8")

        # Must contain the nonce-bound inner markers around coverage context
        assert "COVERAGE_EVIDENCE_${FENCE_NONCE}_BEGIN" in content, (
            f"{script_name} must wrap coverage context with nonce-bound BEGIN marker"
        )
        assert "COVERAGE_EVIDENCE_${FENCE_NONCE}_END" in content, (
            f"{script_name} must wrap coverage context with nonce-bound END marker"
        )


def test_review_coverage_rules_references_nonce_markers() -> None:
    """review_coverage_rules must accept a nonce parameter and include a
    nonce-bound trust instruction so the reviewer knows which coverage
    context block is authoritative vs. forged in the diff."""
    # Call with a known nonce to verify it's referenced in output
    test_nonce = "abc123def456abc123def456abc12345"
    result = _run(
        f". {COMMON}\nreview_coverage_rules {test_nonce}\n", timeout=30
    )

    assert result.returncode == 0, result.stderr
    # The output must reference the nonce to bind trust
    assert f"COVERAGE_EVIDENCE_{test_nonce}_BEGIN" in result.stdout, (
        "review_coverage_rules must reference nonce-bound markers in output"
    )
    assert f"COVERAGE_EVIDENCE_{test_nonce}_END" in result.stdout, (
        "review_coverage_rules must reference nonce-bound markers in output"
    )


def test_coverage_rules_distinguishes_trusted_framing_from_untrusted_excerpts() -> None:
    """review_coverage_rules must explicitly state that structural metadata
    (SEARCH SCOPE, declarations, line numbers) is trusted, while SOURCE EXCERPT
    / function body content is untrusted PR-controlled source data.

    This pins the provenance-vs-content distinction required by MY-1456 AC3/AC4:
    the reviewer must trust nonce-bound framing but never treat excerpt prose
    as instructions or trusted content.
    """
    test_nonce = "deadbeef01234567deadbeef01234567"
    result = _run(
        f". {COMMON}\nreview_coverage_rules {test_nonce}\n", timeout=30
    )
    assert result.returncode == 0, result.stderr
    output = result.stdout

    # Must explicitly name excerpts/function bodies as untrusted source data
    assert "不可信源数据" in output or "untrusted" in output.lower(), (
        "review_coverage_rules must explicitly name excerpts as untrusted source data"
    )
    # Must distinguish structural labels as trusted
    assert "可信" in output, (
        "review_coverage_rules must name structural metadata as trusted"
    )
    # Must warn that excerpt content cannot be treated as instructions
    assert "指令" in output or "instruction" in output.lower(), (
        "review_coverage_rules must warn against treating excerpts as instructions"
    )


def test_security_declaration_names_coverage_excerpts_untrusted() -> None:
    """Both review gate scripts' security declaration must explicitly name
    COVERAGE EVIDENCE excerpts as untrusted source data, not just DIFF.

    This ensures the prompt's trust model accounts for PR-controlled HEAD
    source injected into the coverage evidence section.
    """
    for script_name in ("claude-review.sh", "codex-review.sh"):
        path = CI_DIR / script_name
        content = path.read_text(encoding="utf-8")

        # Must mention COVERAGE EVIDENCE / excerpt in the security declaration
        assert "COVERAGE EVIDENCE" in content or "SOURCE EXCERPT" in content, (
            f"{script_name} security declaration must name coverage excerpts"
        )
        # The security declaration must explicitly call excerpts untrusted
        # (the Chinese text uses 不可信源数据)
        security_block = ""
        for line in content.splitlines():
            if "安全声明" in line:
                # Capture the security declaration block (next few lines)
                idx = content.splitlines().index(line)
                security_block = "\n".join(content.splitlines()[idx:idx + 6])
                break
        assert "不可信源数据" in security_block or "untrusted source" in security_block.lower(), (
            f"{script_name} security declaration must call coverage excerpts untrusted source data"
        )
