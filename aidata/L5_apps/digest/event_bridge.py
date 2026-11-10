"""Bridge AIDash user events back into proposal, pluggable TodoSyncProvider, alert, and Falcon state."""

from __future__ import annotations

import json
import sqlite3
import subprocess
from collections.abc import Callable
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from config import HOME, LINEAR_SYNC_SCRIPT, LOCAL_TODOS_PATH, PROPOSALS_PATH

from L5_apps.digest.proposals import Proposal, read_pending
from L5_apps.digest.todo_sync_provider import (
    LinearTodoSyncProvider,
    LocalTodoSyncProvider,
    TodoSyncProvider,
    _coerce_idea_result,
    resolve_todo_sync_provider,
)

DIGEST_VAULT_SCRIPT = (
    HOME
    / "Development"
    / "user-skills"
    / "skills"
    / "knowledge-digest"
    / "scripts"
    / "digest_vault.py"
)
DEFAULT_BLOG_REPO = HOME / "Development" / "leepepe.github.io"


def _append_jsonl(path: Path, record: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(record, ensure_ascii=False) + "\n")


def _now() -> str:
    return (
        datetime.now(timezone.utc)  # noqa: UP017
        .isoformat(timespec="seconds")
        .replace("+00:00", "Z")
    )


def _default_linear_runner(title: str, description: str) -> tuple[int, str | None]:
    script = Path(LINEAR_SYNC_SCRIPT)
    result = subprocess.run(
        [str(script), "idea", "--title", title, "--description", description,
         "--mode", "auto"],
        check=False,
        capture_output=True,
        text=True,
        timeout=30,
    )
    external_id: str | None = None
    if result.returncode == 0 and result.stdout.strip():
        try:
            payload = json.loads(result.stdout)
            if isinstance(payload, dict):
                issue_obj = payload.get("issue")
                ident = (
                    (issue_obj.get("identifier") if isinstance(issue_obj, dict) else None)
                    or payload.get("identifier")
                )
                if isinstance(ident, str) and ident.strip():
                    external_id = ident.strip()
        except json.JSONDecodeError:
            external_id = None
    return result.returncode, external_id


def _default_linear_status_runner(issue_id: str, state: str) -> int:
    script = Path(LINEAR_SYNC_SCRIPT)
    result = subprocess.run(
        [str(script), "update-issue", "--id", issue_id, "--state", state,
         "--mode", "auto"],
        check=False,
        capture_output=True,
        text=True,
        timeout=30,
    )
    return result.returncode


def _default_blog_publish_runner(
    slug: str,
    blog_repo: Path | None = None,
    mode: str = "auto",
) -> int:
    script = Path(DIGEST_VAULT_SCRIPT)
    target_blog_repo = blog_repo or DEFAULT_BLOG_REPO
    result = subprocess.run(
        [
            "python3",
            str(script),
            "publish-blog",
            "--slug",
            slug,
            "--blog-repo",
            str(target_blog_repo),
            "--mode",
            mode,
        ],
        check=False,
        capture_output=True,
        text=True,
        timeout=60,
    )
    return result.returncode


def _lookup_knowledge_proposal(
    pending: dict[str, Proposal],
    slug: str,
) -> Proposal | None:
    target_ref = f"knowledge://{slug}"
    for prop in pending.values():
        if getattr(prop, "ref", "") == target_ref or prop.id in {
            slug,
            f"learn-{slug}",
            target_ref,
        }:
            return prop
    return None


def _canonicalize_event_ref(
    raw_ref: str,
    active_provider: TodoSyncProvider,
    local_provider: LocalTodoSyncProvider,
) -> str:
    parsed_active = active_provider.parse_ref(raw_ref)
    if parsed_active is not None:
        return active_provider.format_ref(parsed_active)
    parsed_local = local_provider.parse_ref(raw_ref)
    if parsed_local is not None:
        return local_provider.format_ref(parsed_local)
    return raw_ref


def _latest_events(
    events: list[dict],
    active_provider: TodoSyncProvider | None = None,
    local_provider: LocalTodoSyncProvider | None = None,
) -> dict[str, dict]:
    provider = active_provider or LinearTodoSyncProvider(script_path=Path(LINEAR_SYNC_SCRIPT))
    local_prov = local_provider or LocalTodoSyncProvider(local_todos_path=LOCAL_TODOS_PATH)
    latest: dict[str, dict] = {}
    for event in events:
        raw_ref = str(event.get("item_ref") or event.get("itemRef") or "").strip()
        action = str(event.get("action") or "").strip().lower()
        if raw_ref and action in {"done", "undone"}:
            ref = _canonicalize_event_ref(raw_ref, provider, local_prov)
            stamp = str(event.get("timestamp") or event.get("ts") or "")
            current = latest.get(ref)
            if current is None or stamp >= str(current.get("_stamp", "")):
                latest[ref] = {**event, "_stamp": stamp}
    return latest


def _resolve_attention(path: Path, ref: str) -> bool:
    if not path.exists():
        return False
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return False
    changed = False
    items = data.get("items", []) if isinstance(data, dict) else data
    if isinstance(items, list):
        for item in items:
            if isinstance(item, dict) and item.get("ref") == ref:
                item["status"] = "resolved"
                item["resolvedAt"] = _now()
                changed = True
    if changed:
        path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n",
                        encoding="utf-8")
    return changed


def _star_falcon(path: Path, request_id: str, timestamp: str) -> bool:
    if not path.exists():
        return False
    try:
        with sqlite3.connect(path) as conn:
            columns = {
                row[1] for row in conn.execute("PRAGMA table_info(requests)")
            }
            if "summary_json" not in columns:
                return False
            key_columns = [name for name in ("id", "request_id") if name in columns]
            if not key_columns:
                return False
            where = " OR ".join(f"{name} = ?" for name in key_columns)
            conn.execute(
                "UPDATE requests SET summary_json = json_set("
                "COALESCE(summary_json, '{}'), '$.starredAt', ?) WHERE "
                + where,
                (timestamp, *(request_id for _ in key_columns)),
            )
            return conn.total_changes > 0
    except sqlite3.Error:
        return False


def process_user_events(
    events: list[dict],
    *,
    proposals_path: Path | None = None,
    falcon_db_path: Path | None = None,
    attention_status_path: Path | None = None,
    local_todos_path: Path | None = None,
    blog_repo_path: Path | None = None,
    blog_mode: str = "auto",
    provider: TodoSyncProvider | str | None = None,
    linear_runner: Callable[[str, str], Any] | None = None,
    linear_status_runner: Callable[[str, str], int] | None = None,
    blog_publish_runner: Callable[..., int] | None = None,
) -> dict:
    """Apply latest-wins event reductions and return explicit bridge counts."""
    proposal_path = proposals_path or PROPOSALS_PATH
    local_path = local_todos_path or LOCAL_TODOS_PATH
    local_provider = LocalTodoSyncProvider(local_todos_path=local_path)
    if (
        provider is None
        and (linear_runner is not None or linear_status_runner is not None)
    ):
        active_provider: TodoSyncProvider = LinearTodoSyncProvider(
            script_path=Path(LINEAR_SYNC_SCRIPT),
            idea_runner=linear_runner or _default_linear_runner,
            status_runner=linear_status_runner or _default_linear_status_runner,
        )
    else:
        active_provider = resolve_todo_sync_provider(
            provider,
            local_todos_path=local_path,
            linear_script_path=Path(LINEAR_SYNC_SCRIPT),
        )

    result = {
        "resolved": 0, "undone": 0, "promoted": 0, "falcon_starred": 0,
        "blog_published": 0, "ignored": 0, "errors": 0,
    }
    pending = {proposal.id: proposal for proposal in read_pending(proposal_path)}

    for ref, event in _latest_events(events, active_provider, local_provider).items():
        action = str(event.get("action") or "").lower()
        provider_id = active_provider.parse_ref(ref)
        target_provider: TodoSyncProvider | None = None
        if provider_id is not None:
            target_provider = active_provider
        else:
            local_id = local_provider.parse_ref(ref)
            if local_id is not None:
                provider_id = local_id
                target_provider = local_provider

        if provider_id is not None and target_provider is not None:
            try:
                rc = target_provider.sync_status(provider_id, action)
            except (OSError, subprocess.SubprocessError):
                rc = 1
            if rc == 0:
                if action == "done":
                    result["resolved"] += 1
                else:
                    result["undone"] += 1
            else:
                result["errors"] += 1
            continue
        if action == "undone":
            result["undone"] += 1
            continue
        if ref.startswith("proposal://"):
            if action == "done":
                proposal = pending.get(ref.removeprefix("proposal://"))
                if proposal is not None:
                    _append_jsonl(proposal_path, {
                        "id": proposal.id, "ts": proposal.ts,
                        "agent": proposal.agent, "title": proposal.title,
                        "detail": proposal.detail, "priority": proposal.priority,
                        "status": "dismissed",
                    })
                    result["resolved"] += 1
                else:
                    result["ignored"] += 1
            continue
        if ref.startswith("knowledge://"):
            if action == "done":
                slug = ref.removeprefix("knowledge://").strip("/")
                proposal = _lookup_knowledge_proposal(pending, slug)
                if proposal is not None:
                    _append_jsonl(proposal_path, {
                        "id": proposal.id, "ref": ref, "ts": proposal.ts,
                        "agent": proposal.agent, "title": proposal.title,
                        "detail": proposal.detail, "priority": proposal.priority,
                        "status": "dismissed",
                    })
                    result["resolved"] += 1
                else:
                    result["ignored"] += 1
            continue
        if (
            ref.startswith("gtt://")
            and action == "done"
            and attention_status_path
            and _resolve_attention(attention_status_path, ref)
        ):
            result["resolved"] += 1

    for event in events:
        if str(event.get("action") or "").lower() != "star":
            continue
        ref = str(event.get("item_ref") or event.get("itemRef") or "").strip()
        if not ref:
            result["ignored"] += 1
        elif ref.startswith("proposal://"):
            proposal = pending.get(ref.removeprefix("proposal://"))
            if proposal is None:
                result["ignored"] += 1
                continue
            prop_ref = getattr(proposal, "ref", "") or ""
            if prop_ref.startswith("knowledge://"):
                slug = prop_ref.removeprefix("knowledge://").strip("/")
                pub_runner = blog_publish_runner or _default_blog_publish_runner
                try:
                    rc = int(
                        pub_runner(
                            slug,
                            blog_repo_path or DEFAULT_BLOG_REPO,
                            blog_mode,
                        )
                    )
                except (OSError, subprocess.SubprocessError, TypeError, ValueError):
                    rc = 1
                if rc == 0:
                    _append_jsonl(proposal_path, {
                        "id": proposal.id, "ref": prop_ref,
                        "status": "approved", "ts": _now(),
                        "source": "aidash",
                    })
                    result["promoted"] += 1
                    result["blog_published"] += 1
                else:
                    result["errors"] += 1
                continue
            try:
                rc, external_id = _coerce_idea_result(
                    active_provider.promote_proposal(proposal.title, proposal.detail)
                )
            except (OSError, subprocess.SubprocessError):
                rc, external_id = 1, None
            if rc == 0:
                approved_record = {
                    "id": proposal.id, "status": "approved", "ts": _now(),
                    "source": "aidash",
                }
                if external_id:
                    approved_record["external_id"] = external_id
                _append_jsonl(proposal_path, approved_record)
                result["promoted"] += 1
            else:
                result["errors"] += 1
        elif ref.startswith("knowledge://"):
            slug = ref.removeprefix("knowledge://").strip("/")
            if not slug:
                result["ignored"] += 1
                continue
            pub_runner = blog_publish_runner or _default_blog_publish_runner
            try:
                rc = int(
                    pub_runner(
                        slug,
                        blog_repo_path or DEFAULT_BLOG_REPO,
                        blog_mode,
                    )
                )
            except (OSError, subprocess.SubprocessError, TypeError, ValueError):
                rc = 1
            if rc == 0:
                matched_prop = _lookup_knowledge_proposal(pending, slug)
                if matched_prop is not None:
                    _append_jsonl(proposal_path, {
                        "id": matched_prop.id, "ref": ref,
                        "status": "approved", "ts": _now(),
                        "source": "aidash",
                    })
                result["promoted"] += 1
                result["blog_published"] += 1
            else:
                result["errors"] += 1
        elif ref.startswith("falcon://request/"):
            request_id = ref.removeprefix("falcon://request/")
            if _star_falcon(falcon_db_path, request_id, _now()) if falcon_db_path else False:
                result["falcon_starred"] += 1
            else:
                result["ignored"] += 1
        else:
            result["ignored"] += 1
    return result
