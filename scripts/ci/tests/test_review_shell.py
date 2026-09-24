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
        "gates would once again block every PR that touches themselves."
    )


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


def test_review_cli_timeout_seconds_defaults_to_900() -> None:
    """REVIEW_CLI_TIMEOUT_SECONDS defaults to 900 seconds when unset."""
    result = _run(
        f"unset REVIEW_CLI_TIMEOUT_SECONDS\n"
        f". {COMMON}\n"
        'echo "timeout=$REVIEW_CLI_TIMEOUT_SECONDS"\n',
        timeout=30,
    )
    assert result.returncode == 0, result.stderr
    assert "timeout=900" in result.stdout


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
        f'#!/bin/sh\nsh -c \'echo $$ > "{pidfile}"; exec sleep 120\' &\nwhile [ ! -s "{pidfile}" ]; do :; done\nwait\n',
        encoding="utf-8",
    )
    inner.chmod(0o755)

    result = _run(
        f". {COMMON}\n"
        "rc=0\n"
        f"run_with_timeout 2 {inner} || rc=$?\n"
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
        f'python3 -c \'import os, sys, time; open(sys.argv[1], "w").write(str(os.getpid())); time.sleep(120)\' "{pidfile}" &\n'
        f'while [ ! -s "{pidfile}" ]; do :; done\n'
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
        'if [ -z "$GRANDCHILD" ]; then echo NO-PID; exit 1; fi\n'
        'if kill -0 "$GRANDCHILD" 2>/dev/null; then echo LEAKED; else echo CLEAN; fi\n',
        timeout=30,
    )

    assert result.returncode == 0, result.stderr
    assert "rc=0" in result.stdout, result.stdout
    assert "CLEAN" in result.stdout, result.stdout
    assert "NO-PID" not in result.stdout, result.stdout


def test_run_with_timeout_captures_fast_out_of_pgid_descendants_before_first_snapshot(
    tmp_path: pathlib.Path,
) -> None:
    """A fast leader that exits before the first poll still leaves no leaked descendant."""
    pidfile = tmp_path / "grandchild.pid"
    inner = tmp_path / "inner.sh"
    inner.write_text(
        '#!/bin/sh\n'
        f'python3 -c \'import os, sys, time; pidfile = sys.argv[1]; os.setsid(); open(pidfile, "w").write(str(os.getpid())); time.sleep(120)\' "{pidfile}" &\n'
        f'while [ ! -s "{pidfile}" ]; do :; done\n'
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
        'if [ -z "$GRANDCHILD" ]; then echo NO-PID; exit 1; fi\n'
        'if kill -0 "$GRANDCHILD" 2>/dev/null; then echo LEAKED; else echo CLEAN; fi\n',
        timeout=30,
    )

    assert result.returncode == 0, result.stderr
    assert "rc=0" in result.stdout, result.stdout
    assert "CLEAN" in result.stdout, result.stdout
    assert "NO-PID" not in result.stdout, result.stdout


def test_run_with_timeout_cleans_nested_descendant_tree_after_leader_exits_zero(
    tmp_path: pathlib.Path,
) -> None:
    """A nested descendant tree is cleaned before the leader is reported as done."""
    pidfile = tmp_path / "grandchild.pid"
    inner = tmp_path / "inner.sh"
    inner.write_text(
        '#!/bin/sh\n'
        f'python3 - "{pidfile}" <<\'PY\' &\n'
        'import os, sys, time\n'
        'pidfile = sys.argv[1]\n'
        'os.setsid()\n'
        'with open(pidfile, "w", encoding="utf-8") as fh:\n'
        '    fh.write(str(os.getpid()))\n'
        'time.sleep(120)\n'
        'PY\n'
        f'while [ ! -s "{pidfile}" ]; do :; done\n'
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
        'if [ -z "$GRANDCHILD" ]; then echo NO-PID; exit 1; fi\n'
        'if kill -0 "$GRANDCHILD" 2>/dev/null; then echo LEAKED; else echo CLEAN; fi\n',
        timeout=30,
    )

    assert result.returncode == 0, result.stderr
    assert "rc=0" in result.stdout, result.stdout
    assert "CLEAN" in result.stdout, result.stdout
    assert "NO-PID" not in result.stdout, result.stdout


def test_run_with_timeout_does_not_kill_unrelated_orphan_processes(
    tmp_path: pathlib.Path,
) -> None:
    """Cleanup only targets identities already observed in the launched tree."""
    pidfile = tmp_path / "unrelated.pid"
    unrelated = tmp_path / "unrelated.sh"
    unrelated.write_text(
        '#!/bin/sh\n'
        'exec sleep 120\n',
        encoding="utf-8",
    )
    unrelated.chmod(0o755)

    result = _run(
        f". {COMMON}\n"
        f'python3 - "{unrelated}" "{pidfile}" <<\'PY\'\n'
        'import os, subprocess, sys\n'
        'script = sys.argv[1]\n'
        'pid_file = sys.argv[2]\n'
        'proc = subprocess.Popen([script], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)\n'
        'with open(pid_file, "w", encoding="utf-8") as fh:\n'
        '    fh.write(str(proc.pid))\n'
        'PY\n'
        "rc=0\n"
        "run_with_timeout 2 /bin/sh -c 'exit 0' || rc=$?\n"
        'echo "rc=$rc"\n'
        f'UNRELATED="$(cat "{pidfile}" 2>/dev/null)"\n'
        'if [ -z "$UNRELATED" ]; then echo NO-PID; exit 1; fi\n'
        'if kill -0 "$UNRELATED" 2>/dev/null; then echo SAFE; else echo KILLED; fi\n'
        'kill -TERM "$UNRELATED" 2>/dev/null || true\n',
        timeout=30,
    )

    assert result.returncode == 0, result.stderr
    assert "rc=0" in result.stdout, result.stdout
    assert "SAFE" in result.stdout, result.stdout
    assert "KILLED" not in result.stdout, result.stdout


def test_run_with_timeout_exits_clean_on_leader_exit_before_deadline_boundary(
    tmp_path: pathlib.Path,
) -> None:
    """A leader that exits on the final interval must not be misclassified as timeout."""
    pidfile = tmp_path / "grandchild.pid"
    inner = tmp_path / "inner.sh"
    inner.write_text(
        '#!/bin/sh\n'
        f"sh -c 'echo $$ > \"{pidfile}\"; exec sleep 120' &\n"
        f'while [ ! -s "{pidfile}" ]; do :; done\n'
        'sleep 0.8\n'
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
        'if [ -z "$GRANDCHILD" ]; then echo NO-PID; exit 1; fi\n'
        'if kill -0 "$GRANDCHILD" 2>/dev/null; then echo LEAKED; else echo CLEAN; fi\n',
        timeout=30,
    )

    assert result.returncode == 0, result.stderr
    assert "rc=0" in result.stdout, result.stdout
    assert "CLEAN" in result.stdout, result.stdout
    assert "NO-PID" not in result.stdout, result.stdout


def test_run_with_timeout_returns_124_for_late_nonzero_exit_after_deadline() -> None:
    """A late nonzero exit after the wall-clock deadline is fail-closed as timeout."""
    result = _run(
        f". {COMMON}\n"
        "rc=0\n"
        "run_with_timeout 1 /bin/sh -c 'sleep 2; exit 3' || rc=$?\n"
        'echo "rc=$rc"\n',
        timeout=30,
    )

    assert result.returncode == 0, result.stderr
    assert "rc=124" in result.stdout, result.stdout


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
        f'while [ ! -s "{pidfile}" ]; do :; done\n'
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


def test_run_with_timeout_kills_nested_wrapper_descendants(tmp_path: pathlib.Path) -> None:
    """A nested env→bash→child wrapper must not leave a grandchild alive."""
    pidfile = tmp_path / "grandchild.pid"
    inner = tmp_path / "inner.sh"
    inner.write_text(
        f'#!/bin/sh\n'
        f'env FOO=bar python3 -c \'import os, sys, time; open(sys.argv[1], "w").write(str(os.getpid())); time.sleep(120)\' "{pidfile}" &\n'
        f'while [ ! -s "{pidfile}" ]; do :; done\n'
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
        'if [ -z "$GRANDCHILD" ]; then echo NO-PID; exit 1; fi\n'
        'if kill -0 "$GRANDCHILD" 2>/dev/null; then echo LEAKED; else echo CLEAN; fi\n',
        timeout=30,
    )

    assert result.returncode == 0, result.stderr
    assert "rc=0" in result.stdout, result.stdout
    assert "CLEAN" in result.stdout, result.stdout
    assert "NO-PID" not in result.stdout, result.stdout


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

    # Reach the sleeping fake Codex through the real provider bootstrap, not a
    # setup failure or the operator's daily provider/credentials.
    raven_config = tmp_path / "raven.toml"
    raven_config.write_text(
        'model_provider = "raven"\n[model_providers.raven]\n'
        'base_url = "http://localhost:7024/v1"\n'
        'wire_api = "responses"\nenv_key = "RAVEN_API_KEY"\n',
        encoding="utf-8",
    )
    env_prefix = (
        f'export PATH="{stub_dir}:$PATH"\n'
        f'export CODEX_RAVEN_CONFIG="{raven_config}" RAVEN_API_KEY=offline-fixture\n'
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
    if cli_name == "codex":
        assert "codex CLI 超时" in result.stdout, result.stdout + result.stderr


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


class TestProcessSupervisorContract:
    """Deterministic contract tests for the T020 Process Supervisor state machine."""

    @pytest.fixture(autouse=True)
    def _setup_path(self) -> None:
        import sys
        sys_path = str(CI_DIR)
        if sys_path not in sys.path:
            sys.path.insert(0, sys_path)

    def test_scripted_ordering_pre_deadline_retains_status(self) -> None:
        from review_process_supervisor import (
            ProcessSupervisor, ScriptedAdapter, ScriptedClock,
        )
        clock = ScriptedClock(start=1000.0)
        adapter = ScriptedAdapter()
        sup = ProcessSupervisor(timeout_seconds=2.0, command=["echo", "hi"], adapter=adapter, clock=clock)

        sup.root_identity = adapter.register_process(100, 1, 100, "1000.0", has_capability=True)
        sup.root_pgid = 100
        sup.ledger[sup.root_identity] = sup.root_identity
        sup.start_time = 1000.0
        sup.deadline = 1002.0

        clock.advance(1.5)  # leader completes at 1001.5 <= 1002.0
        leader_completion = clock.monotonic()
        adapter.alive.discard(100)
        cleanup_ok = sup._cleanup()
        assert cleanup_ok is True
        rc = sup.classify_outcome(
            leader_completion_time=leader_completion,
            child_status=42,
            timed_out=False,
            cleanup_ok=cleanup_ok,
        )
        assert rc == 42

    def test_scripted_ordering_exact_tie_returns_real_status(self) -> None:
        from review_process_supervisor import (
            ProcessSupervisor, ScriptedAdapter, ScriptedClock,
        )
        clock = ScriptedClock(start=1000.0)
        adapter = ScriptedAdapter()
        sup = ProcessSupervisor(timeout_seconds=2.0, command=["echo", "hi"], adapter=adapter, clock=clock)

        sup.root_identity = adapter.register_process(100, 1, 100, "1000.0", has_capability=True)
        sup.root_pgid = 100
        sup.ledger[sup.root_identity] = sup.root_identity
        sup.start_time = 1000.0
        sup.deadline = 1002.0

        clock.advance(2.0)  # leader completes exactly at deadline 1002.0 == 1002.0
        leader_completion_time = clock.monotonic()
        adapter.alive.discard(100)
        cleanup_ok = sup._cleanup()
        assert cleanup_ok is True
        rc = sup.classify_outcome(
            leader_completion_time=leader_completion_time,
            child_status=0,
            timed_out=False,
            cleanup_ok=cleanup_ok,
        )
        assert rc == 0

    def test_scripted_ordering_post_deadline_returns_124(self) -> None:
        from review_process_supervisor import (
            ProcessSupervisor, ScriptedAdapter, ScriptedClock,
        )
        clock = ScriptedClock(start=1000.0)
        adapter = ScriptedAdapter()
        sup = ProcessSupervisor(timeout_seconds=2.0, command=["sleep", "10"], adapter=adapter, clock=clock)

        sup.root_identity = adapter.register_process(100, 1, 100, "1000.0", has_capability=True)
        sup.root_pgid = 100
        sup.ledger[sup.root_identity] = sup.root_identity
        sup.start_time = 1000.0
        sup.deadline = 1002.0

        clock.advance(2.001)  # past deadline
        leader_completion_time = clock.monotonic()
        cleanup_ok = sup._cleanup()
        rc = sup.classify_outcome(
            leader_completion_time=leader_completion_time,
            child_status=0,
            timed_out=True,
            cleanup_ok=cleanup_ok,
        )
        assert rc == 124

    def test_pid_birth_marker_reuse_is_never_signalled(self) -> None:
        from review_process_supervisor import (
            ProcessSupervisor, ScriptedAdapter,
        )
        import signal
        adapter = ScriptedAdapter()
        sup = ProcessSupervisor(timeout_seconds=2.0, command=["echo", "hi"], adapter=adapter)

        orig_ident = adapter.register_process(200, 1, 200, "1000.0", has_capability=True)
        sup.ledger[orig_ident] = orig_ident

        # Process dies and PID 200 is reused by an unrelated process with a newer birth marker
        adapter.alive.discard(200)
        adapter.register_process(200, 1, 1, "2000.0", has_capability=False)

        # Attempt to signal the original identity
        signalled = adapter.signal_identity(orig_ident, signal.SIGTERM)
        assert signalled is False
        assert ("pid", 200, signal.SIGTERM) in adapter.signal_log
        assert 200 in adapter.alive  # The new process is NOT killed

    def test_concurrent_supervisors_never_cross_signal(self) -> None:
        from review_process_supervisor import (
            ProcessSupervisor, ScriptedAdapter,
        )
        adapter = ScriptedAdapter()
        sup1 = ProcessSupervisor(timeout_seconds=2.0, command=["cmd1"], adapter=adapter)
        sup2 = ProcessSupervisor(timeout_seconds=2.0, command=["cmd2"], adapter=adapter)

        # Sup1 spawns 101, Sup2 spawns 201
        p1 = adapter.register_process(101, 1, 101, "1000.0", has_capability=False)
        p2 = adapter.register_process(201, 1, 201, "1000.0", has_capability=False)
        sup1.root_identity = p1
        sup1.root_pgid = 101
        sup1.ledger[p1] = p1

        sup2.root_identity = p2
        sup2.root_pgid = 201
        sup2.ledger[p2] = p2

        # Sup1 spawns child 102 carrying sup1 capability; Sup2 spawns child 202 carrying sup2 capability
        p1_child = adapter.register_process(102, 101, 101, "1000.1", has_capability=False)
        p2_child = adapter.register_process(202, 201, 201, "1000.1", has_capability=False)

        sup1._refresh_ledger()
        sup2._refresh_ledger()

        assert p1_child in sup1.ledger
        assert p2_child not in sup1.ledger
        assert p2_child in sup2.ledger
        assert p1_child not in sup2.ledger

        sup1._cleanup()
        assert adapter.is_alive(p1) is False
        assert adapter.is_alive(p1_child) is False
        assert adapter.is_alive(p2) is True
        assert adapter.is_alive(p2_child) is True

    def test_reparented_ledger_identities_retained_through_cleanup(self) -> None:
        from review_process_supervisor import (
            ProcessSupervisor, ScriptedAdapter,
        )
        adapter = ScriptedAdapter()
        sup = ProcessSupervisor(timeout_seconds=2.0, command=["cmd"], adapter=adapter)

        root = adapter.register_process(300, 1, 300, "1000.0", has_capability=True)
        sup.root_identity = root
        sup.root_pgid = 300
        sup.ledger[root] = root

        # Child 301 is created by root, is TERM-resistant, reparents to PPID 1 and sets own PGID 301
        child = adapter.register_process(
            301, 300, 301, "1000.1", has_capability=True, term_resistant=True
        )
        sup._refresh_ledger()
        assert child in sup.ledger

        # Now simulate root dying and child having ppid=1
        adapter.alive.discard(300)
        adapter.processes[301] = adapter.processes[301]._replace(ppid=1)

        # Child is retained in ledger and killed on KILL phase of cleanup
        assert sup.ledger[child] == child
        cleanup_ok = sup._cleanup()
        assert cleanup_ok is True
        assert adapter.is_alive(child) is False
        rc = sup.classify_outcome(
            leader_completion_time=1001.0,
            child_status=0,
            timed_out=False,
            cleanup_ok=cleanup_ok,
        )
        assert rc == 0

    def test_cleanup_proof_failure_returns_fail_closed(self) -> None:
        from review_process_supervisor import (
            ProcessSupervisor, ScriptedAdapter,
        )
        adapter = ScriptedAdapter()
        adapter.fail_cleanup_proof = True  # simulate unkillable process
        sup = ProcessSupervisor(timeout_seconds=2.0, command=["cmd"], adapter=adapter)

        root = adapter.register_process(400, 1, 400, "1000.0", has_capability=True)
        sup.root_identity = root
        sup.root_pgid = 400
        sup.ledger[root] = root

        cleanup_ok = sup._cleanup()
        assert cleanup_ok is False
        rc = sup.classify_outcome(
            leader_completion_time=1001.0,
            child_status=0,
            timed_out=False,
            cleanup_ok=cleanup_ok,
        )
        assert rc == 125

    def test_membership_failure_sets_supervision_error_and_fails_closed(self) -> None:
        from review_process_supervisor import (
            ProcessSupervisor, ScriptedAdapter,
        )
        adapter = ScriptedAdapter()
        adapter.fail_membership = True
        sup = ProcessSupervisor(timeout_seconds=2.0, command=["cmd"], adapter=adapter)

        root = adapter.register_process(500, 1, 500, "1000.0", has_capability=True)
        sup.root_identity = root
        sup.root_pgid = 500
        sup.ledger[root] = root

        sup._refresh_ledger()
        assert sup.supervision_error is True
        cleanup_ok = sup._cleanup()
        assert cleanup_ok is False
        rc = sup.classify_outcome(
            leader_completion_time=1001.0,
            child_status=0,
            timed_out=False,
            cleanup_ok=cleanup_ok,
        )
        assert rc == 125

    def test_spawn_during_cleanup_is_discovered_and_cleaned(self) -> None:
        from review_process_supervisor import (
            ProcessSupervisor, ScriptedAdapter,
        )
        import signal
        adapter = ScriptedAdapter()
        sup = ProcessSupervisor(timeout_seconds=2.0, command=["cmd"], adapter=adapter)

        root = adapter.register_process(600, 1, 600, "1000.0", has_capability=True)
        sup.root_identity = root
        sup.root_pgid = 600
        sup.ledger[root] = root

        # Hook: when root 600 receives SIGTERM during cleanup, it dynamically spawns child 601
        child_ref = []
        def spawn_child_on_term():
            if not child_ref:
                c = adapter.register_process(601, 600, 601, "1000.5", has_capability=True)
                child_ref.append(c)

        adapter.signal_hooks.append((600, signal.SIGTERM, spawn_child_on_term))

        cleanup_ok = sup._cleanup()
        assert cleanup_ok is True
        assert len(child_ref) == 1
        assert adapter.is_alive(root) is False
        assert adapter.is_alive(child_ref[0]) is False
        rc = sup.classify_outcome(
            leader_completion_time=1001.0,
            child_status=0,
            timed_out=False,
            cleanup_ok=cleanup_ok,
        )
        assert rc == 0

    def test_unrelated_simultaneous_processes_survive_untouched(self) -> None:
        from review_process_supervisor import (
            ProcessSupervisor, ScriptedAdapter,
        )
        adapter = ScriptedAdapter()
        sup = ProcessSupervisor(timeout_seconds=2.0, command=["cmd"], adapter=adapter)

        root = adapter.register_process(700, 1, 700, "1000.0", has_capability=True)
        sup.root_identity = root
        sup.root_pgid = 700
        sup.ledger[root] = root

        # Unrelated processes with ppid=1, distinct PGIDs, no capability
        p_sleep = adapter.register_process(801, 1, 801, "900.0", has_capability=False)
        p_node = adapter.register_process(802, 1, 802, "950.0", has_capability=False)
        p_python = adapter.register_process(803, 1, 803, "960.0", has_capability=False)

        sup._refresh_ledger()
        assert p_sleep not in sup.ledger
        assert p_node not in sup.ledger
        assert p_python not in sup.ledger

        cleanup_ok = sup._cleanup()
        assert cleanup_ok is True
        assert adapter.is_alive(p_sleep) is True
        assert adapter.is_alive(p_node) is True
        assert adapter.is_alive(p_python) is True

    def test_parent_revalidation_rejects_reused_ppid(self) -> None:
        from review_process_supervisor import (
            ProcessSupervisor, ScriptedAdapter,
        )
        adapter = ScriptedAdapter()
        sup = ProcessSupervisor(timeout_seconds=2.0, command=["cmd"], adapter=adapter)

        root = adapter.register_process(900, 1, 900, "1000.0", has_capability=True)
        sup.root_identity = root
        sup.root_pgid = 900
        sup.ledger[root] = root

        # Root dies and PID 900 is reused by an unrelated process with a newer birth marker
        adapter.alive.discard(900)
        reused_root = adapter.register_process(900, 1, 1, "2000.0", has_capability=False)
        assert reused_root.birth_marker == "2000.0"

        # A new process claims ppid=900, but its parent is the reused 900 (not original root)
        fake_child = adapter.register_process(901, 900, 901, "2000.1", has_capability=False)
        assert adapter.processes[fake_child.pid].ppid == 900

        sup._refresh_ledger()
        # fake_child should NOT be admitted to ledger
        assert fake_child not in sup.ledger

    def test_pgid_reuse_never_signalled_as_group(self) -> None:
        from review_process_supervisor import (
            ProcessSupervisor, ScriptedAdapter,
        )
        adapter = ScriptedAdapter()
        sup = ProcessSupervisor(timeout_seconds=2.0, command=["cmd"], adapter=adapter)

        orig_root = adapter.register_process(950, 1, 950, "1000.0", has_capability=True)
        sup.root_identity = orig_root
        sup.root_pgid = 950
        sup.ledger[orig_root] = orig_root

        # Root dies and unrelated process takes PGID 950
        adapter.alive.discard(950)
        reused_pgid = adapter.register_process(950, 1, 950, "3000.0", has_capability=False)
        # Unrelated candidate claiming PGID 950
        cand_951 = adapter.register_process(951, 1, 950, "3000.1", has_capability=False)

        # 1. Refresh ledger must NOT admit candidate in reused PGID
        sup._refresh_ledger()
        assert cand_951 not in sup.ledger

        # 2. Cleanup must NOT signal the reused PGID 950
        cleanup_ok = sup._cleanup(leader_pid=0)
        assert cleanup_ok is True
        assert adapter.is_alive(reused_pgid) is True
        assert adapter.is_alive(cand_951) is True
        # Verify signal_log has no signals to pgid 950
        pgid_signals = [item for item in adapter.signal_log if item[0] == "pgid" and item[1] == 950]
        assert len(pgid_signals) == 0

    def test_stale_snapshot_disappeared_parent_or_root_never_admitted_nor_signalled(self) -> None:
        from review_process_supervisor import (
            ProcessSupervisor, ScriptedAdapter, ProcessIdentity,
        )
        adapter = ScriptedAdapter()
        sup = ProcessSupervisor(timeout_seconds=2.0, command=["cmd"], adapter=adapter)

        # Record parent 800 and root 800 in ledger
        ident_800 = ProcessIdentity(800, "1000.0")
        sup.root_identity = ident_800
        sup.root_pgid = 800
        sup.ledger[ident_800] = ident_800

        # Candidate 801 claiming ppid=800, candidate 802 claiming pgid=800
        cand_801 = adapter.register_process(801, 800, 801, "1500.0", has_capability=False)
        cand_802 = adapter.register_process(802, 1, 800, "1500.0", has_capability=False)

        # But parent/root 800 is not in adapter (disappeared before revalidation)
        assert adapter.get_identity(800) is None

        sup._refresh_ledger()
        # Neither candidate should be admitted because positive identity lookup failed
        assert cand_801 not in sup.ledger
        assert cand_802 not in sup.ledger

        # Cleanup should not signal them
        sup._cleanup(leader_pid=0)
        assert adapter.is_alive(cand_801) is True
        assert adapter.is_alive(cand_802) is True

    def test_signalling_failure_returns_125(self) -> None:
        from review_process_supervisor import (
            ProcessSupervisor, ScriptedAdapter,
        )
        adapter = ScriptedAdapter()
        adapter.fail_signalling = True
        sup = ProcessSupervisor(timeout_seconds=2.0, command=["cmd"], adapter=adapter)

        root = adapter.register_process(700, 1, 700, "1000.0", has_capability=True)
        sup.root_identity = root
        sup.root_pgid = 700
        sup.ledger[root] = root

        cleanup_ok = sup._cleanup(leader_pid=700)
        assert cleanup_ok is False
        assert sup.supervision_error is True

        rc = sup.classify_outcome(
            leader_completion_time=1001.0,
            child_status=0,
            timed_out=False,
            cleanup_ok=cleanup_ok,
        )
        assert rc == 125

    def test_relay_error_and_eof_failure_returns_125(self, tmp_path: pathlib.Path, monkeypatch: pytest.MonkeyPatch) -> None:
        import errno
        import os
        import sys
        from review_process_supervisor import ProcessSupervisor

        # Normal execution to baseline
        sup = ProcessSupervisor(
            timeout_seconds=5.0,
            command=[sys.executable, "-c", "import sys; sys.stdout.write('hello'); sys.stdout.flush(); sys.exit(0)"],
        )
        rc = sup.run()
        assert rc == 0

        # Inject relay write failure during run()
        orig_write = os.write
        def broken_write(fd, data):
            if fd in (1, 2):
                raise OSError(errno.EIO, "Simulated I/O error on relay dest")
            return orig_write(fd, data)

        monkeypatch.setattr(os, "write", broken_write)
        sup2 = ProcessSupervisor(
            timeout_seconds=5.0,
            command=[sys.executable, "-c", "import sys; sys.stdout.write('data'); sys.stdout.flush(); sys.exit(0)"],
        )
        rc2 = sup2.run()
        assert rc2 == 125
        assert sup2.supervision_error is True

    def test_barrier_readiness_failure_aborts_without_releasing_target(self, tmp_path: pathlib.Path) -> None:
        import sys
        marker_file = tmp_path / "executed.marker"

        # End-to-end execution of ProcessSupervisor.run() with a mock child readiness failure
        from review_process_supervisor import ProcessSupervisor, SUPERVISOR_ERROR_RC, ScriptedAdapter
        adapter = ScriptedAdapter()
        # If adapter returns None for identity at barrier, run() aborts with SUPERVISOR_ERROR_RC (125)
        # without releasing the target barrier.
        sup = ProcessSupervisor(
            timeout_seconds=2.0,
            command=[
                sys.executable,
                "-c",
                f"import pathlib; pathlib.Path('{marker_file}').write_text('ran');",
            ],
            adapter=adapter,
        )
        # In adapter, pid lookup returns None initially -> ready verification fails closed
        rc = sup.run()
        assert rc == SUPERVISOR_ERROR_RC
        assert not marker_file.exists()

    def test_cleanup_continues_for_all_members_after_single_inspection_error(self) -> None:
        import signal
        from review_process_supervisor import ProcessSupervisor, ScriptedAdapter

        adapter = ScriptedAdapter()
        sup = ProcessSupervisor(timeout_seconds=5.0, command=["cmd"], adapter=adapter)

        # Register root (100) and two children (101, 102), all term_resistant to verify signal delivery
        r_ident = adapter.register_process(100, 1, 100, "100.000000", term_resistant=True)
        c1_ident = adapter.register_process(101, 100, 100, "101.000000", term_resistant=True)
        c2_ident = adapter.register_process(102, 100, 100, "102.000000", term_resistant=True)

        sup.root_identity = r_ident
        sup.root_pgid = 100
        sup.ledger[r_ident] = r_ident
        sup.ledger[c1_ident] = c1_ident
        sup.ledger[c2_ident] = c2_ident

        # Inject inspection uncertainty on PID 101
        adapter.fail_inspection_pids.add(101)

        # Run cleanup
        cleanup_res = sup._cleanup(leader_pid=100)

        # 1. Cleanup must fail closed and record supervision error
        assert cleanup_res is False
        assert sup.supervision_error is True
        assert sup.classify_outcome(
            leader_completion_time=1.0, child_status=0, timed_out=False, cleanup_ok=cleanup_res
        ) == 125

        # 2. Cleanup must have continued and sent signals to remaining members (100, 102)
        signalled_pids_term = [pid for kind, pid, sig in adapter.signal_log if kind == "pid" and sig == signal.SIGTERM]
        signalled_pgid_term = [pgid for kind, pgid, sig in adapter.signal_log if kind == "pgid" and sig == signal.SIGTERM]
        signalled_pgid_kill = [pgid for kind, pgid, sig in adapter.signal_log if kind == "pgid" and sig == signal.SIGKILL]

        assert 100 in signalled_pgid_term
        assert 100 in signalled_pgid_kill
        assert 100 in signalled_pids_term
        assert 102 in signalled_pids_term

    def test_candidate_capability_inspection_failure_sets_supervision_error_returns_125(self) -> None:
        from review_process_supervisor import ProcessSupervisor, ScriptedAdapter, SUPERVISOR_ERROR_RC

        adapter = ScriptedAdapter()
        sup = ProcessSupervisor(timeout_seconds=5.0, command=["cmd"], adapter=adapter)

        # Register root (100) and a descendant candidate (101)
        r_ident = adapter.register_process(100, 1, 100, "100.000000")
        adapter.register_process(101, 100, 100, "101.000000", has_capability=True)

        sup.root_identity = r_ident
        sup.root_pgid = 100
        sup.ledger[r_ident] = r_ident

        # Inject capability inspection uncertainty on PID 101 during candidate discovery
        adapter.fail_capability_pids.add(101)

        # Refresh ledger must catch InspectionError, set supervision_error = True
        sup._refresh_ledger()

        assert sup.supervision_error is True
        rc = sup.classify_outcome(
            leader_completion_time=1.0,
            child_status=0,
            timed_out=False,
            cleanup_ok=True,
        )
        assert rc == SUPERVISOR_ERROR_RC

    def test_terminal_event_before_deadline_polled_after_deadline_returns_success(self) -> None:
        from review_process_supervisor import ProcessSupervisor, ScriptedClock, ScriptedAdapter

        clock = ScriptedClock(start=100.0)
        adapter = ScriptedAdapter()
        sup = ProcessSupervisor(timeout_seconds=5.0, command=["cmd"], adapter=adapter, clock=clock)
        sup.start_time = 100.0
        sup.deadline = 105.0

        # Terminal event arrived at 104.0 (before deadline 105.0), polled/classified after deadline at 106.0
        rc = sup.classify_outcome(
            leader_completion_time=104.0,
            child_status=0,
            timed_out=False,
            cleanup_ok=True,
        )
        assert rc == 0

    def test_stop_continue_before_deadline_terminal_exit_after_deadline_returns_124(self) -> None:
        from review_process_supervisor import (
            ProcessSupervisor,
            ScriptedClock,
            ScriptedAdapter,
            REVIEW_TIMEOUT_RC,
        )

        clock = ScriptedClock(start=100.0)
        adapter = ScriptedAdapter()
        sup = ProcessSupervisor(
            timeout_seconds=5.0,
            command=["mock_cmd"],
            adapter=adapter,
            clock=clock,
        )
        sup.start_time = 100.0
        sup.deadline = 105.0

        # Outcome classification logic with deadline arbitration:
        # Stop at 101.0, Continue at 102.0, Terminal Exit at 106.0 (after deadline 105.0)
        rc_classified = sup.classify_outcome(
            leader_completion_time=106.0,
            child_status=0,
            timed_out=False,
            cleanup_ok=True,
        )
        assert rc_classified == REVIEW_TIMEOUT_RC

    def test_darwin_adapter_non_definitive_inspection_results(self, monkeypatch) -> None:
        import sys
        if sys.platform != "darwin":
            pytest.skip("Darwin-specific test requires Darwin platform")
        import ctypes
        import errno
        import os
        from review_process_supervisor import DarwinMembershipAdapter, InspectionError

        adapter = DarwinMembershipAdapter()
        cap_bytes = b"CAP_KEY=test_cap"

        # 1. Direct _get_bsdinfo testing on living vs dead vs other-user process
        def mock_pidinfo_fail(pid, flavor, arg, ptr, sz):
            ctypes.set_errno(errno.EPERM)
            return 0

        monkeypatch.setattr(adapter.libproc, "proc_pidinfo", mock_pidinfo_fail)

        # Other user verified by proc_bsdshortinfo (effective UID != my_uid) -> returns None
        def mock_pidinfo_shortinfo_other_user(pid, flavor, arg, ptr, sz):
            if flavor == adapter.PROC_PIDT_BSHORTINFO and ptr:
                sinfo = ctypes.cast(ptr, ctypes.POINTER(adapter.proc_bsdshortinfo)).contents
                sinfo.pbsi_status = 2  # Alive
                sinfo.pbsi_uid = os.getuid() + 1000  # Provably different UID
                return sz
            ctypes.set_errno(errno.EPERM)
            return 0

        monkeypatch.setattr(adapter.libproc, "proc_pidinfo", mock_pidinfo_shortinfo_other_user)
        monkeypatch.setattr(os, "kill", lambda pid, sig: None)
        assert adapter._get_bsdinfo(99999) is None

        # Zombie verified by proc_bsdshortinfo (pbsi_status == 5) -> returns None
        def mock_pidinfo_shortinfo_zombie(pid, flavor, arg, ptr, sz):
            if flavor == adapter.PROC_PIDT_BSHORTINFO and ptr:
                sinfo = ctypes.cast(ptr, ctypes.POINTER(adapter.proc_bsdshortinfo)).contents
                sinfo.pbsi_status = 5  # SZOMB
                sinfo.pbsi_uid = os.getuid()
                return sz
            ctypes.set_errno(errno.EPERM)
            return 0

        monkeypatch.setattr(adapter.libproc, "proc_pidinfo", mock_pidinfo_shortinfo_zombie)
        assert adapter._get_bsdinfo(99999) is None

        # Same-UID living process with indeterminate permission failure (UID not proven different) -> raises InspectionError
        monkeypatch.setattr(adapter.libproc, "proc_pidinfo", mock_pidinfo_fail)
        monkeypatch.setattr(os, "kill", lambda pid, sig: None)  # Living process
        with pytest.raises(InspectionError):
            adapter._get_bsdinfo(99999)

        # Unresolved kill PermissionError without UID proof -> raises InspectionError
        def mock_kill_perm_error(pid, sig):
            raise PermissionError("Indeterminate permission error")

        monkeypatch.setattr(os, "kill", mock_kill_perm_error)
        with pytest.raises(InspectionError):
            adapter._get_bsdinfo(99999)

        # When dead (kill raises ProcessLookupError), _get_bsdinfo returns None
        monkeypatch.setattr(os, "kill", lambda pid, sig: (_ for _ in ()).throw(ProcessLookupError()))
        assert adapter._get_bsdinfo(99999) is None

        # 2. Direct enumerate_candidates testing
        def mock_listpids(buf, bufsz):
            if buf is None:
                return 2
            buf[0] = 101  # other user
            buf[1] = 102  # same UID but inspection failure
            return 2

        monkeypatch.setattr(adapter.libproc, "proc_listallpids", mock_listpids)

        def mock_pidinfo_multi(pid, flavor, arg, ptr, sz):
            if flavor == adapter.PROC_PIDT_BSHORTINFO and ptr:
                sinfo = ctypes.cast(ptr, ctypes.POINTER(adapter.proc_bsdshortinfo)).contents
                if pid == 101:
                    sinfo.pbsi_status = 2
                    sinfo.pbsi_uid = os.getuid() + 1000  # Provably other user
                    return sz
            ctypes.set_errno(errno.EPERM)
            return 0

        monkeypatch.setattr(adapter.libproc, "proc_pidinfo", mock_pidinfo_multi)
        monkeypatch.setattr(os, "kill", lambda pid, sig: None)

        with pytest.raises(InspectionError):
            adapter.enumerate_candidates("test_cap")

        # 3. sysctl KERN_PROCARGS2 capability probing
        class MockBsdInfo:
            pbi_status = 2  # Alive
            pbi_start_tvsec = 1000
            pbi_start_tvusec = 0
            pbi_uid = os.getuid()
            pbi_ruid = os.getuid()
            pbi_ppid = 1
            pbi_pgid = 99999

        monkeypatch.setattr(adapter, "_get_bsdinfo", lambda pid: MockBsdInfo() if pid == 99999 else None)
        monkeypatch.setattr(os, "kill", lambda pid, sig: None)  # Living process

        # Non-definitive sysctl errnos (EINVAL, EIO, 14/EFAULT, EPERM) must raise InspectionError on living candidate
        for err in (errno.EINVAL, errno.EIO, 14, errno.EPERM):
            def mock_sysctl_fail(mib, miblen, buf, bufp, newp, newlen, _err=err):
                ctypes.set_errno(_err)
                return -1

            monkeypatch.setattr(adapter.libc, "sysctl", mock_sysctl_fail)
            with pytest.raises(InspectionError):
                adapter._has_capability(99999, cap_bytes, birth_marker="1000.000000")

        # Zombie process (pbi_status == 5) returns False
        class MockZombieInfo:
            pbi_status = 5
            pbi_start_tvsec = 1000
            pbi_start_tvusec = 0

        monkeypatch.setattr(adapter, "_get_bsdinfo", lambda pid: MockZombieInfo())
        assert adapter._has_capability(99999, cap_bytes, birth_marker="1000.000000") is False

        # Birth marker mismatch (recycled PID) returns False
        monkeypatch.setattr(adapter, "_get_bsdinfo", lambda pid: MockBsdInfo())
        assert adapter._has_capability(99999, cap_bytes, birth_marker="2000.000000") is False

        # Dead process via kill raising ProcessLookupError returns False
        def mock_kill_dead(pid, sig):
            raise ProcessLookupError()

        monkeypatch.setattr(os, "kill", mock_kill_dead)
        assert adapter._has_capability(99999, cap_bytes, birth_marker="1000.000000") is False

    def test_linux_adapter_inspection_fail_closed(self, monkeypatch, tmp_path) -> None:
        import os
        from review_process_supervisor import LinuxMembershipAdapter, InspectionError

        adapter = LinuxMembershipAdapter()

        # 1. Malformed /proc/<pid>/stat without paren
        proc_dir = tmp_path / "proc"
        proc_dir.mkdir()
        pid_dir = proc_dir / "123"
        pid_dir.mkdir()
        (pid_dir / "stat").write_text("invalid stat format without paren")

        class MockStat:
            st_uid = os.getuid()

        orig_open = open
        monkeypatch.setattr("os.listdir", lambda path: ["123"] if path == "/proc" else [])
        monkeypatch.setattr("os.stat", lambda p: MockStat())
        monkeypatch.setattr("builtins.open", lambda p, *args, **kwargs: orig_open(str(p).replace("/proc", str(proc_dir)), *args, **kwargs))

        # Linux get_identity fails closed on malformed stat
        with pytest.raises(InspectionError):
            adapter.get_identity(123)

        # 2. Malformed non-integer starttime field
        (pid_dir / "stat").write_text("123 (mock) S 1 123 123 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 not_an_int 0 0 0 0")
        with pytest.raises(InspectionError):
            adapter.get_identity(123)

        with pytest.raises(InspectionError):
            adapter.enumerate_candidates("cap")

        # 3. Linux enumerate_candidates fail closed on permission uncertainty on same UID
        monkeypatch.setattr(os, "kill", lambda pid, sig: None)  # Same UID living process

        def perm_error_stat(p):
            raise PermissionError("restricted proc")
        monkeypatch.setattr(os, "stat", perm_error_stat)

        with pytest.raises(InspectionError):
            adapter.enumerate_candidates("cap")

    def test_birth_marker_numeric_comparison_across_digit_boundaries(self) -> None:
        from review_process_supervisor import (
            parse_birth_marker,
            compare_birth_markers,
            ProcessSupervisor,
            ScriptedAdapter,
            ProcessIdentity,
            CandidateInfo,
            InspectionError,
        )

        # 1. Numeric vs lexicographical ordering: 100 > 99
        assert compare_birth_markers("100", "99") > 0
        assert compare_birth_markers("100.000000", "99.999999") > 0
        assert compare_birth_markers("100.000001", "100.000000") > 0
        assert compare_birth_markers("100.000000", "100.000000") == 0
        assert compare_birth_markers("99.999999", "100.000000") < 0

        # Malformed birth markers fail closed
        with pytest.raises(InspectionError):
            parse_birth_marker("not_an_int")
        with pytest.raises(InspectionError):
            parse_birth_marker("")

        # 2. Ledger admittance across numeric digit boundary
        adapter = ScriptedAdapter()
        sup = ProcessSupervisor(timeout_seconds=5.0, command=["mock"], adapter=adapter)

        # Root has birth "99", child has birth "100" (born after launch)
        root_ident = adapter.register_process(100, 1, 100, "99", has_capability=True)
        adapter.processes[101] = CandidateInfo(
            pid=101,
            ppid=100,
            pgid=100,
            birth_marker="100",
            is_zombie=False,
            has_capability=False,  # relies on parent ancestry proof
        )
        adapter.identities[101] = ProcessIdentity(101, "100")
        adapter.alive.add(101)

        sup.root_identity = root_ident
        sup.root_pgid = 100
        sup.ledger[root_ident] = root_ident

        sup._refresh_ledger()

        child_ident = ProcessIdentity(101, "100")
        assert child_ident in sup.ledger  # Successfully admitted because 100 >= 99 numerically

    def test_process_identity_pid_reuse_tracking_in_ledger(self) -> None:
        from review_process_supervisor import (
            ProcessSupervisor,
            ScriptedAdapter,
            ProcessIdentity,
            CandidateInfo,
        )

        adapter = ScriptedAdapter()
        sup = ProcessSupervisor(timeout_seconds=5.0, command=["mock"], adapter=adapter)

        # Register initial root (100) and child (101, birth="1000.0")
        root_ident = adapter.register_process(100, 1, 100, "100.0", has_capability=True)
        child1_ident = adapter.register_process(101, 100, 100, "1000.0", has_capability=True)

        sup.root_identity = root_ident
        sup.root_pgid = 100
        sup.ledger[root_ident] = root_ident
        sup.ledger[child1_ident] = child1_ident

        assert child1_ident in sup.ledger

        # Now simulate child1 exiting, and a new process (child2) recycling PID 101 with birth="2000.0"
        adapter.alive.remove(101)  # child1 is dead
        adapter.identities[101] = ProcessIdentity(101, "2000.0")
        adapter.processes[101] = CandidateInfo(
            pid=101,
            ppid=100,
            pgid=100,
            birth_marker="2000.0",
            is_zombie=False,
            has_capability=True,
        )
        adapter.alive.add(101)  # child2 is alive

        # Refresh ledger: should retire old (101, "1000.0") and admit new (101, "2000.0")
        sup._refresh_ledger()

        child2_ident = ProcessIdentity(101, "2000.0")
        assert child1_ident not in sup.ledger
        assert child2_ident in sup.ledger
        assert sup.ledger[child2_ident] == child2_ident

    def test_production_sigchld_poll_leader_deadline_arbitration(self, monkeypatch) -> None:
        import os
        from review_process_supervisor import ProcessSupervisor, ScriptedClock

        clock = ScriptedClock(start=100.0)
        sup = ProcessSupervisor(
            timeout_seconds=5.0,
            command=["mock_cmd"],
            clock=clock,
            wait_event_fn=None,  # Exercise real production _poll_leader
        )
        sup.start_time = 100.0
        sup.deadline = 105.0

        # 1. SIGCHLD arrived at 104.0 (before deadline 105.0), queuing (status=0, event_time=104.0)
        sup.observed_events.append((0, 104.0))
        clock._now = 106.0  # Poll executed after deadline
        waited_pid, status, event_time = sup._poll_leader(1234, os.WNOHANG)
        assert waited_pid == 1234
        assert event_time == 104.0  # Uses exact observed timestamp!

        rc = sup.classify_outcome(
            leader_completion_time=event_time,
            child_status=0,
            timed_out=False,
            cleanup_ok=True,
        )
        assert rc == 0  # Not 124 timeout!

        # 2. When observed_events is empty, _poll_leader calls _drain_wait_events directly
        def mock_waitpid_single(pid, flags):
            return (pid, 0)
        monkeypatch.setattr(os, "waitpid", mock_waitpid_single)
        clock._now = 104.5
        waited_pid, status, event_time = sup._poll_leader(1234, os.WNOHANG)
        assert waited_pid == 1234
        assert status == 0
        assert event_time == 104.5

    def test_coalesced_sigchld_notification_draining_and_pairing(self, monkeypatch) -> None:
        import os
        from review_process_supervisor import ProcessSupervisor, ScriptedClock

        clock = ScriptedClock(start=100.0)
        sup = ProcessSupervisor(
            timeout_seconds=5.0,
            command=["mock_cmd"],
            clock=clock,
            wait_event_fn=None,
        )
        sup.start_time = 100.0
        sup.deadline = 105.0

        # Simulate waitpid sequence where multiple state changes occurred across distinct timestamps:
        # Event 1: STOP (0x7F) at clock 101.0
        # Event 2: CONT (0xFFFF) at clock 102.0
        # Event 3: EXIT 0 (0) at clock 103.5
        # Event 4: 0 (no more events)
        statuses_and_times = [(1234, 0x7F, 101.0), (1234, 0xFFFF, 102.0), (1234, 0, 103.5), (0, 0, 103.5)]
        call_idx = 0

        def mock_waitpid_coalesced(pid, flags):
            nonlocal call_idx
            wpid, st, t = statuses_and_times[call_idx]
            call_idx += 1
            clock._now = t
            return (wpid, st)

        monkeypatch.setattr(os, "waitpid", mock_waitpid_coalesced)

        # Call production _drain_wait_events
        sup._drain_wait_events(1234, os.WNOHANG)

        assert len(sup.observed_events) == 3
        # Each reaped status has its exact reaped observation timestamp
        assert sup.observed_events[0] == (0x7F, 101.0)
        assert sup.observed_events[1] == (0xFFFF, 102.0)
        assert sup.observed_events[2] == (0, 103.5)

        # Now simulate polling loop executing later, past the deadline at 107.0
        clock._now = 107.0

        # Poll 1: STOP
        wpid, st1, t1 = sup._poll_leader(1234, os.WNOHANG)
        assert os.WIFSTOPPED(st1)
        assert t1 == 101.0

        # Poll 2: CONT
        wpid, st2, t2 = sup._poll_leader(1234, os.WNOHANG)
        assert st2 == 0xFFFF
        assert t2 == 102.0

        # Poll 3: EXIT 0
        wpid, st3, t3 = sup._poll_leader(1234, os.WNOHANG)
        assert os.WIFEXITED(st3)
        assert t3 == 103.5  # Paired with exact observation 103.5, NOT 107.0!

        # Classify outcome: completion was at 103.5 <= deadline 105.0 -> Exit status 0
        rc = sup.classify_outcome(
            leader_completion_time=t3,
            child_status=os.WEXITSTATUS(st3),
            timed_out=False,
            cleanup_ok=True,
        )
        assert rc == 0

    def test_coalesced_wait_pre_deadline_terminal_event_consumed_post_deadline_in_run(self, monkeypatch) -> None:
        import os
        import sys
        from review_process_supervisor import ProcessSupervisor, ScriptedClock

        clock = ScriptedClock(start=100.0)
        sup = ProcessSupervisor(
            timeout_seconds=5.0,
            command=[sys.executable, "-c", "import sys; sys.exit(0)"],
            clock=clock,
        )

        # Preload observed_events with:
        # 1. Non-terminal STOP (0x7F at 101.0)
        # 2. Terminal EXIT 0 (0 at 104.0, observed before deadline 105.0)
        # and mark terminal_reaped = True.
        sup.observed_events.append((0x7F, 101.0))
        sup.observed_events.append((0, 104.0))
        sup.terminal_reaped = True

        post_deadline_drain_called = False

        def mock_waitpid_post_deadline(pid_arg, flags):
            nonlocal post_deadline_drain_called
            post_deadline_drain_called = True
            # Subprocess already exited/reaped earlier, so post-deadline waitpid raises ChildProcessError / ECHILD
            raise ChildProcessError("No child processes")

        monkeypatch.setattr(os, "waitpid", mock_waitpid_post_deadline)
        monkeypatch.setattr(sup, "_cleanup", lambda leader_pid=None: True)

        # In run(), first poll consumes STOP at 101.0.
        # After consuming STOP, advance monotonic clock past deadline to 108.0.
        original_poll_leader = sup._poll_leader

        def mock_poll_leader(pid, flags):
            wpid, st, t = original_poll_leader(pid, flags)
            if os.WIFSTOPPED(st):
                clock._now = 108.0  # Monotonically advance to 108.0 past 105.0 deadline
            return wpid, st, t

        monkeypatch.setattr(sup, "_poll_leader", mock_poll_leader)

        rc = sup.run()
        assert post_deadline_drain_called is True
        assert clock.monotonic() >= 108.0
        assert sup.supervision_error is False
        # Leader completed at pre-deadline timestamp 104.0 <= 105.0 -> Retains exit code 0!
        assert rc == 0

    def test_empty_queue_echild_sets_supervision_error_returns_125(self, monkeypatch) -> None:
        import os
        import sys
        from review_process_supervisor import (
            ProcessSupervisor,
            ScriptedClock,
            SUPERVISOR_ERROR_RC,
        )

        clock = ScriptedClock(start=100.0)
        sup = ProcessSupervisor(
            timeout_seconds=5.0,
            command=[sys.executable, "-c", "import sys; sys.exit(0)"],
            clock=clock,
        )

        def mock_waitpid_echild(pid_arg, flags):
            raise ChildProcessError("No child processes")

        monkeypatch.setattr(os, "waitpid", mock_waitpid_echild)
        monkeypatch.setattr(sup, "_cleanup", lambda leader_pid=None: True)

        rc = sup.run()
        assert sup.supervision_error is True
        assert rc == SUPERVISOR_ERROR_RC  # Returns 125, not 124!

    def test_child_process_error_recovery_with_queued_terminal_event(self, monkeypatch) -> None:
        import os
        import sys
        from review_process_supervisor import ProcessSupervisor, ScriptedClock

        clock = ScriptedClock(start=100.0)
        sup = ProcessSupervisor(
            timeout_seconds=5.0,
            command=[sys.executable, "-c", "import sys; sys.exit(0)"],
            clock=clock,
        )

        # Drive run() into a state where:
        # 1. Non-terminal STOP (0x7F at 101.0) and pre-deadline terminal EXIT 0 (0 at 102.0) are queued in observed_events.
        # 2. In run(), first _poll_leader consumes STOP.
        # 3. Before next poll, waitpid raises ChildProcessError (e.g. process wait ownership lost).
        # 4. _poll_leader raises ChildProcessError on the second poll.
        # 5. run()'s except ChildProcessError recovers and drains observed_events, finding the queued EXIT 0.
        # 6. run() returns child exit status 0, and supervision_error remains False!
        sup.observed_events.append((0x7F, 101.0))  # STOP
        sup.observed_events.append((0, 102.0))     # EXIT 0
        sup.terminal_reaped = True

        echild_reached = False

        def mock_waitpid_raise(pid_arg, flags):
            nonlocal echild_reached
            echild_reached = True
            raise ChildProcessError("No child processes")

        monkeypatch.setattr(os, "waitpid", mock_waitpid_raise)
        monkeypatch.setattr(sup, "_cleanup", lambda leader_pid=None: True)

        # When STOP is polled, queue still has EXIT 0. On next poll, force ChildProcessError from _poll_leader
        poll_count = 0
        original_poll_leader = sup._poll_leader

        def mock_poll_leader_with_echild(pid, flags):
            nonlocal poll_count, echild_reached
            poll_count += 1
            if poll_count == 1:
                return original_poll_leader(pid, flags)  # returns STOP
            echild_reached = True
            raise ChildProcessError("Lost wait ownership")

        monkeypatch.setattr(sup, "_poll_leader", mock_poll_leader_with_echild)

        rc = sup.run()
        assert echild_reached is True
        # Queued terminal event reaped before ECHILD -> Returns child status 0, not 125
        assert sup.supervision_error is False
        assert rc == 0

    def test_state_machine_with_scripted_wait_events(self) -> None:
        import os
        import sys
        from review_process_supervisor import (
            ProcessSupervisor,
            ScriptedClock,
            REVIEW_TIMEOUT_RC,
        )

        # Case A: Stop at 101.0, Continue at 102.0, Exit 0 at 104.0 (before deadline 105.0)
        # Polled at 106.0 -> Retains success 0!
        clock_a = ScriptedClock(start=100.0)
        events_a = [
            (None, os.WNOHANG | os.WUNTRACED, 101.0, lambda pid: (pid, 0x7F | (19 << 8))),  # STOP (SIGSTOP=19)
            (None, os.WNOHANG | os.WUNTRACED, 102.0, lambda pid: (pid, 0xFFFF)),  # CONT
            (None, os.WNOHANG | os.WUNTRACED, 104.0, lambda pid: (pid, 0)),  # Exit 0
        ]

        def wait_event_fn_a(pid: int, flags: int) -> tuple[int, int, float]:
            if events_a:
                _, _, t, fn = events_a.pop(0)
                clock_a._now = max(clock_a._now, t)
                wpid, st = fn(pid)
                return wpid, st, t
            return 0, 0, clock_a.monotonic()

        sup_a = ProcessSupervisor(
            timeout_seconds=5.0,
            command=[sys.executable, "-c", "import sys; sys.exit(0)"],
            clock=clock_a,
            wait_event_fn=wait_event_fn_a,
        )
        rc_a = sup_a.run()
        assert rc_a == 0

        # Case B: Stop at 101.0, Continue at 102.0, Exit 0 at 106.0 (after deadline 105.0)
        # -> Returns 124 timeout!
        clock_b = ScriptedClock(start=100.0)
        events_b = [
            (None, os.WNOHANG | os.WUNTRACED, 101.0, lambda pid: (pid, 0x7F | (19 << 8))),  # STOP
            (None, os.WNOHANG | os.WUNTRACED, 102.0, lambda pid: (pid, 0xFFFF)),  # CONT
            (None, os.WNOHANG | os.WUNTRACED, 106.0, lambda pid: (pid, 0)),  # Exit 0 at 106.0
        ]

        def wait_event_fn_b(pid: int, flags: int) -> tuple[int, int, float]:
            if events_b:
                _, _, t, fn = events_b.pop(0)
                clock_b._now = max(clock_b._now, t)
                wpid, st = fn(pid)
                return wpid, st, t
            clock_b._now += 1.0
            return 0, 0, clock_b.monotonic()

        sup_b = ProcessSupervisor(
            timeout_seconds=5.0,
            command=[sys.executable, "-c", "import sys; sys.exit(0)"],
            clock=clock_b,
            wait_event_fn=wait_event_fn_b,
        )
        rc_b = sup_b.run()
        assert rc_b == REVIEW_TIMEOUT_RC

    def test_sigchld_stop_continue_terminal_sequence(self) -> None:
        import os
        import signal
        import sys
        import time
        from review_process_supervisor import ProcessSupervisor

        cmd = [
            sys.executable,
            "-c",
            "import os, signal, sys; os.kill(os.getpid(), signal.SIGSTOP); sys.exit(0)",
        ]
        sup = ProcessSupervisor(timeout_seconds=5.0, command=cmd)

        import threading
        def wake_child():
            for _ in range(500):
                time.sleep(0.01)
                if sup.root_identity is not None:
                    pid = sup.root_identity.pid
                    for _ in range(200):
                        time.sleep(0.02)
                        try:
                            os.kill(pid, signal.SIGCONT)
                        except OSError:
                            break
                    break

        t = threading.Thread(target=wake_child, daemon=True)
        t.start()
        rc = sup.run()
        t.join(timeout=2.0)
        assert rc == 0

        # Outcome classification logic with deadline arbitration
        sup_class = ProcessSupervisor(timeout_seconds=10.0, command=["cmd"])
        sup_class.start_time = 100.0
        sup_class.deadline = 110.0

        # 1. Normal completion before deadline
        rc = sup_class.classify_outcome(
            leader_completion_time=105.0,
            child_status=0,
            timed_out=False,
            cleanup_ok=True,
        )
        assert rc == 0

        # 2. Leader completion after deadline returns 124
        rc_timeout = sup_class.classify_outcome(
            leader_completion_time=115.0,
            child_status=0,
            timed_out=False,
            cleanup_ok=True,
        )
        assert rc_timeout == 124

        # 3. Timeout without leader completion returns 124
        rc_timed_out = sup_class.classify_outcome(
            leader_completion_time=None,
            child_status=None,
            timed_out=True,
            cleanup_ok=True,
        )
        assert rc_timed_out == 124

    def test_darwin_proc_listallpids_nonpositive_raises_inspection_error(self, monkeypatch: pytest.MonkeyPatch) -> None:
        import sys
        if sys.platform != "darwin":
            pytest.skip("Darwin-specific test")
        from review_process_supervisor import DarwinMembershipAdapter, InspectionError
        adapter = DarwinMembershipAdapter()

        # Mock proc_listallpids returning 0 with errno 0 (must raise InspectionError, not return [])
        def mock_proc_listallpids_zero(buf, bufsz):
            import ctypes
            ctypes.set_errno(0)
            return 0

        monkeypatch.setattr(adapter.libproc, "proc_listallpids", mock_proc_listallpids_zero)
        with pytest.raises(InspectionError, match="proc_listallpids count failed"):
            adapter.enumerate_candidates("test_cap")

    def test_scripted_adapter_docstrings_and_throwing_contracts(self) -> None:
        from review_process_supervisor import ScriptedAdapter, InspectionError, ProcessIdentity
        adapter = ScriptedAdapter()

        # Check docstrings on all methods
        for method_name in ["register_process", "get_identity", "enumerate_candidates", "is_alive", "is_pgid_alive", "signal_identity", "signal_pgid"]:
            method = getattr(adapter, method_name)
            assert method.__doc__ is not None, f"Missing docstring on {method_name}"
            assert "Returns:" in method.__doc__, f"Missing Returns: section in {method_name}"

        # Check throwing contracts
        adapter.fail_inspection_pids.add(100)
        with pytest.raises(InspectionError):
            adapter.get_identity(100)

        with pytest.raises(InspectionError):
            adapter.is_alive(ProcessIdentity(100, "1.0"))

        with pytest.raises(InspectionError):
            adapter.signal_identity(ProcessIdentity(100, "1.0"), 15)

        adapter.fail_candidate_discovery = True
        with pytest.raises(InspectionError):
            adapter.enumerate_candidates("cap")

    def test_drain_wait_events_reentrancy_and_indeterminate_errors(self, monkeypatch: pytest.MonkeyPatch) -> None:
        import errno
        import os
        from review_process_supervisor import ProcessSupervisor, ScriptedClock

        clock = ScriptedClock(start=100.0)
        sup = ProcessSupervisor(timeout_seconds=5.0, command=["mock"], clock=clock)

        # Test re-entrancy guard
        sup._in_drain = True
        sup._drain_wait_events(1234, 0)
        assert len(sup.observed_events) == 0
        sup._in_drain = False

        # Test unexpected OSError (e.g. EINVAL) sets supervision_error
        def mock_waitpid_error(pid, flags):
            raise OSError(errno.EINVAL, "Invalid argument")

        monkeypatch.setattr(os, "waitpid", mock_waitpid_error)
        sup._drain_wait_events(1234, 0)
        assert sup.supervision_error is True

    def test_darwin_procargs_zero_length_on_living_candidate_raises_inspection_error(self, monkeypatch: pytest.MonkeyPatch) -> None:
        import os
        import sys
        if sys.platform != "darwin":
            pytest.skip("Darwin-specific test")
        import ctypes
        from review_process_supervisor import DarwinMembershipAdapter, InspectionError, ProcessSupervisor, SUPERVISOR_ERROR_RC

        adapter = DarwinMembershipAdapter()
        # Mock sysctl returning 0 with size 0 repeatedly
        def mock_sysctl_zero(mib, mib_len, oldp, oldlenp, newp, newlen):
            if oldlenp:
                sz = ctypes.cast(oldlenp, ctypes.POINTER(ctypes.c_size_t))
                sz.contents.value = 0
            return 0

        monkeypatch.setattr(adapter.libc, "sysctl", mock_sysctl_zero)
        # Mock living process
        class MockBsdInfo:
            pbi_status = 2  # Non-zombie
            pbi_start_tvsec = 1000
            pbi_start_tvusec = 500000

        monkeypatch.setattr(adapter, "_get_bsdinfo", lambda pid: MockBsdInfo())
        monkeypatch.setattr(adapter, "_is_other_user_or_zombie", lambda pid, my_uid: False)
        monkeypatch.setattr(os, "kill", lambda pid, sig: None)

        with pytest.raises(InspectionError, match="returned zero-length buffer for living candidate"):
            adapter._has_capability(1234, b"CAP=123")

        # Verify supervisor cleanup / run outcome with InspectionError returns 125
        sup = ProcessSupervisor(timeout_seconds=5.0, command=["mock"], adapter=adapter)
        sup.capability = "mock_token"
        cleanup_ok = sup._cleanup(leader_pid=1234)
        assert cleanup_ok is False
        assert sup.supervision_error is True
        rc = sup.classify_outcome(
            leader_completion_time=100.0,
            child_status=0,
            timed_out=False,
            cleanup_ok=False,
        )
        assert rc == SUPERVISOR_ERROR_RC

    def test_linux_proc_stat_permission_error_without_uid_proof_raises_inspection_error(self, monkeypatch: pytest.MonkeyPatch) -> None:
        import os
        from review_process_supervisor import LinuxMembershipAdapter, InspectionError, ProcessSupervisor, SUPERVISOR_ERROR_RC

        adapter = LinuxMembershipAdapter()
        monkeypatch.setattr(os, "listdir", lambda path: ["1234"] if path == "/proc" else [])

        def mock_stat_perm(path):
            if path == "/proc/1234":
                raise PermissionError("Permission denied")
            raise FileNotFoundError()

        monkeypatch.setattr(os, "stat", mock_stat_perm)
        # kill(1234, 0) does not raise ProcessLookupError (process is alive)
        monkeypatch.setattr(os, "kill", lambda pid, sig: None)

        with pytest.raises(InspectionError, match="permission denied on /proc/1234 without definitive UID proof"):
            adapter.enumerate_candidates("test_cap")

        # Supervisor cleanup with this failure returns cleanup_ok = False and rc = 125
        sup = ProcessSupervisor(timeout_seconds=5.0, command=["mock"], adapter=adapter)
        sup.capability = "test_cap"
        cleanup_ok = sup._cleanup(leader_pid=1234)
        assert cleanup_ok is False
        assert sup.supervision_error is True
        rc = sup.classify_outcome(
            leader_completion_time=100.0,
            child_status=0,
            timed_out=False,
            cleanup_ok=False,
        )
        assert rc == SUPERVISOR_ERROR_RC

    def test_drain_wait_events_nested_reentrancy_order_pairing(self, monkeypatch: pytest.MonkeyPatch) -> None:
        import os
        from review_process_supervisor import ProcessSupervisor, ScriptedClock

        clock = ScriptedClock(start=100.0)
        sup = ProcessSupervisor(timeout_seconds=5.0, command=["mock"], clock=clock)

        drain_calls = 0
        def mock_waitpid_nested(pid, flags):
            nonlocal drain_calls
            drain_calls += 1
            if drain_calls == 1:
                # Trigger a nested drain call (e.g. from signal handler or hook)
                sup._drain_wait_events(pid, flags)
                clock._now = 101.0
                return (pid, 0x7F)  # STOP
            elif drain_calls == 2:
                clock._now = 102.0
                return (pid, 0xFFFF)  # CONT
            elif drain_calls == 3:
                clock._now = 103.0
                return (pid, 0)  # EXIT 0
            return (0, 0)

        monkeypatch.setattr(os, "waitpid", mock_waitpid_nested)
        sup._drain_wait_events(1234, 0)

        # Ensure ordered 1-to-1 status/timestamp pairing without duplicates or loss
        assert len(sup.observed_events) == 3
        assert sup.observed_events[0] == (0x7F, 101.0)
        assert sup.observed_events[1] == (0xFFFF, 102.0)
        assert sup.observed_events[2] == (0, 103.0)

    def test_timeout_validation_rejects_non_finite_and_non_positive(self) -> None:
        from review_process_supervisor import ProcessSupervisor, SUPERVISOR_ERROR_RC
        import subprocess
        import sys

        for bad_val in (float("nan"), float("inf"), float("-inf"), 0.0, -1.0, -100.0):
            with pytest.raises(ValueError, match="timeout_seconds must be a positive finite number"):
                ProcessSupervisor(timeout_seconds=bad_val, command=["echo", "hi"])

        # Also test CLI rejection
        for bad_cli in ("nan", "inf", "-inf", "0", "-5", "abc"):
            res = subprocess.run(
                [sys.executable, str(CI_DIR / "review_process_supervisor.py"), "run", bad_cli, "echo", "hi"],
                capture_output=True,
                text=True,
            )
            assert res.returncode == SUPERVISOR_ERROR_RC

    def test_darwin_adapter_rejects_partial_identity_records(self, monkeypatch: pytest.MonkeyPatch) -> None:
        import os
        import sys
        if sys.platform != "darwin":
            pytest.skip("Darwin-specific test")
        from review_process_supervisor import DarwinMembershipAdapter, InspectionError

        adapter = DarwinMembershipAdapter()

        # Mock proc_pidinfo returning partial size for BSDINFO (less than sizeof(proc_bsdinfo))
        def mock_partial_bsdinfo(pid, flavor, arg, ptr, sz):
            if flavor == adapter.PROC_PIDT_BSDINFO:
                return sz - 10  # Partial record
            return sz

        monkeypatch.setattr(adapter.libproc, "proc_pidinfo", mock_partial_bsdinfo)
        with pytest.raises(InspectionError, match="returned partial size"):
            adapter._get_bsdinfo(1234)

        # Mock proc_pidinfo returning partial size for BSHORTINFO
        def mock_partial_bshortinfo(pid, flavor, arg, ptr, sz):
            if flavor == adapter.PROC_PIDT_BSHORTINFO:
                return sz - 5  # Partial record
            return 0

        monkeypatch.setattr(adapter.libproc, "proc_pidinfo", mock_partial_bshortinfo)
        monkeypatch.setattr(os, "kill", lambda pid, sig: None)
        with pytest.raises(InspectionError, match="returned partial size"):
            adapter._is_other_user_or_zombie(1234, 501)

    def test_linux_adapter_pidfd_signaling_production_coverage(self, monkeypatch: pytest.MonkeyPatch) -> None:
        import os
        import signal
        from review_process_supervisor import LinuxMembershipAdapter, InspectionError, ProcessIdentity

        adapter = LinuxMembershipAdapter()
        target = ProcessIdentity(1234, "100.000000")

        # 1. When pidfd APIs are unavailable -> raises InspectionError
        monkeypatch.delattr(os, "pidfd_open", raising=False)
        with pytest.raises(InspectionError, match="Linux atomic pidfd signaling is unavailable"):
            adapter.signal_identity(target, signal.SIGTERM)

        # Restore simulated pidfd APIs
        monkeypatch.setattr(os, "pidfd_open", lambda pid, flags: 99, raising=False)
        monkeypatch.setattr(os, "close", lambda fd: None)

        signalled = []
        monkeypatch.setattr(signal, "pidfd_send_signal", lambda fd, sig: signalled.append((fd, sig)), raising=False)

        # 2. Post-open get_identity returns None (process dead) -> returns True without signaling
        monkeypatch.setattr(adapter, "get_identity", lambda pid: None)
        assert adapter.signal_identity(target, signal.SIGTERM) is True
        assert len(signalled) == 0

        # 3. Post-open get_identity returns mismatched identity (recycled PID) -> returns True without signaling
        recycled = ProcessIdentity(1234, "200.000000")
        monkeypatch.setattr(adapter, "get_identity", lambda pid: recycled)
        assert adapter.signal_identity(target, signal.SIGTERM) is True
        assert len(signalled) == 0

        # 4. Post-open get_identity returns matching identity -> signals via pidfd_send_signal
        monkeypatch.setattr(adapter, "get_identity", lambda pid: target)
        assert adapter.signal_identity(target, signal.SIGTERM) is True
        assert signalled == [(99, signal.SIGTERM)]


    def test_linux_environ_eacces_after_ownership_flip_is_skipped_not_fatal(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """EACCES on environ is a TOCTOU with the same-UID filter, not uncertainty.

        On Linux a same-UID process that execs a setuid/file-capability binary
        becomes non-dumpable: its /proc/<pid> flips to root ownership and
        environ reads return EACCES. The pre-read ``st_uid`` filter already
        skips such processes; a process that flips BETWEEN that stat and the
        environ read used to escape the filter and turn an unrelated runner
        process into a 125 for a leader that exited normally (CI run
        35730245781: ``rc=125`` instead of ``rc=3``). A fresh stat must settle
        it: gone or no longer ours is skipped; still ours stays fail-closed.
        """
        import builtins
        import io
        import os
        from review_process_supervisor import InspectionError, LinuxMembershipAdapter

        my_uid = os.getuid()
        fields = ["S", "1", "4242", "4242"] + ["0"] * 15 + ["5000", "0", "0"]
        stat_line = "4242 (sudo) " + " ".join(fields)

        orig_open = builtins.open
        orig_stat = os.stat

        def fake_open(path, *args, **kwargs):
            if str(path) == "/proc/4242/stat":
                return io.StringIO(stat_line)
            if str(path) == "/proc/4242/environ":
                raise PermissionError(13, "Permission denied", str(path))
            return orig_open(path, *args, **kwargs)

        def run_with_restat(restat):
            calls = {"n": 0}

            def fake_stat(path, *args, **kwargs):
                if str(path) != "/proc/4242":
                    return orig_stat(path, *args, **kwargs)
                calls["n"] += 1
                if calls["n"] == 1:
                    return os.stat_result((0o555, 0, 0, 0, my_uid, 0, 0, 0, 0, 0))
                return restat()

            monkeypatch.setattr(os, "stat", fake_stat)
            return LinuxMembershipAdapter().enumerate_candidates("cap", min_birth_marker="1000")

        monkeypatch.setattr(os, "listdir", lambda p: ["4242"] if p == "/proc" else [])
        monkeypatch.setattr(builtins, "open", fake_open)

        # 1. Ownership flipped to root after the first stat -> skipped, no raise.
        def flipped():
            return os.stat_result((0o555, 0, 0, 0, 0, 0, 0, 0, 0, 0))

        assert run_with_restat(flipped) == []

        # 2. Process vanished between the environ read and the re-stat -> skipped.
        def vanished():
            raise FileNotFoundError(2, "No such file or directory", "/proc/4242")

        assert run_with_restat(vanished) == []

        # 3. Still same-UID yet unreadable -> genuine uncertainty, still fails closed.
        def same():
            return os.stat_result((0o555, 0, 0, 0, my_uid, 0, 0, 0, 0, 0))

        with pytest.raises(InspectionError, match="environ"):
            run_with_restat(same)
