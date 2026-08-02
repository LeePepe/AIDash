"""Hermetic unit tests for the AIDash push path (effectful half of aidash.py).

No test launches the real app or shells out to a real aidash — the runner,
opener, and pgrep are all fakes. The real-app path is a single skippable
@pytest.mark.integration test.
"""

import pytest

from L5_apps.digest.aidash import (
    Briefing, Container, Card, PushResult,
    resolve_aidash_bin, resolve_aidash_app,
    ensure_app_running, ensure_xpc_ready, push_briefing,
)

BRIEFING = Briefing(
    "2026-07-10", "aidata-digest",
    (Container("11111111-0710-0001-0000-000000000001", "总览", 10,
               (Card("22222222-0710-0001-0000-000000000001", "digest", "hero",
                     {"title": "t", "body": "b"}, style="accent"),),
               layout="auto", style="accent"),),
)


class FakeRunner:
    """Records argv lists; returns configured returncode, or raises."""

    def __init__(self, returncode=0, raise_exc=None):
        self.calls: list[list[str]] = []
        self._rc = returncode
        self._raise = raise_exc

    def __call__(self, argv, **kw):
        self.calls.append(list(argv))
        if self._raise is not None:
            raise self._raise
        return self._rc


def _up_pgrep(_):
    return True


def _down_pgrep(_):
    return False


def _noop_opener():
    return None


def _healthy_probe(_bin):
    """XPC round-trip succeeds."""
    return True


def _dead_probe(_bin):
    """Process may be up, but XPC never answers."""
    return False


class RecordingSink:
    """Captures loud-failure reasons instead of writing the error log."""

    def __init__(self):
        self.reasons: list[str] = []

    def __call__(self, reason: str) -> None:
        self.reasons.append(reason)


def _noop_sink(_reason):
    return None


# --- resolve_aidash_bin ----------------------------------------------------
@pytest.mark.unit
def test_resolve_bin_none_when_glob_empty():
    # No fixed install, empty DerivedData glob → None.
    assert resolve_aidash_bin(globber=lambda pat: [],
                              exists=lambda p: False) is None


@pytest.mark.unit
def test_resolve_bin_picks_newest():
    got = resolve_aidash_bin(
        globber=lambda pat: ["/a/aidash", "/b/aidash"],
        mtime=lambda p: {"/a/aidash": 1.0, "/b/aidash": 2.0}[p],
        exists=lambda p: False,  # no fixed install → fall back to glob
    )
    assert got == "/b/aidash"


@pytest.mark.unit
def test_resolve_bin_prefers_fixed_when_present():
    """The fixed ~/.local/bin/aidash wins over any DerivedData build."""
    from L5_apps.digest.aidash import AIDASH_BIN_FIXED
    got = resolve_aidash_bin(
        globber=lambda pat: ["/dd/aidash"],  # DerivedData also present…
        mtime=lambda p: 9.0,
        exists=lambda p: p == AIDASH_BIN_FIXED,  # …but fixed exists
    )
    assert got == AIDASH_BIN_FIXED


@pytest.mark.unit
def test_resolve_bin_falls_back_to_glob_when_no_fixed():
    """No fixed install → newest DerivedData build (dev-box compatibility)."""
    got = resolve_aidash_bin(
        globber=lambda pat: ["/dd/aidash"],
        mtime=lambda p: 1.0,
        exists=lambda p: False,
    )
    assert got == "/dd/aidash"


# --- resolve_aidash_app ----------------------------------------------------
@pytest.mark.unit
def test_resolve_app_prefers_fixed_when_present():
    """The fixed /Applications/AIDash.app wins over any DerivedData bundle."""
    from L5_apps.digest.aidash import AIDASH_APP_FIXED
    got = resolve_aidash_app(
        globber=lambda pat: ["/dd/AIDash.app"],
        mtime=lambda p: 9.0,
        exists=lambda p: p == AIDASH_APP_FIXED,
    )
    assert got == AIDASH_APP_FIXED


@pytest.mark.unit
def test_resolve_app_falls_back_to_glob_when_no_fixed():
    """No fixed install → newest DerivedData bundle."""
    got = resolve_aidash_app(
        globber=lambda pat: ["/dd/a.app", "/dd/b.app"],
        mtime=lambda p: {"/dd/a.app": 1.0, "/dd/b.app": 2.0}[p],
        exists=lambda p: False,
    )
    assert got == "/dd/b.app"


@pytest.mark.unit
def test_resolve_app_none_when_nothing_present():
    assert resolve_aidash_app(globber=lambda pat: [],
                              exists=lambda p: False) is None


# --- ensure_app_running ----------------------------------------------------
@pytest.mark.unit
def test_ensure_app_running_true_when_pgrep_hits():
    assert ensure_app_running(opener=_noop_opener, pgrep=_up_pgrep,
                              poll_s=0.0, attempts=2) is True


@pytest.mark.unit
def test_ensure_app_running_false_when_never_up():
    assert ensure_app_running(opener=_noop_opener, pgrep=_down_pgrep,
                              poll_s=0.0, attempts=2) is False


# --- push_briefing: happy + every failure mode -----------------------------
@pytest.mark.unit
def test_push_happy_path_publishes():
    runner = FakeRunner(returncode=0)
    res = push_briefing(BRIEFING, bin_path="/x/aidash", runner=runner,
                        opener=_noop_opener, pgrep=_up_pgrep,
                        probe=_healthy_probe, failure_sink=_noop_sink,
                        poll_s=0.0, attempts=1)
    assert res.ok and res.published
    # order: briefing put, container put, card put, briefing publish
    kinds = [c[1:3] for c in runner.calls]
    assert ["briefing", "put"] in kinds
    assert ["container", "put"] in kinds
    assert ["card", "put"] in kinds
    assert ["briefing", "publish"] == kinds[-1]


@pytest.mark.unit
def test_push_skipped_when_bin_missing():
    runner = FakeRunner()
    sink = RecordingSink()
    res = push_briefing(BRIEFING, bin_path=None, runner=runner,
                        opener=_noop_opener, pgrep=_up_pgrep,
                        probe=_healthy_probe, failure_sink=sink)
    assert not res.ok
    assert "cli" in res.reason.lower() or "bin" in res.reason.lower()
    assert runner.calls == []  # nothing shelled out
    assert sink.reasons  # loud: recorded, not silent


@pytest.mark.unit
def test_push_skipped_when_app_not_running():
    runner = FakeRunner()
    sink = RecordingSink()
    res = push_briefing(BRIEFING, bin_path="/x/aidash", runner=runner,
                        opener=_noop_opener, pgrep=_down_pgrep,
                        probe=_healthy_probe, failure_sink=sink,
                        poll_s=0.0, attempts=1)
    assert not res.ok
    assert "app" in res.reason.lower()
    assert runner.calls == []
    assert sink.reasons


@pytest.mark.unit
def test_push_fails_on_nonzero_exit_xpc():
    runner = FakeRunner(returncode=2)  # XPC transport failed
    res = push_briefing(BRIEFING, bin_path="/x/aidash", runner=runner,
                        opener=_noop_opener, pgrep=_up_pgrep,
                        probe=_healthy_probe, failure_sink=_noop_sink,
                        poll_s=0.0, attempts=1)
    assert not res.ok
    assert not res.published


@pytest.mark.unit
def test_push_never_raises_when_runner_raises():
    runner = FakeRunner(raise_exc=FileNotFoundError("no such binary"))
    res = push_briefing(BRIEFING, bin_path="/x/aidash", runner=runner,
                        opener=_noop_opener, pgrep=_up_pgrep,
                        probe=_healthy_probe, failure_sink=_noop_sink,
                        poll_s=0.0, attempts=1)
    assert not res.ok  # degraded, not raised


@pytest.mark.unit
def test_push_never_raises_when_opener_raises():
    def bad_opener():
        raise OSError("open failed")
    res = push_briefing(BRIEFING, bin_path="/x/aidash", runner=FakeRunner(),
                        opener=bad_opener, pgrep=_down_pgrep,
                        probe=_healthy_probe, failure_sink=_noop_sink,
                        poll_s=0.0, attempts=1)
    assert not res.ok


# --- ensure_xpc_ready ------------------------------------------------------
@pytest.mark.unit
def test_ensure_xpc_ready_true_on_first_healthy_probe():
    assert ensure_xpc_ready("/x/aidash", probe=_healthy_probe,
                            poll_s=0.0, attempts=3) is True


@pytest.mark.unit
def test_ensure_xpc_ready_false_when_never_healthy():
    assert ensure_xpc_ready("/x/aidash", probe=_dead_probe,
                            poll_s=0.0, attempts=3) is False


@pytest.mark.unit
def test_ensure_xpc_ready_retries_until_healthy():
    calls = {"n": 0}

    def flaky(_bin):
        calls["n"] += 1
        return calls["n"] >= 2  # dead once, then healthy

    assert ensure_xpc_ready("/x/aidash", probe=flaky,
                            poll_s=0.0, attempts=5) is True
    assert calls["n"] == 2


@pytest.mark.unit
def test_default_probe_returns_false_on_missing_bin():
    """The real probe must be self-contained: a bad bin path is 'not ready',
    never a raised OSError the caller has to guard."""
    from L5_apps.digest.aidash import _default_probe
    assert _default_probe("/nonexistent/definitely/not/aidash") is False


@pytest.mark.unit
def test_default_probe_returns_false_on_hang(monkeypatch):
    """CRITICAL: when XPC is dead the CLI HANGS (does not fail fast). The probe
    must bound itself with a timeout and treat a hang as 'not ready', so the
    04:00 cron degrades loudly instead of blocking forever."""
    import subprocess as _sp
    from L5_apps.digest import aidash

    def _hang(*a, **kw):
        raise _sp.TimeoutExpired(cmd="aidash", timeout=kw.get("timeout", 12))

    monkeypatch.setattr(aidash.subprocess, "run", _hang)
    assert aidash._default_probe("/any/aidash", timeout_s=1) is False



# --- the 04:00 failure mode: process up, XPC dead --------------------------
@pytest.mark.unit
def test_push_skipped_when_process_up_but_xpc_dead():
    """The exact regression this fix targets: pgrep hits (app process alive)
    but the XPC listener never serves, so the push must NOT be attempted and
    the failure must be recorded loudly — not silently swallowed."""
    runner = FakeRunner(returncode=0)
    sink = RecordingSink()
    res = push_briefing(BRIEFING, bin_path="/x/aidash", runner=runner,
                        opener=_noop_opener, pgrep=_up_pgrep,
                        probe=_dead_probe, failure_sink=sink,
                        poll_s=0.0, attempts=2)
    assert not res.ok
    assert not res.published
    assert "xpc" in res.reason.lower()
    assert runner.calls == []          # never shelled out a mutating put
    assert sink.reasons                # loud: recorded to the failure sink
    assert any("xpc" in r.lower() for r in sink.reasons)


@pytest.mark.unit
def test_push_records_reason_on_publish_stage_failure():
    """A mid-publish CLI failure is also recorded loudly."""
    runner = FakeRunner(returncode=2)
    sink = RecordingSink()
    res = push_briefing(BRIEFING, bin_path="/x/aidash", runner=runner,
                        opener=_noop_opener, pgrep=_up_pgrep,
                        probe=_healthy_probe, failure_sink=sink,
                        poll_s=0.0, attempts=1)
    assert not res.ok
    assert sink.reasons


@pytest.mark.integration
def test_real_push_smoke():
    # Only runs when explicitly selected with -m integration and the app/CLI
    # are actually present. Never part of the hermetic unit suite.
    bin_path = resolve_aidash_bin()
    if bin_path is None:
        pytest.skip("aidash CLI not present in DerivedData")
    res = push_briefing(BRIEFING, bin_path=bin_path)
    assert isinstance(res, PushResult)


# --- root-cause hardening (2026-07-18): loud desktop notify + patient XPC gate -
@pytest.mark.unit
def test_default_notifier_shells_osascript(monkeypatch):
    """The notifier posts a desktop notification via osascript."""
    from L5_apps.digest import aidash
    captured = {}

    def _fake_run(argv, **kw):
        captured["argv"] = argv
        class _P:
            returncode = 0
        return _P()

    monkeypatch.setattr(aidash.subprocess, "run", _fake_run)
    aidash._default_notifier("T", "hello")
    assert captured["argv"][0] == "osascript"
    assert any("display notification" in a for a in captured["argv"])
    assert any("hello" in a for a in captured["argv"])


@pytest.mark.unit
def test_default_notifier_never_raises(monkeypatch):
    """A missing/failed osascript (non-macOS, sandbox) must be swallowed."""
    from L5_apps.digest import aidash

    def _boom(*a, **kw):
        raise OSError("osascript not found")

    monkeypatch.setattr(aidash.subprocess, "run", _boom)
    aidash._default_notifier("T", "m")  # must not raise


@pytest.mark.unit
def test_default_notifier_escapes_quotes(monkeypatch):
    """Double-quotes in the message must be escaped so the AppleScript is valid."""
    from L5_apps.digest import aidash
    captured = {}
    monkeypatch.setattr(aidash.subprocess, "run",
                        lambda argv, **kw: captured.setdefault("argv", argv))
    aidash._default_notifier('ti"tle', 'a "quoted" bit')
    script = captured["argv"][-1]
    assert '\\"quoted\\"' in script  # inner quotes escaped, not raw


@pytest.mark.unit
def test_record_push_failure_notifies_and_logs(tmp_path):
    """Both loud channels fire: the durable log line AND the desktop notify."""
    from L5_apps.digest import aidash
    notes: list[tuple[str, str]] = []
    log_path = tmp_path / "push-errors.log"
    aidash._record_push_failure(
        "XPC not reachable",
        now=lambda: "2026-07-18T04:00:00Z",
        log_path=log_path,
        notifier=lambda title, msg: notes.append((title, msg)),
    )
    assert log_path.read_text(encoding="utf-8").count("XPC not reachable") == 1
    assert len(notes) == 1                       # notified exactly once
    assert "XPC not reachable" in notes[0][1]


@pytest.mark.unit
def test_record_push_failure_notifies_even_when_log_fails(tmp_path):
    """A log-write failure must NOT skip the notification (separate try blocks)."""
    from L5_apps.digest import aidash
    notes: list = []
    # A path whose parent can't be created (a file where a dir is expected).
    bad_parent = tmp_path / "afile"
    bad_parent.write_text("x", encoding="utf-8")
    aidash._record_push_failure(
        "boom",
        log_path=bad_parent / "nested" / "push.log",
        notifier=lambda t, m: notes.append(m),
    )
    assert notes  # notified despite the log write blowing up


@pytest.mark.unit
def test_push_uses_separate_patient_xpc_budget():
    """The XPC gate must poll xpc_attempts times, NOT the (short) process budget.

    Regression guard for the 2026-07-18 warmup race: with attempts=1 but
    xpc_attempts=5, a probe that only goes healthy on its 4th call must still
    succeed — proving the XPC gate uses the patient budget, not the process one.
    """
    calls = {"n": 0}

    def slow_warmup(_bin):
        calls["n"] += 1
        return calls["n"] >= 4  # dead for 3 probes, then the listener checks in

    res = push_briefing(BRIEFING, bin_path="/x/aidash", runner=FakeRunner(0),
                        opener=_noop_opener, pgrep=_up_pgrep,
                        probe=slow_warmup, failure_sink=_noop_sink,
                        poll_s=0.0, attempts=1, xpc_attempts=5)
    assert res.ok and res.published
    assert calls["n"] == 4  # kept probing past the 1-attempt process budget


@pytest.mark.unit
def test_push_default_xpc_budget_is_patient():
    """Sanity: the default xpc_attempts is materially larger than the old shared
    6 so an Xcode-Run / cron-wake listener cold-start isn't raced."""
    import inspect
    from L5_apps.digest.aidash import push_briefing as pb
    default = inspect.signature(pb).parameters["xpc_attempts"].default
    assert default >= 20
