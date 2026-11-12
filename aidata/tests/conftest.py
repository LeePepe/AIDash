"""Keep every test state sink inside pytest's temporary directory."""

from __future__ import annotations

import importlib
from pathlib import Path

import pytest


@pytest.fixture(autouse=True)
def isolate_digest_state(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    state = tmp_path / "state"
    archive = tmp_path / "archive"
    state.mkdir()
    archive.mkdir()
    config = importlib.import_module("config")
    monkeypatch.setattr(config, "PROPOSALS_PATH", state / "proposals.jsonl", raising=False)
    monkeypatch.setattr(config, "LEARNING_QUEUE_PATH", state / "learning_queue.jsonl", raising=False)
    for module_name, names in {
        "L5_apps.digest.proposals": ("PROPOSALS_PATH",),
        "L5_apps.digest.event_bridge": ("PROPOSALS_PATH", "LEARNING_QUEUE_PATH", "JOB_ACTION_CURSOR_PATH"),
        "L5_apps.digest.app": ("DIGEST_DIR",),
        "L5_apps.digest.aidash": ("PUSH_ERROR_LOG",),
        "L5_apps.digest.freshness": ("_CRON_ERR_LOG",),
    }.items():
        try:
            module = importlib.import_module(module_name)
        except ImportError:
            continue
        for name in names:
            target = state / f"{name.lower()}.jsonl"
            if name == "DIGEST_DIR":
                target = archive
            elif name == "_CRON_ERR_LOG":
                target = state / "cron-errors.log"
            elif name == "PUSH_ERROR_LOG":
                target = state / "aidash-push-errors.log"
            monkeypatch.setattr(module, name, target, raising=False)
    yield
