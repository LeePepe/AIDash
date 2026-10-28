"""Repository governance and workflow-gate fingerprints."""

from __future__ import annotations

import json
import re
import shutil
import subprocess  # nosec B404 - fixed read-only commands
from pathlib import Path
from typing import Any

from cleanio import write_clean
from config import GITHUB_CI_REPOS, HOME
from rawio import read_raw, write_raw_snapshot

SOURCE = "github_ruleset"


def _gh_rules(repo: str, default_branch: str = "main") -> Any:
    if not shutil.which("gh"):
        return None
    try:
        proc = subprocess.run(
            ["gh", "api", f"repos/{repo}/rules/branches/{default_branch}"], capture_output=True,
            text=True, timeout=30, check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if proc.returncode != 0:
        try:
            proc = subprocess.run(
                ["gh", "api", f"repos/{repo}/rulesets"], capture_output=True,
                text=True, timeout=30, check=False,
            )
        except (OSError, subprocess.SubprocessError):
            return None
        if proc.returncode != 0:
            return None
    try:
        return json.loads(proc.stdout)
    except json.JSONDecodeError:
        return None


def _required_checks(rules: Any) -> tuple[int, set[str]]:
    if not rules:
        return 0, set()
    if isinstance(rules, list):
        return 0, {
            str(name)
            for rule in rules if isinstance(rule, dict)
            for name in rule.get("required_status_checks", {}).get("contexts", [])
        }
    required = rules.get("required_status_checks") or {}
    contexts = set(required.get("contexts") or [])
    return int(bool(required or rules.get("rules"))), contexts


def _yaml_value(text: str, key: str) -> str | None:
    match = re.search(rf"(?m)^\s*{re.escape(key)}\s*:\s*[\"']?([^\"'#\n]+)", text)
    return match.group(1).strip() if match else None


def _workflow_category(workflow: Path, text: str) -> str:
    haystack = f"{workflow.name} {text}".lower()
    if any(token in haystack for token in ("codex-review", "kimi-review", "review")):
        return "ai_review_gate"
    if "testflight" in haystack or "release" in haystack:
        return "release_tf"
    if "stuck-pr" in haystack or "cron" in haystack:
        return "cron_bot"
    if workflow.name in {"release.yml", "release.yaml"}:
        return "release_04"
    return "ci_build"


def _repo_path(repo: str) -> Path | None:
    name = repo.split("/", 1)[-1]
    path = HOME / "Development" / name
    return path if path.is_dir() else None


def collect() -> int:
    repos: list[dict[str, Any]] = []
    gates: list[dict[str, Any]] = []
    for repo in GITHUB_CI_REPOS:
        path = _repo_path(repo)
        workflows = sorted(path.glob(".github/workflows/*")) if path else []
        rules = _gh_rules(repo)
        ruleset_strict, required_checks = _required_checks(rules)
        shared_pin = None
        for workflow in workflows:
            if workflow.suffix not in {".yml", ".yaml"}:
                continue
            try:
                text = workflow.read_text(encoding="utf-8")
            except OSError:
                continue
            pin = re.search(r"uses:\s*LeePepe/shared-ci/[^@\s]+@([0-9a-fA-F]{7,40}|v[\w.-]+)", text)
            shared_pin = shared_pin or (pin.group(1) if pin else None)
            gates.append({
                "workflow_gate_key": f"{repo}:{workflow.name}",
                "repo_key": repo,
                "workflow_file": workflow.name,
                "workflow_name": _yaml_value(text, "name") or workflow.stem,
                "workflow_category": _workflow_category(workflow, text),
                "uses_shared_ci": int("LeePepe/shared-ci/" in text),
                "pinned_shared_ci_ref": pin.group(1) if pin else None,
                "is_required_check": int(
                    workflow.stem in required_checks
                    or (workflow.name in required_checks)
                    or any(check in {workflow.stem, workflow.name}
                           for check in required_checks)
                ),
                "timeout_minutes": int(_yaml_value(text, "timeout-minutes") or 0) or None,
            })
        repos.append({
            "repo_key": repo,
            "owner": repo.split("/", 1)[0],
            "repo_name": repo.split("/", 1)[1],
            "domain_group": "shared" if repo.split("/", 1)[1].startswith("shared-") else "product",
            "local_main_path": str(path).replace(str(HOME), "~", 1) if path else None,
            "default_branch": "main",
            "head_sha": None,
            "is_dirty": None,
            "dirty_count": None,
            "has_agents_md": int(bool(path and (path / "AGENTS.md").exists())),
            "has_layer_map": int(bool(path and (path / "CONTEXT.md").exists())),
            "has_verify_script": int(bool(path and (path / "scripts" / "verify").exists())),
            "has_design_contract": int(bool(path and (path / "docs" / "design-contract.md").exists())),
            "shared_ci_pinned_sha": shared_pin,
            "ruleset_strict": ruleset_strict,
            "updated_at": None,
        })
    return write_raw_snapshot(SOURCE, repos + gates) if repos or gates else 0


_REPO_DDL = """CREATE TABLE repo (
    repo_key TEXT PRIMARY KEY, owner TEXT, repo_name TEXT, domain_group TEXT,
    local_main_path TEXT, default_branch TEXT, head_sha TEXT, is_dirty INTEGER,
    dirty_count INTEGER, has_agents_md INTEGER, has_layer_map INTEGER,
    has_verify_script INTEGER, has_design_contract INTEGER,
    shared_ci_pinned_sha TEXT, ruleset_strict INTEGER, updated_at TEXT
)"""
_GATE_DDL = """CREATE TABLE workflow_gate (
    workflow_gate_key TEXT PRIMARY KEY, repo_key TEXT NOT NULL,
    workflow_file TEXT NOT NULL, workflow_name TEXT, workflow_category TEXT,
    uses_shared_ci INTEGER, pinned_shared_ci_ref TEXT,
    is_required_check INTEGER, timeout_minutes INTEGER
)"""


def normalize() -> int:
    repos: dict[str, dict[str, Any]] = {}
    gates: dict[str, dict[str, Any]] = {}
    for record in read_raw(SOURCE):
        if record.get("workflow_gate_key"):
            gates[record["workflow_gate_key"]] = record
        elif record.get("repo_key"):
            repos[record["repo_key"]] = record
    repo_cols = ("repo_key", "owner", "repo_name", "domain_group", "local_main_path",
                 "default_branch", "head_sha", "is_dirty", "dirty_count",
                 "has_agents_md", "has_layer_map", "has_verify_script",
                 "has_design_contract", "shared_ci_pinned_sha", "ruleset_strict",
                 "updated_at")
    gate_cols = ("workflow_gate_key", "repo_key", "workflow_file", "workflow_name",
                 "workflow_category", "uses_shared_ci", "pinned_shared_ci_ref",
                 "is_required_check", "timeout_minutes")
    count = write_clean(SOURCE, "repo", _REPO_DDL, list(repos.values()), repo_cols)
    count += write_clean(SOURCE, "workflow_gate", _GATE_DDL, list(gates.values()), gate_cols)
    return count
