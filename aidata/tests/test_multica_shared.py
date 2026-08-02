"""Unit tests for the shared Multica CLI helper (adapters/_multica.py, T3).

Hermetic: subprocess + shutil.which are monkeypatched so no live CLI is needed.
Covers resolver fallback, the no-binary RuntimeError, nonzero-exit RuntimeError
with stderr truncation, empty-stdout -> [], JSON parsing, and the injected-binp
seam that lets adapters pass their own patchable _multica_bin().
"""

import subprocess

import pytest

import adapters._multica as m


@pytest.mark.unit
def test_multica_bin_prefers_config_name(monkeypatch):
    seen = []

    def fake_which(name):
        seen.append(name)
        return "/opt/bin/multica" if name == m.MULTICA_BIN else None

    monkeypatch.setattr(m.shutil, "which", fake_which)
    assert m.multica_bin() == "/opt/bin/multica"


@pytest.mark.unit
def test_multica_bin_falls_back_to_plain_multica(monkeypatch):
    monkeypatch.setattr(
        m.shutil, "which",
        lambda name: "/usr/bin/multica" if name == "multica" else None)
    assert m.multica_bin() == "/usr/bin/multica"


@pytest.mark.unit
def test_multica_bin_none_when_absent(monkeypatch):
    monkeypatch.setattr(m.shutil, "which", lambda name: None)
    assert m.multica_bin() is None


@pytest.mark.unit
def test_run_json_raises_without_binary(monkeypatch):
    monkeypatch.setattr(m, "multica_bin", lambda: None)
    with pytest.raises(RuntimeError, match="not found"):
        m.run_json(["issue", "list"])


@pytest.mark.unit
def test_run_json_uses_injected_binp(monkeypatch):
    captured = {}

    def fake_run(argv, **kw):
        captured["argv"] = argv
        return subprocess.CompletedProcess(argv, 0, stdout='{"ok": true}', stderr="")

    monkeypatch.setattr(m.subprocess, "run", fake_run)
    # multica_bin would return None, but the injected binp must win.
    monkeypatch.setattr(m, "multica_bin", lambda: None)
    out = m.run_json(["issue", "list"], binp="/tmp/fake-multica")
    assert out == {"ok": True}
    assert captured["argv"][0] == "/tmp/fake-multica"
    assert captured["argv"][1:] == ["issue", "list"]


@pytest.mark.unit
def test_run_json_empty_stdout_returns_empty_list(monkeypatch):
    monkeypatch.setattr(
        m.subprocess, "run",
        lambda argv, **kw: subprocess.CompletedProcess(argv, 0, stdout="  ", stderr=""))
    assert m.run_json(["x"], binp="/bin/multica") == []


@pytest.mark.unit
def test_run_json_nonzero_raises_with_truncated_stderr(monkeypatch):
    long_err = "E" * 500
    monkeypatch.setattr(
        m.subprocess, "run",
        lambda argv, **kw: subprocess.CompletedProcess(argv, 1, stdout="", stderr=long_err))
    with pytest.raises(RuntimeError) as ei:
        m.run_json(["issue", "runs"], binp="/bin/multica")
    msg = str(ei.value)
    # stderr truncated to _STDERR_TRUNC chars
    assert ("E" * m._STDERR_TRUNC) in msg
    assert ("E" * (m._STDERR_TRUNC + 1)) not in msg
