"""team_audit_snapshot adapter — manual import of immutable team-audit bundles.

This source is intentionally excluded from the default scheduled collection pass.
It reads a configured local import root (TEAM_AUDIT_IMPORT_ROOT) and imports a
bundle snapshot only when the operator explicitly selects the source via
`aidata collect --source team_audit_snapshot`.

The contract is intentionally conservative:
- read-only import from a local filesystem root
- append-only raw storage via rawio.write_raw()
- duplicate identity+hash replays are ignored
- identity+new-hash collisions are kept as collision observations rather than
  overwriting the accepted parent snapshot
- same identity+same hash should be a no-op on re-import
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any, Iterable

from cleanio import write_clean
from rawio import read_raw, write_raw

SOURCE = "team_audit_snapshot"
_JSON_SUFFIXES = {".json", ".jsonl", ".ndjson"}


def _manual_root() -> Path | None:
    try:
        import config
    except Exception:
        return None
    root = getattr(config, "TEAM_AUDIT_IMPORT_ROOT", "")
    if not root:
        return None
    path = Path(str(root)).expanduser()
    return path if path.exists() else None


def _canonical_json(value: Any) -> str:
    return json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(",", ":"))


def _hash_payload(value: Any) -> str:
    payload = _canonical_json(value).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def _record_identity(payload: dict[str, Any], fallback: str) -> str:
    for key in (
        "identity",
        "snapshot_id",
        "snapshotId",
        "bundle_id",
        "bundleId",
        "id",
        "record_id",
    ):
        value = payload.get(key)
        if value not in (None, ""):
            return str(value)
    for key in ("subject_id", "subjectId"):
        value = payload.get(key)
        if value not in (None, ""):
            return f"subject:{value}"
    return fallback


def _normalize_value(value: Any) -> Any:
    if isinstance(value, (str, int, float, bool)) or value is None:
        return value
    if isinstance(value, (list, tuple, dict)):
        return json.dumps(value, ensure_ascii=False, sort_keys=True)
    return str(value)


def _parent_from_payload(payload: dict[str, Any]) -> tuple[str | None, str | None]:
    for parent_key in ("parent", "parent_snapshot", "accepted_parent"):
        parent = payload.get(parent_key)
        if isinstance(parent, dict):
            parent_id = _record_identity(parent, "")
            parent_hash = parent.get("hash") or parent.get("snapshot_hash") or parent.get("content_hash")
            if parent_id or parent_hash:
                return (parent_id or None, parent_hash or None)
    return (
        payload.get("parent_snapshot_id") or payload.get("parentSnapshotId") or None,
        payload.get("parent_snapshot_hash") or payload.get("parentSnapshotHash") or payload.get("accepted_parent_hash") or None,
    )


def _payload_to_record(raw: Any, *, file_path: str) -> Iterable[dict[str, Any]]:
    if isinstance(raw, list):
        for item in raw:
            yield from _payload_to_record(item, file_path=file_path)
        return

    if not isinstance(raw, dict):
        return

    payload = dict(raw)
    kind = (
        payload.get("kind")
        or payload.get("type")
        or payload.get("record_type")
        or payload.get("entity_type")
        or "snapshot"
    )

    # Many bundle shapes are nested under a single key like `records`, `findings`,
    # `children`, or `sidecars`. Keep the parent bundle record first so its hash is
    # accepted as the canonical snapshot, and later nested records can be treated as
    # collisions or children without overwriting the accepted parent.
    identity = _record_identity(payload, f"{kind}:{file_path}")
    digest = (
        payload.get("hash")
        or payload.get("snapshot_hash")
        or payload.get("content_hash")
        or payload.get("sha256")
        or payload.get("sidecar_hash")
        or _hash_payload(payload)
    )
    parent_id, parent_hash = _parent_from_payload(payload)

    record = {
        "kind": kind,
        "identity": identity,
        "hash": str(digest),
        "source_path": file_path,
        "payload": payload,
        "cohort": payload.get("cohort"),
        "cursor": payload.get("cursor") or payload.get("cursor_id"),
        "instruction_hash": payload.get("instruction_hash") or payload.get("instructionHash"),
        "axes": _normalize_value(payload.get("axes")),
        "subject_id": payload.get("subject_id") or payload.get("subjectId"),
        "responsibility_layer": payload.get("responsibility_layer") or payload.get("responsibilityLayer"),
        "feedback_lineage": _normalize_value(payload.get("feedback_lineage") or payload.get("feedbackLineage")),
        "agent_repeat": _normalize_value(payload.get("agent_repeat") or payload.get("agentRepeat")),
        "limitations": _normalize_value(payload.get("limitations")),
        "artifacts": _normalize_value(payload.get("artifacts")),
        "grill": _normalize_value(payload.get("grill")),
        "sidecar_id": payload.get("sidecar_id") or payload.get("sidecarId"),
        "sidecar_hash": payload.get("sidecar_hash") or payload.get("sidecarHash"),
        "parent_snapshot_id": parent_id,
        "parent_snapshot_hash": parent_hash,
        "accepted_parent_snapshot_id": payload.get("accepted_parent_snapshot_id") or payload.get("acceptedParentSnapshotId"),
        "accepted_parent_snapshot_hash": payload.get("accepted_parent_snapshot_hash") or payload.get("acceptedParentSnapshotHash"),
        "observation_kind": payload.get("observation_kind") or payload.get("observationKind"),
        "detail": payload.get("detail") or payload.get("message") or payload.get("note"),
    }
    yield record

    for key in ("records", "findings", "children", "sidecars", "snapshots", "observations", "entries"):
        if key in payload and isinstance(payload[key], (list, tuple)):
            for child in payload[key]:
                yield from _payload_to_record(child, file_path=file_path)


def _iter_import_files(root: Path) -> Iterable[Path]:
    if root.is_file():
        if root.suffix.lower() in _JSON_SUFFIXES:
            yield root
        return
    for path in sorted(root.rglob("*")):
        if path.is_file() and path.suffix.lower() in _JSON_SUFFIXES:
            yield path


def collect() -> int:
    """Collect manual bundle snapshots into append-only raw JSONL shards."""
    root = _manual_root()
    if root is None:
        return 0

    seen: set[tuple[str, str]] = set()
    batch: list[dict[str, Any]] = []
    for path in _iter_import_files(root):
        try:
            raw_text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        try:
            parsed: Any = json.loads(raw_text)
        except json.JSONDecodeError:
            for line in raw_text.splitlines():
                if not line.strip():
                    continue
                try:
                    parsed_line = json.loads(line)
                except json.JSONDecodeError:
                    continue
                for rec in _payload_to_record(parsed_line, file_path=str(path)):
                    key = (rec["identity"], rec["hash"])
                    if key in seen:
                        continue
                    seen.add(key)
                    batch.append(rec)
            continue

        for rec in _payload_to_record(parsed, file_path=str(path)):
            key = (rec["identity"], rec["hash"])
            if key in seen:
                continue
            seen.add(key)
            batch.append(rec)

    if not batch:
        return 0
    return write_raw(SOURCE, batch)


_SNAPSHOT_DDL = """
CREATE TABLE snapshot (
    snapshot_id TEXT PRIMARY KEY,
    kind TEXT,
    identity TEXT,
    content_hash TEXT,
    cohort TEXT,
    cursor TEXT,
    instruction_hash TEXT,
    axes TEXT,
    subject_id TEXT,
    responsibility_layer TEXT,
    feedback_lineage TEXT,
    agent_repeat TEXT,
    limitations TEXT,
    artifacts TEXT,
    grill TEXT,
    sidecar_id TEXT,
    sidecar_hash TEXT,
    parent_snapshot_id TEXT,
    parent_snapshot_hash TEXT,
    accepted_parent_snapshot_id TEXT,
    accepted_parent_snapshot_hash TEXT,
    source_path TEXT,
    payload_json TEXT
)
"""

_SNAPSHOT_COLS = (
    "snapshot_id",
    "kind",
    "identity",
    "content_hash",
    "cohort",
    "cursor",
    "instruction_hash",
    "axes",
    "subject_id",
    "responsibility_layer",
    "feedback_lineage",
    "agent_repeat",
    "limitations",
    "artifacts",
    "grill",
    "sidecar_id",
    "sidecar_hash",
    "parent_snapshot_id",
    "parent_snapshot_hash",
    "accepted_parent_snapshot_id",
    "accepted_parent_snapshot_hash",
    "source_path",
    "payload_json",
)

_COLLISION_DDL = """
CREATE TABLE observation (
    observation_id TEXT PRIMARY KEY,
    snapshot_id TEXT,
    observation_kind TEXT,
    detail TEXT,
    parent_snapshot_id TEXT,
    parent_snapshot_hash TEXT,
    identity TEXT,
    content_hash TEXT
)
"""

_COLLISION_COLS = (
    "observation_id",
    "snapshot_id",
    "observation_kind",
    "detail",
    "parent_snapshot_id",
    "parent_snapshot_hash",
    "identity",
    "content_hash",
)

_SIDECAR_DDL = """
CREATE TABLE sidecar (
    sidecar_id TEXT PRIMARY KEY,
    snapshot_id TEXT,
    sidecar_hash TEXT,
    kind TEXT,
    source_path TEXT,
    content_hash TEXT
)
"""

_SIDECAR_COLS = (
    "sidecar_id",
    "snapshot_id",
    "sidecar_hash",
    "kind",
    "source_path",
    "content_hash",
)


def _snapshot_row(rec: dict[str, Any]) -> dict[str, Any]:
    body = rec.get("payload") or rec
    snapshot_id = rec.get("identity")
    return {
        "snapshot_id": snapshot_id,
        "kind": rec.get("kind") or "snapshot",
        "identity": rec.get("identity"),
        "content_hash": rec.get("hash"),
        "cohort": rec.get("cohort"),
        "cursor": rec.get("cursor"),
        "instruction_hash": rec.get("instruction_hash"),
        "axes": rec.get("axes"),
        "subject_id": rec.get("subject_id"),
        "responsibility_layer": rec.get("responsibility_layer"),
        "feedback_lineage": rec.get("feedback_lineage"),
        "agent_repeat": rec.get("agent_repeat"),
        "limitations": rec.get("limitations"),
        "artifacts": rec.get("artifacts"),
        "grill": rec.get("grill"),
        "sidecar_id": rec.get("sidecar_id"),
        "sidecar_hash": rec.get("sidecar_hash"),
        "parent_snapshot_id": rec.get("parent_snapshot_id"),
        "parent_snapshot_hash": rec.get("parent_snapshot_hash"),
        "accepted_parent_snapshot_id": rec.get("accepted_parent_snapshot_id"),
        "accepted_parent_snapshot_hash": rec.get("accepted_parent_snapshot_hash"),
        "source_path": rec.get("source_path"),
        "payload_json": json.dumps(body, ensure_ascii=False, sort_keys=True),
    }


def _observation_row(rec: dict[str, Any], *, parent_snapshot_id: str | None, parent_hash: str | None) -> dict[str, Any]:
    return {
        "observation_id": f"obs:{rec.get('identity')}:{rec.get('hash')}",
        "snapshot_id": rec.get("identity"),
        "observation_kind": rec.get("observation_kind") or "collision",
        "detail": rec.get("detail") or "identity hash collision",
        "parent_snapshot_id": parent_snapshot_id,
        "parent_snapshot_hash": parent_hash,
        "identity": rec.get("identity"),
        "content_hash": rec.get("hash"),
    }


def _sidecar_row(rec: dict[str, Any]) -> dict[str, Any] | None:
    sidecar_id = rec.get("sidecar_id")
    if not sidecar_id:
        return None
    return {
        "sidecar_id": sidecar_id,
        "snapshot_id": rec.get("identity"),
        "sidecar_hash": rec.get("sidecar_hash") or rec.get("hash"),
        "kind": rec.get("kind") or "sidecar",
        "source_path": rec.get("source_path"),
        "content_hash": rec.get("hash"),
    }


def normalize() -> int:
    """Normalize raw bundle records into an idempotent clean SQLite DB."""
    if _manual_root() is None:
        return 0

    raw_records = read_raw(SOURCE)
    if not raw_records:
        return 0

    accepted: dict[str, dict[str, Any]] = {}
    snapshot_rows: list[dict[str, Any]] = []
    observation_rows: list[dict[str, Any]] = []
    sidecar_rows: list[dict[str, Any]] = []

    for rec in raw_records:
        rec = dict(rec)
        identity = rec.get("identity")
        if not identity:
            continue
        digest = str(rec.get("hash") or "")

        is_collision = bool(
            rec.get("observation_kind")
            or rec.get("parent_snapshot_id")
            or rec.get("parent_snapshot_hash")
        )

        existing = accepted.get(identity)
        if existing is None:
            if is_collision:
                # A collision without an accepted parent can be stored as an
                # observation only after the canonical snapshot is known.
                continue
            accepted[identity] = rec
            snapshot_rows.append(_snapshot_row(rec))
            sidecar = _sidecar_row(rec)
            if sidecar is not None:
                sidecar_rows.append(sidecar)
            continue

        if existing.get("hash") == digest:
            # Replay of the same snapshot identity/hash — ignore as a duplicate.
            continue

        parent_id = existing.get("identity")
        parent_hash = existing.get("hash")
        observation_rows.append(_observation_row(rec, parent_snapshot_id=parent_id, parent_hash=parent_hash))

    if snapshot_rows:
        write_clean(SOURCE, "snapshot", _SNAPSHOT_DDL, snapshot_rows, _SNAPSHOT_COLS)
    if observation_rows:
        write_clean(SOURCE, "observation", _COLLISION_DDL, observation_rows, _COLLISION_COLS)
    if sidecar_rows:
        write_clean(SOURCE, "sidecar", _SIDECAR_DDL, sidecar_rows, _SIDECAR_COLS)

    return len(snapshot_rows)
