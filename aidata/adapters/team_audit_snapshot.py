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
from datetime import datetime, timezone
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
    if not path.exists():
        return None
    try:
        return path.resolve(strict=True)
    except OSError:
        return None


def _canonical_json(value: Any) -> str:
    return json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(",", ":"))


def _hash_bytes(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def _hash_payload(value: Any) -> str:
    return _hash_bytes(_canonical_json(value).encode("utf-8"))


def _is_utc_timestamp(value: Any) -> bool:
    if not isinstance(value, str) or not value:
        return False
    try:
        datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return False
    return True


def _first_value(payload: dict[str, Any], *keys: str) -> Any:
    for key in keys:
        if key in payload and payload[key] not in (None, ""):
            return payload[key]
    return None


def _record_identity(payload: dict[str, Any], fallback: str) -> str:
    value = _first_value(payload, "snapshotID", "snapshot_id", "snapshotId", "identity", "bundleID", "bundle_id", "bundleId", "id")
    if value is not None:
        return str(value)
    for key in ("subjectID", "subject_id", "subjectId"):
        value = payload.get(key)
        if value not in (None, ""):
            return f"subject:{value}"
    return fallback


def _is_snapshot_like(value: Any) -> bool:
    if not isinstance(value, dict):
        return False
    return bool(_first_value(value, "snapshotID", "snapshot_id", "snapshotId", "identity"))


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
            parent_hash = _first_value(parent, "hash", "snapshotHash", "snapshot_hash", "contentHash", "content_hash")
            if parent_id or parent_hash:
                return (str(parent_id) if parent_id else None, str(parent_hash) if parent_hash else None)
    parent_id = _first_value(payload, "parent_snapshot_id", "parentSnapshotId", "accepted_parent_snapshot_id", "acceptedParentSnapshotId")
    parent_hash = _first_value(payload, "parent_snapshot_hash", "parentSnapshotHash", "accepted_parent_snapshot_hash", "acceptedParentSnapshotHash")
    return (str(parent_id) if parent_id else None, str(parent_hash) if parent_hash else None)


def _is_contract_payload(payload: Any) -> bool:
    if not isinstance(payload, dict):
        return False
    ids = (
        "snapshotID",
        "snapshot_id",
        "snapshotId",
        "identity",
        "bundleID",
        "bundle_id",
        "bundleId",
    )
    if not any(key in payload for key in ids):
        return False
    if "message" in payload and not any(key in payload for key in ids + ("sidecarID", "sidecar_id", "sidecarId")):
        return False
    if _first_value(payload, "subjectID", "subject_id", "subjectId") in (None, ""):
        return False
    if _first_value(payload, "responsibilityLayer", "responsibility_layer", "responsibility") in (None, ""):
        return False
    if _first_value(payload, "mode") not in (None, "baseline", "incremental", "replay", "collision"):
        return False
    if _first_value(payload, "capturedAt", "captured_at") is not None and not _is_utc_timestamp(_first_value(payload, "capturedAt", "captured_at")):
        return False
    if _first_value(payload, "cohort") is None:
        return False
    if _first_value(payload, "cursor") is None:
        return False
    if "axes" in payload and not isinstance(payload.get("axes"), list):
        return False
    if "feedbackLineage" in payload and not isinstance(payload.get("feedbackLineage"), list):
        return False
    if "agentRepeat" in payload and not isinstance(payload.get("agentRepeat"), list):
        return False
    if "limitations" in payload and not isinstance(payload.get("limitations"), list):
        return False
    if "artifacts" in payload and not isinstance(payload.get("artifacts"), list):
        return False
    if "grill" in payload and not isinstance(payload.get("grill"), list):
        return False
    return True


def _iter_import_files(root: Path) -> Iterable[Path]:
    root_resolved = root.resolve(strict=True)
    for path in sorted(root_resolved.rglob("*"), key=lambda p: (0 if p.name == "snapshot.json" else 1 if p.name == "artifacts.json" else 2, p.name, str(p.relative_to(root_resolved)))):
        if path.is_symlink() or not path.is_file():
            continue
        try:
            resolved = path.resolve(strict=True)
        except OSError:
            continue
        try:
            resolved.relative_to(root_resolved)
        except ValueError:
            continue
        if path.suffix.lower() in _JSON_SUFFIXES:
            yield path


def _read_json_text(path: Path) -> Any | None:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError):
        return None


def _bundle_from_file(path: Path, root: Path) -> dict[str, Any] | None:
    parsed = _read_json_text(path)
    if parsed is None:
        return None
    if isinstance(parsed, list):
        for item in parsed:
            if isinstance(item, dict) and _is_contract_payload(item):
                return dict(item)
        return None
    if not isinstance(parsed, dict):
        return None

    payload = dict(parsed)
    if path.name.endswith("snapshot.json"):
        sidecar_path = path.with_name("artifacts.json")
        if sidecar_path.exists() and sidecar_path.is_file() and not sidecar_path.is_symlink():
            sidecar_raw = _read_json_text(sidecar_path)
            if isinstance(sidecar_raw, dict):
                payload.setdefault("artifacts", sidecar_raw.get("artifacts") or sidecar_raw.get("items") or [])
                payload.setdefault("grill", sidecar_raw.get("grill") or [])
                payload.setdefault("sidecarID", _first_value(sidecar_raw, "sidecarID", "sidecar_id", "sidecarId"))
                payload.setdefault("sidecarHash", _first_value(sidecar_raw, "sidecarHash", "sidecar_hash", "sidecarHash"))
                payload.setdefault("subjectID", _first_value(sidecar_raw, "subjectID", "subject_id", "subjectId"))
                payload.setdefault("responsibilityLayer", _first_value(sidecar_raw, "responsibilityLayer", "responsibility_layer", "responsibility"))
                payload.setdefault("schemaVersion", sidecar_raw.get("schemaVersion") or sidecar_raw.get("schema_version") or "team-audit/v1")
    elif path.name == "artifacts.json":
        payload.setdefault("sidecarID", _first_value(payload, "sidecarID", "sidecar_id", "sidecarId"))
        payload.setdefault("subjectID", _first_value(payload, "subjectID", "subject_id", "subjectId"))

    if not _is_contract_payload(payload):
        return None
    if not _contract_valid(payload):
        return None
    return payload


def _contract_valid(payload: dict[str, Any]) -> bool:
    snapshot_id = _first_value(payload, "snapshotID", "snapshot_id", "snapshotId", "identity")
    if snapshot_id in (None, ""):
        return False
    if _first_value(payload, "subjectID", "subject_id", "subjectId") in (None, ""):
        return False
    if _first_value(payload, "responsibilityLayer", "responsibility_layer", "responsibility") in (None, ""):
        return False
    captured_at = _first_value(payload, "capturedAt", "captured_at")
    if captured_at is None or not _is_utc_timestamp(captured_at):
        return False
    mode = _first_value(payload, "mode")
    if mode is None or mode not in {"baseline", "incremental", "replay", "collision"}:
        return False
    cohort = _first_value(payload, "cohort")
    if cohort is None or not isinstance(cohort, str):
        return False
    cursor = _first_value(payload, "cursor")
    if cursor is None or not isinstance(cursor, str):
        return False
    axes = payload.get("axes")
    if not isinstance(axes, list) or not axes:
        return False
    for item in axes:
        if not isinstance(item, str):
            return False
    for key in ("feedbackLineage", "agentRepeat", "limitations", "artifacts", "grill"):
        value = payload.get(key)
        if value is not None and not isinstance(value, list):
            return False
    return True


def _payload_record(payload: dict[str, Any], *, file_path: str, file_bytes: bytes) -> dict[str, Any]:
    snapshot_id = _record_identity(payload, f"snapshot:{file_path}")
    digest = _hash_bytes(file_bytes)
    sidecar_id = _first_value(payload, "sidecarID", "sidecar_id", "sidecarId")
    sidecar_hash = _first_value(payload, "sidecarHash", "sidecar_hash", "sidecarHash")
    if sidecar_id is not None and sidecar_hash is None:
        sidecar_hash = digest
    parent_snapshot_id, parent_snapshot_hash = _parent_from_payload(payload)
    captured_at = _first_value(payload, "capturedAt", "captured_at") or datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    return {
        "kind": "snapshot",
        "identity": snapshot_id,
        "hash": digest,
        "source_path": file_path,
        "payload": payload,
        "cohort": _first_value(payload, "cohort"),
        "cursor": _first_value(payload, "cursor", "cursorId", "cursor_id"),
        "instruction_hash": _first_value(payload, "instructionHash", "instruction_hash"),
        "axes": _normalize_value(payload.get("axes")),
        "subject_id": _first_value(payload, "subjectID", "subject_id", "subjectId"),
        "responsibility_layer": _first_value(payload, "responsibilityLayer", "responsibility_layer", "responsibility"),
        "feedback_lineage": _normalize_value(payload.get("feedbackLineage", payload.get("feedback_lineage"))),
        "agent_repeat": _normalize_value(payload.get("agentRepeat", payload.get("agent_repeat"))),
        "limitations": _normalize_value(payload.get("limitations")),
        "artifacts": _normalize_value(payload.get("artifacts")),
        "grill": _normalize_value(payload.get("grill")),
        "sidecar_id": sidecar_id,
        "sidecar_hash": sidecar_hash,
        "parent_snapshot_id": parent_snapshot_id,
        "parent_snapshot_hash": parent_snapshot_hash,
        "accepted_parent_snapshot_id": _first_value(payload, "acceptedParentSnapshotId", "accepted_parent_snapshot_id"),
        "accepted_parent_snapshot_hash": _first_value(payload, "acceptedParentSnapshotHash", "accepted_parent_snapshot_hash"),
        "observation_kind": _first_value(payload, "observationKind", "observation_kind"),
        "detail": _first_value(payload, "detail", "message", "note"),
        "observed_at": _first_value(payload, "observedAt", "observed_at") or captured_at,
        "source": SOURCE,
        "mode": _first_value(payload, "mode"),
        "captured_at": captured_at,
        "schema_version": _first_value(payload, "schemaVersion", "schema_version") or "team-audit/v1",
    }


def _observation_record(identity: str, digest: str, *, parent_snapshot_id: str | None, parent_snapshot_hash: str | None, detail: str) -> dict[str, Any]:
    observed_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    return {
        "kind": "observation",
        "identity": identity,
        "hash": digest,
        "source": SOURCE,
        "observation_kind": "collision",
        "detail": detail,
        "parent_snapshot_id": parent_snapshot_id,
        "parent_snapshot_hash": parent_snapshot_hash,
        "observed_at": observed_at,
        "disposition": "rejected",
        "limitation": "same snapshot identity with different hash",
    }


def collect() -> int:
    """Collect manual bundle snapshots into append-only raw JSONL shards."""
    root = _manual_root()
    if root is None:
        return 0

    existing: set[tuple[str, str]] = {(r.get("identity"), r.get("hash")) for r in read_raw(SOURCE) if r.get("identity") and r.get("hash")}
    accepted_by_identity: dict[str, str] = {}
    batch: list[dict[str, Any]] = []

    for path in _iter_import_files(root):
        if path.suffix.lower() == ".jsonl" or path.suffix.lower() == ".ndjson":
            try:
                lines = path.read_text(encoding="utf-8").splitlines()
            except (OSError, UnicodeDecodeError):
                continue
            for line in lines:
                if not line.strip():
                    continue
                try:
                    payload = json.loads(line)
                except json.JSONDecodeError:
                    continue
                bundle = payload if isinstance(payload, dict) and _is_contract_payload(payload) else None
                if bundle is None:
                    continue
                record = _payload_record(bundle, file_path=str(path), file_bytes=line.encode("utf-8"))
                rec_key = (record["identity"], record["hash"])
                prev_hash = accepted_by_identity.get(record["identity"])
                seen_batch = {(r.get("identity"), r.get("hash")) for r in batch if r.get("identity") and r.get("hash")}
                if rec_key in existing or rec_key in seen_batch:
                    continue
                if prev_hash is None:
                    accepted_by_identity[record["identity"]] = record["hash"]
                    batch.append(record)
                    existing.add(rec_key)
                    continue
                if prev_hash == record["hash"]:
                    continue
                obs = _observation_record(
                    record["identity"],
                    record["hash"],
                    parent_snapshot_id=record["identity"],
                    parent_snapshot_hash=prev_hash,
                    detail="replayed snapshot differs from accepted parent",
                )
                seen_batch = {(r.get("identity"), r.get("hash")) for r in batch if r.get("identity") and r.get("hash")}
                if (obs["identity"], obs["hash"]) not in existing and (obs["identity"], obs["hash"]) not in seen_batch:
                    batch.append(obs)
                    existing.add((obs["identity"], obs["hash"]))
                continue

        if path.suffix.lower() == ".json":
            payload = _bundle_from_file(path, root)
            if payload is None:
                continue
            snapshot_id = _record_identity(payload, f"snapshot:{path}")
            file_bytes = path.read_bytes()
            digest = _hash_bytes(file_bytes)
            rec_key = (snapshot_id, digest)
            if rec_key in existing:
                continue
            prev_hash = accepted_by_identity.get(snapshot_id)
            if prev_hash is None:
                record = _payload_record(payload, file_path=str(path), file_bytes=file_bytes)
                accepted_by_identity[record["identity"]] = record["hash"]
                batch.append(record)
                existing.add((record["identity"], record["hash"]))
                continue
            if prev_hash != digest:
                obs = _observation_record(
                    snapshot_id,
                    digest,
                    parent_snapshot_id=snapshot_id,
                    parent_snapshot_hash=prev_hash,
                    detail="replayed snapshot differs from accepted parent",
                )
                seen_batch = {(r.get("identity"), r.get("hash")) for r in batch if r.get("identity") and r.get("hash")}
                if (obs["identity"], obs["hash"]) not in existing and (obs["identity"], obs["hash"]) not in seen_batch:
                    batch.append(obs)
                    existing.add((obs["identity"], obs["hash"]))

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
    payload_json TEXT,
    observed_at TEXT,
    source TEXT,
    schema_version TEXT,
    mode TEXT,
    captured_at TEXT
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
    "observed_at",
    "source",
    "schema_version",
    "mode",
    "captured_at",
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
    content_hash TEXT,
    observed_at TEXT,
    source TEXT,
    disposition TEXT,
    limitation TEXT
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
    "observed_at",
    "source",
    "disposition",
    "limitation",
)

_SIDECAR_DDL = """
CREATE TABLE sidecar (
    sidecar_id TEXT PRIMARY KEY,
    snapshot_id TEXT,
    sidecar_hash TEXT,
    kind TEXT,
    source_path TEXT,
    content_hash TEXT,
    observed_at TEXT,
    source TEXT
)
"""

_SIDECAR_COLS = (
    "sidecar_id",
    "snapshot_id",
    "sidecar_hash",
    "kind",
    "source_path",
    "content_hash",
    "observed_at",
    "source",
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
        "observed_at": rec.get("observed_at"),
        "source": rec.get("source") or SOURCE,
        "schema_version": body.get("schemaVersion") or body.get("schema_version") or "team-audit/v1",
        "mode": body.get("mode"),
        "captured_at": body.get("capturedAt") or body.get("captured_at"),
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
        "observed_at": rec.get("observed_at") or rec.get("captured_at"),
        "source": rec.get("source") or SOURCE,
        "disposition": "rejected",
        "limitation": "same snapshot identity with different hash",
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
        "observed_at": rec.get("observed_at"),
        "source": rec.get("source") or SOURCE,
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

        if rec.get("kind") == "observation":
            observation_rows.append(_observation_row(rec, parent_snapshot_id=rec.get("parent_snapshot_id"), parent_hash=rec.get("parent_snapshot_hash")))
            continue

        existing = accepted.get(identity)
        if existing is None:
            accepted[identity] = rec
            snapshot_rows.append(_snapshot_row(rec))
            sidecar = _sidecar_row(rec)
            if sidecar is not None:
                sidecar_rows.append(sidecar)
            continue

        if existing.get("hash") == digest:
            continue

        observation_rows.append(_observation_row(rec, parent_snapshot_id=identity, parent_hash=existing.get("hash")))

    if snapshot_rows:
        write_clean(SOURCE, "snapshot", _SNAPSHOT_DDL, snapshot_rows, _SNAPSHOT_COLS)
    if observation_rows:
        write_clean(SOURCE, "observation", _COLLISION_DDL, observation_rows, _COLLISION_COLS)
    if sidecar_rows:
        write_clean(SOURCE, "sidecar", _SIDECAR_DDL, sidecar_rows, _SIDECAR_COLS)

    return len(snapshot_rows)
