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
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Iterable

from cleanio import write_clean
from rawio import read_raw, write_raw

SOURCE = "team_audit_snapshot"
_JSON_SUFFIXES = {".json", ".jsonl", ".ndjson"}
_ALLOWED_SNAPSHOT_KEYS = {
    "kind",
    "snapshotID",
    "snapshot_id",
    "snapshotId",
    "identity",
    "subjectID",
    "subject_id",
    "subjectId",
    "responsibilityLayer",
    "responsibility_layer",
    "responsibility",
    "mode",
    "capturedAt",
    "captured_at",
    "cohort",
    "cursor",
    "cursors",
    "schemaVersion",
    "schema_version",
    "instructionVersions",
    "instruction_versions",
    "axes",
    "feedbackLineage",
    "feedback_lineage",
    "agentRepeat",
    "agent_repeat",
    "limitations",
    "artifacts",
    "grill",
    "grillMeURL",
    "grillWithDocsURL",
    "sidecarID",
    "sidecar_id",
    "sidecarId",
    "sidecarHash",
    "sidecar_hash",
    "snapshotHash",
    "snapshot_hash",
    "source",
    "payload",
    "detail",
    "message",
    "note",
    "status",
    "acceptedParentSnapshotId",
    "accepted_parent_snapshot_id",
    "acceptedParentSnapshotHash",
    "accepted_parent_snapshot_hash",
}
_ALLOWED_SIDECAR_KEYS = {
    "sidecarID",
    "sidecar_id",
    "sidecarId",
    "snapshotID",
    "snapshot_id",
    "snapshotId",
    "subjectID",
    "subject_id",
    "subjectId",
    "responsibilityLayer",
    "responsibility_layer",
    "responsibility",
    "schemaVersion",
    "schema_version",
    "artifacts",
    "grill",
    "grillMeURL",
    "grillWithDocsURL",
    "kind",
    "source",
    "detail",
}


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


def _safe_read_bytes(path: Path) -> bytes | None:
    try:
        return path.read_bytes()
    except OSError:
        return None


def _safe_iterdir(path: Path) -> list[Path] | None:
    try:
        return list(path.iterdir())
    except OSError:
        return None


def _is_utc_timestamp(value: Any) -> bool:
    if not isinstance(value, str) or not value:
        return False
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return False
    if parsed.tzinfo is None:
        return False
    return parsed.utcoffset() == timedelta(0)


def _is_https_url(value: Any) -> bool:
    if not isinstance(value, str) or not value:
        return False
    try:
        parsed = __import__("urllib.parse").parse.urlparse(value)
    except Exception:
        return False
    return parsed.scheme == "https" and bool(parsed.netloc)


def _is_hex_hash(value: Any) -> bool:
    return isinstance(value, str) and len(value) == 64 and all(ch in "0123456789abcdefABCDEF" for ch in value)


def _is_string_list(value: Any) -> bool:
    return isinstance(value, list) and all(isinstance(item, str) and item for item in value)


def _validate_artifact_list(value: Any) -> bool:
    if not isinstance(value, list):
        return False
    for item in value:
        if isinstance(item, str):
            if not item:
                return False
            continue
        if not isinstance(item, dict):
            return False
        if not all(key in item for key in ("id", "kind", "hash")):
            return False
        if not _is_hex_hash(item.get("hash")):
            return False
        if not isinstance(item.get("id"), str) or not item["id"]:
            return False
        if not isinstance(item.get("kind"), str) or not item["kind"]:
            return False
        if "url" in item and not _is_https_url(item["url"]):
            return False
    return True


def _validate_bundle_shape(payload: dict[str, Any]) -> bool:
    allowed = set(_ALLOWED_SNAPSHOT_KEYS)
    unknown = set(payload) - allowed
    if unknown:
        return False
    mode = _first_value(payload, "mode")
    if mode not in ("baseline", "incremental"):
        return False
    captured_at = _first_value(payload, "capturedAt", "captured_at")
    if not _is_utc_timestamp(captured_at):
        return False
    if not _record_identity(payload, ""):
        return False
    if _first_value(payload, "subjectID", "subject_id", "subjectId") in (None, ""):
        return False
    if _first_value(payload, "responsibilityLayer", "responsibility_layer", "responsibility") in (None, ""):
        return False
    if "schemaVersion" in payload and not (payload["schemaVersion"] in (1, "1", "team-audit/v1")):
        return False
    if "schema_version" in payload and not (payload["schema_version"] in (1, "1", "team-audit/v1")):
        return False
    if not _is_string_list(payload.get("axes", [])) and payload.get("axes") is not None:
        return False
    for key in ("feedbackLineage", "feedback_lineage", "agentRepeat", "agent_repeat", "limitations"):
        if key in payload and not _is_string_list(payload[key]):
            return False
    if "grill" in payload and not _is_string_list(payload["grill"]):
        return False
    if "grillMeURL" in payload and not _is_https_url(payload["grillMeURL"]):
        return False
    if "grillWithDocsURL" in payload and not _is_https_url(payload["grillWithDocsURL"]):
        return False
    if "artifacts" in payload and not _validate_artifact_list(payload["artifacts"]):
        return False
    if mode == "baseline":
        cohort = _first_value(payload, "cohort")
        if cohort in (None, ""):
            return False
        cursor = _first_value(payload, "cursor", "cursorId", "cursor_id")
        if cursor not in (None, "") and not isinstance(cursor, str):
            return False
        cursors = payload.get("cursors")
        if cursors is not None and not (isinstance(cursors, list) and all(isinstance(x, str) and x for x in cursors)):
            return False
    else:
        cursors = payload.get("cursors")
        if cursors is None or not isinstance(cursors, list) or not cursors or not all(isinstance(x, str) and x for x in cursors):
            return False
        if "cursor" in payload and payload.get("cursor") not in (None, ""):
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
    disallowed = set(payload) - _ALLOWED_SNAPSHOT_KEYS
    if disallowed:
        return False
    if not _record_identity(payload, ""):
        return False
    if _first_value(payload, "subjectID", "subject_id", "subjectId") in (None, ""):
        return False
    if _first_value(payload, "responsibilityLayer", "responsibility_layer", "responsibility") in (None, ""):
        return False
    if _first_value(payload, "mode") not in (None, "baseline", "incremental"):
        return False
    captured_at = _first_value(payload, "capturedAt", "captured_at")
    if captured_at is None or not _is_utc_timestamp(captured_at):
        return False
    mode = _first_value(payload, "mode")
    if mode in (None, "baseline"):
        cohort = _first_value(payload, "cohort")
        if cohort in (None, ""):
            return False
    if mode == "incremental":
        cursor = _first_value(payload, "cursor", "cursorId", "cursor_id")
        if cursor in (None, ""):
            return False
    version = _first_value(payload, "schemaVersion", "schema_version")
    if version not in (None, 1, "1", "team-audit/v1"):
        return False
    for key in ("axes", "feedbackLineage", "feedback_lineage", "agentRepeat", "agent_repeat", "limitations"):
        value = payload.get(key)
        if value is not None:
            if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
                return False
    for key in ("artifacts", "grill"):
        value = payload.get(key)
        if value is not None:
            if isinstance(value, list):
                if not all(isinstance(item, (str, dict)) for item in value):
                    return False
                if any(isinstance(item, dict) and not all(k in item for k in ("id", "kind", "hash")) for item in value if isinstance(item, dict)):
                    return False
            else:
                return False
    if "sidecarHash" in payload and payload["sidecarHash"] not in (None, "") and not _is_hex_hash(payload["sidecarHash"]):
        return False
    if "grillMeURL" in payload and not _is_https_url(payload["grillMeURL"]):
        return False
    if "grillWithDocsURL" in payload and not _is_https_url(payload["grillWithDocsURL"]):
        return False
    return True


def _iter_import_files(root: Path) -> Iterable[Path]:
    try:
        root_resolved = root.resolve(strict=True)
    except OSError:
        return
    try:
        children = sorted(root_resolved.iterdir(), key=lambda p: p.name)
    except OSError:
        return
    for path in children:
        if path.is_symlink() or not path.is_dir():
            continue
        try:
            resolved = path.resolve(strict=True)
            resolved.relative_to(root_resolved)
        except (OSError, ValueError):
            continue
        snapshot_path = path / "snapshot.json"
        sidecar_path = path / "artifacts.json"
        if not snapshot_path.is_file() or snapshot_path.is_symlink():
            continue
        if not sidecar_path.is_file() or sidecar_path.is_symlink():
            continue
        entries = _safe_iterdir(path)
        if entries is None:
            continue
        json_like = {
            child.name
            for child in entries
            if child.is_file() and not child.is_symlink() and child.name.endswith((".json", ".jsonl", ".ndjson"))
        }
        if json_like - {"snapshot.json", "artifacts.json"}:
            continue
        yield path


def _read_json_text(path: Path) -> Any | None:
    raw = _safe_read_bytes(path)
    if raw is None:
        return None
    try:
        return json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        return None


def _bundle_from_file(bundle_dir: Path, root: Path) -> dict[str, Any] | None:
    snapshot_path = bundle_dir / "snapshot.json"
    sidecar_path = bundle_dir / "artifacts.json"
    if not snapshot_path.exists() or not sidecar_path.exists():
        return None
    if snapshot_path.is_symlink() or sidecar_path.is_symlink():
        return None

    json_like = {
        child.name
        for child in bundle_dir.iterdir()
        if child.is_file() and not child.is_symlink() and child.name.endswith((".json", ".jsonl", ".ndjson"))
    }
    if json_like - {"snapshot.json", "artifacts.json"}:
        return None

    snapshot_raw = _read_json_text(snapshot_path)
    sidecar_raw = _read_json_text(sidecar_path)
    if not isinstance(snapshot_raw, dict) or not isinstance(sidecar_raw, dict):
        return None

    snapshot_id = _first_value(snapshot_raw, "snapshotID", "snapshot_id", "snapshotId", "identity")
    sidecar_id = _first_value(sidecar_raw, "sidecarID", "sidecar_id", "sidecarId")
    if snapshot_id in (None, "") or sidecar_id in (None, ""):
        return None
    if _first_value(snapshot_raw, "subjectID", "subject_id", "subjectId") != _first_value(sidecar_raw, "subjectID", "subject_id", "subjectId"):
        return None
    if _first_value(snapshot_raw, "responsibilityLayer", "responsibility_layer", "responsibility") != _first_value(sidecar_raw, "responsibilityLayer", "responsibility_layer", "responsibility"):
        return None

    snapshot_bytes = _safe_read_bytes(snapshot_path)
    sidecar_bytes = _safe_read_bytes(sidecar_path)
    if snapshot_bytes is None or sidecar_bytes is None:
        return None
    snapshot_hash = _hash_bytes(snapshot_bytes)
    sidecar_hash = _hash_bytes(sidecar_bytes)
    declared_sidecar_hash = _first_value(snapshot_raw, "sidecarHash", "sidecar_hash")
    if declared_sidecar_hash is not None and declared_sidecar_hash != sidecar_hash:
        return None
    if _first_value(sidecar_raw, "sidecarHash", "sidecar_hash") not in (None, sidecar_hash):
        return None

    payload = {**snapshot_raw}
    payload["sidecarID"] = sidecar_id
    payload["sidecarHash"] = sidecar_hash
    payload["snapshotHash"] = snapshot_hash
    payload["schemaVersion"] = _first_value(snapshot_raw, "schemaVersion", "schema_version") or "team-audit/v1"
    if not _is_contract_payload(payload):
        return None
    if not _contract_valid(payload):
        return None
    return {
        "kind": "snapshot",
        "identity": snapshot_id,
        "hash": snapshot_hash,
        "source_path": str(snapshot_path),
        "payload": payload,
        "cohort": _first_value(payload, "cohort"),
        "cursor": _first_value(payload, "cursor"),
        "subject_id": _first_value(payload, "subjectID", "subject_id", "subjectId"),
        "responsibility_layer": _first_value(payload, "responsibilityLayer", "responsibility_layer", "responsibility"),
        "feedback_lineage": _normalize_value(payload.get("feedbackLineage", payload.get("feedback_lineage"))),
        "agent_repeat": _normalize_value(payload.get("agentRepeat", payload.get("agent_repeat"))),
        "limitations": _normalize_value(payload.get("limitations")),
        "artifacts": _normalize_value(payload.get("artifacts")),
        "grill": _normalize_value(payload.get("grill")),
        "sidecar_id": sidecar_id,
        "sidecar_hash": sidecar_hash,
        "parent_snapshot_id": None,
        "parent_snapshot_hash": None,
        "observed_at": _first_value(payload, "capturedAt", "captured_at"),
        "source": SOURCE,
        "mode": _first_value(payload, "mode"),
        "captured_at": _first_value(payload, "capturedAt", "captured_at"),
        "schema_version": payload["schemaVersion"],
        "detail": _first_value(payload, "detail", "message", "note"),
    }


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
    if mode is None or mode not in {"baseline", "incremental"}:
        return False
    cohort = _first_value(payload, "cohort")
    if cohort in (None, ""):
        return False
    cursor = _first_value(payload, "cursor", "cursorId", "cursor_id")
    if mode == "incremental" and cursor in (None, ""):
        return False
    if _first_value(payload, "schemaVersion", "schema_version") not in (None, 1, "1", "team-audit/v1"):
        return False
    axes = payload.get("axes")
    if axes is not None and (not isinstance(axes, list) or not all(isinstance(item, str) for item in axes)):
        return False
    for key in ("feedbackLineage", "feedback_lineage", "agentRepeat", "agent_repeat", "limitations"):
        value = payload.get(key)
        if value is not None and (not isinstance(value, list) or not all(isinstance(item, str) for item in value)):
            return False
    artifacts = payload.get("artifacts")
    if artifacts is not None:
        if not isinstance(artifacts, list):
            return False
        for item in artifacts:
            if isinstance(item, str):
                if not item:
                    return False
            elif isinstance(item, dict):
                if not all(k in item for k in ("id", "kind", "hash")):
                    return False
                if not isinstance(item["id"], str) or not item["id"]:
                    return False
                if not isinstance(item["kind"], str) or not item["kind"]:
                    return False
                if not _is_hex_hash(item["hash"]):
                    return False
            else:
                return False
    grill = payload.get("grill")
    if grill is not None and (not isinstance(grill, list) or not all(isinstance(item, str) for item in grill)):
        return False
    if "sidecarHash" in payload and payload["sidecarHash"] not in (None, "") and not _is_hex_hash(payload["sidecarHash"]):
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

    raw_records = read_raw(SOURCE)
    existing: set[tuple[str, str]] = {(r.get("identity"), r.get("hash")) for r in raw_records if r.get("identity") and r.get("hash")}
    accepted_by_identity: dict[str, str] = {}
    for rec in raw_records:
        if rec.get("kind") == "observation":
            continue
        identity = rec.get("identity")
        digest = rec.get("hash")
        if identity and digest:
            accepted_by_identity[identity] = str(digest)
    batch: list[dict[str, Any]] = []

    for bundle_dir in _iter_import_files(root):
        payload = _bundle_from_file(bundle_dir, root)
        if payload is None:
            continue
        snapshot_id = payload["identity"]
        digest = payload["hash"]
        rec_key = (snapshot_id, digest)
        if rec_key in existing:
            continue
        prev_hash = accepted_by_identity.get(snapshot_id)
        if prev_hash is None:
            batch.append({
                "kind": "snapshot",
                "identity": snapshot_id,
                "hash": digest,
                "source": SOURCE,
                "source_path": payload["source_path"],
                "payload": payload["payload"],
                "cohort": payload["cohort"],
                "cursor": payload["cursor"],
                "subject_id": payload["subject_id"],
                "responsibility_layer": payload["responsibility_layer"],
                "feedback_lineage": payload["feedback_lineage"],
                "agent_repeat": payload["agent_repeat"],
                "limitations": payload["limitations"],
                "artifacts": payload["artifacts"],
                "grill": payload["grill"],
                "sidecar_id": payload["sidecar_id"],
                "sidecar_hash": payload["sidecar_hash"],
                "parent_snapshot_id": None,
                "parent_snapshot_hash": None,
                "observed_at": payload["observed_at"],
                "mode": payload["mode"],
                "captured_at": payload["captured_at"],
                "schema_version": payload["schema_version"],
                "detail": payload["detail"],
            })
            accepted_by_identity[snapshot_id] = digest
            existing.add(rec_key)
            continue
        if prev_hash == digest:
            continue
        obs = _observation_record(
            snapshot_id,
            digest,
            parent_snapshot_id=snapshot_id,
            parent_snapshot_hash=prev_hash,
            detail="replayed snapshot differs from accepted parent",
        )
        obs_key = (obs["identity"], obs["hash"])
        if obs_key not in existing:
            batch.append(obs)
            existing.add(obs_key)

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
    identity = rec.get("identity") or parent_snapshot_id or "unknown"
    digest = rec.get("hash") or ""
    return {
        "observation_id": f"obs:{identity}:{digest}",
        "snapshot_id": rec.get("identity") or parent_snapshot_id,
        "observation_kind": rec.get("observation_kind") or "collision",
        "detail": rec.get("detail") or "identity hash collision",
        "parent_snapshot_id": parent_snapshot_id,
        "parent_snapshot_hash": parent_hash,
        "identity": identity,
        "content_hash": digest,
        "observed_at": rec.get("observed_at") or rec.get("captured_at") or datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "source": rec.get("source") or SOURCE,
        "disposition": rec.get("disposition") or "rejected",
        "limitation": rec.get("limitation") or "same snapshot identity with different hash",
    }


def _sidecar_row(rec: dict[str, Any]) -> dict[str, Any] | None:
    sidecar_id = rec.get("sidecar_id")
    if not sidecar_id:
        return None
    sidecar_hash = rec.get("sidecar_hash") or rec.get("hash")
    if sidecar_hash is None:
        return None
    return {
        "sidecar_id": sidecar_id,
        "snapshot_id": rec.get("identity"),
        "sidecar_hash": sidecar_hash,
        "kind": rec.get("kind") or "sidecar",
        "source_path": rec.get("source_path"),
        "content_hash": sidecar_hash,
        "observed_at": rec.get("observed_at") or rec.get("captured_at"),
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
    seen_observation_ids: set[str] = set()

    for rec in raw_records:
        rec = dict(rec)
        identity = rec.get("identity")
        if not identity:
            continue
        digest = str(rec.get("hash") or "")

        if rec.get("kind") == "observation":
            row = _observation_row(rec, parent_snapshot_id=rec.get("parent_snapshot_id"), parent_hash=rec.get("parent_snapshot_hash"))
            if row["observation_id"] not in seen_observation_ids:
                observation_rows.append(row)
                seen_observation_ids.add(row["observation_id"])
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

        row = _observation_row(rec, parent_snapshot_id=identity, parent_hash=existing.get("hash"))
        if row["observation_id"] not in seen_observation_ids:
            observation_rows.append(row)
            seen_observation_ids.add(row["observation_id"])

    if snapshot_rows:
        write_clean(SOURCE, "snapshot", _SNAPSHOT_DDL, snapshot_rows, _SNAPSHOT_COLS)
    if observation_rows:
        write_clean(SOURCE, "observation", _COLLISION_DDL, observation_rows, _COLLISION_COLS)
    if sidecar_rows:
        write_clean(SOURCE, "sidecar", _SIDECAR_DDL, sidecar_rows, _SIDECAR_COLS)

    return len(snapshot_rows)
