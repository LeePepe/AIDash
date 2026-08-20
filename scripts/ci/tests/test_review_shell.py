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
    paths = "\n".join(
        f"Packages/AIDashUI/Sources/AIDashUI/CardView/Generated{n:04d}.swift"
        for n in range(100)
    )
    assert len(paths.encode("utf-8")) > 512

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
        f'CHANGED="{paths}"\n'
        "rc=0\n"
        "build_scope_evidence 0000000000000000000000000000000000000000 "
        f'"{empty_diff}" "$CHANGED" >/dev/null || rc=$?\n'
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
    """The claude CLI invocation includes --max-turns 1 AND --tools "".

    Without --max-turns 1, `claude -p` runs in full agentic mode — reading
    files, running commands, taking multiple turns — easily exhausting the
    900-second watchdog on the self-hosted runner (MY-1452).

    Without --tools "", built-in tools (Read, Edit, Bash, etc.) remain active
    and a single first-turn tool call can exhaust the watchdog. Both flags are
    required. `--tools ""` is the documented way to disable all tools per
    `claude --help`.

    This is a behavioural check restricted to executable lines (comments
    stripped): removing the real CLI flags while leaving them in comments must
    fail the test.
    """
    executable_lines = _code_lines(CLAUDE)
    executable_text = "\n".join(code for _, code in executable_lines)

    assert "--max-turns 1" in executable_text, (
        "claude-review.sh must pass --max-turns 1 to `claude -p` to prevent "
        "unbounded agentic exploration (MY-1452)"
    )
    assert '--tools ""' in executable_text, (
        'claude-review.sh must pass --tools "" to `claude -p` to '
        "deterministically disable all built-in tools (MY-1452)"
    )


def test_claude_review_emits_phase_timing() -> None:
    """Phase timing helpers are defined and invoked for the three phases.

    MY-1452 requires actionable phase-specific evidence: when a future timeout
    occurs, the log must say WHERE it stalled (diff / scope-evidence /
    claude-cli), not just that 900 seconds elapsed.

    This check uses _code_lines (comments stripped) so that commenting out a
    _phase_start/_phase_end call while keeping a comment mentioning it will
    correctly fail the test.
    """
    executable_lines = _code_lines(CLAUDE)
    executable_text = "\n".join(code for _, code in executable_lines)
    for phase in ("diff", "scope-evidence", "claude-cli"):
        assert f'_phase_start "{phase}"' in executable_text, (
            f"claude-review.sh is missing _phase_start for phase {phase!r} "
            f"in executable code (MY-1452)"
        )
        assert f'_phase_end "{phase}"' in executable_text, (
            f"claude-review.sh is missing _phase_end for phase {phase!r} "
            f"in executable code (MY-1452)"
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
