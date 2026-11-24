"""Incrementally pull telemetry batches from Azure Blob Storage."""

from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import socket
import subprocess  # nosec B404 - fixed executable and argument vectors only
import tempfile
import time
from collections.abc import Sequence
from pathlib import Path
from typing import Any

from config import (
    AIDATA_SYNC_CONTAINER,
    AIDATA_SYNC_PREFIX,
    AIDATA_SYNC_STORAGE_ACCOUNT,
    GTT_XFER_DIR,
    RAW_DIR,
    resolve_icloud_sync_dir,
)
from rawio import raw_source_lock
from state import get_watermark, set_watermark

_INHERITED_ENVIRONMENT = (
    "PATH", "HOME", "AZURE_CONFIG_DIR", "TMPDIR", "TMP", "TEMP",
    "LANG", "LC_ALL", "LC_CTYPE", "SSL_CERT_FILE", "REQUESTS_CA_BUNDLE",
)
_REFRESH_SECONDS = 60
_ICLOUD_EXPORT_WATERMARK = "icloud_exported_shards_v1"
_ICLOUD_PULL_WATERMARK = "icloud_pulled_shards_v1"
_ICLOUD_SOURCES = (
    "claude_jsonl", "codex_prompts", "copilot_cli",
    "gtt_ledger", "gtt_receipt", "bot_tl",
)
_SAFE_COMPONENT_RE = re.compile(r"^[A-Za-z0-9._-]+$")


def _file_signature(path: Path) -> str | None:
    try:
        digest = hashlib.sha256()
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
        return digest.hexdigest()
    except OSError:
        return None


def _copy_atomically(source: Path, destination: Path) -> bool:
    destination.parent.mkdir(parents=True, exist_ok=True)
    temp_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="wb", dir=destination.parent, prefix=f".{destination.name}.", delete=False
        ) as handle:
            temp_path = Path(handle.name)
            with source.open("rb") as source_handle:
                shutil.copyfileobj(source_handle, handle)
            handle.flush()
            os.fsync(handle.fileno())
        temp_path.replace(destination)
        directory = os.open(destination.parent, os.O_RDONLY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
        return True
    except OSError:
        return False
    finally:
        if temp_path is not None:
            temp_path.unlink(missing_ok=True)


def _safe_shard_path(root: Path, *parts: str) -> Path | None:
    if root.is_symlink():
        return None
    if any(not part or part in {".", ".."} or not _SAFE_COMPONENT_RE.fullmatch(part) for part in parts):
        return None
    candidate = root.joinpath(*parts)
    try:
        if not candidate.resolve().is_relative_to(root.resolve()):
            return None
    except OSError:
        return None
    parent = root
    for part in parts[:-1]:
        parent = parent / part
        if parent.is_symlink():
            return None
    return candidate


def export_local_telemetry_shards(
    *,
    sync_dir: Path | None = None,
    sources: Sequence[str] = _ICLOUD_SOURCES,
) -> int:
    """Export changed local raw shards to this host's iCloud shard directory."""
    resolved_sync = resolve_icloud_sync_dir(sync_dir)
    if resolved_sync is None:
        return 0
    hostname = socket.gethostname()
    if not _SAFE_COMPONENT_RE.fullmatch(hostname):
        return 0
    previous = get_watermark(_ICLOUD_EXPORT_WATERMARK)
    watermark = dict(previous) if isinstance(previous, dict) else {}
    exported = 0
    changed = False
    for source in sources:
        if source not in _ICLOUD_SOURCES:
            continue
        source_dir = RAW_DIR / source
        if source_dir.is_symlink() or not source_dir.is_dir():
            continue
        try:
            shards = sorted(source_dir.glob("*.jsonl"))
        except OSError:
            continue
        for shard in shards:
            if shard.is_symlink() or shard.name.startswith("icloud-") or not shard.is_file():
                continue
            signature = _file_signature(shard)
            if signature is None:
                continue
            destination = _safe_shard_path(
                resolved_sync / "telemetry-shards", hostname, source, shard.name
            )
            if destination is None:
                continue
            key = f"{source}/{shard.name}"
            if watermark.get(key) == signature and destination.is_file():
                continue
            if destination.is_file() and _file_signature(destination) == signature:
                watermark[key] = signature
                changed = True
                continue
            if _copy_atomically(shard, destination):
                watermark[key] = signature
                changed = True
                exported += 1
    if changed:
        set_watermark(_ICLOUD_EXPORT_WATERMARK, watermark)
    return exported


def pull_icloud_telemetry_shards(*, sync_dir: Path | None = None) -> int:
    """Import changed telemetry shards from other hosts into local collectors."""
    resolved_sync = resolve_icloud_sync_dir(sync_dir)
    if resolved_sync is None:
        return 0
    shard_root = resolved_sync / "telemetry-shards"
    if shard_root.is_symlink() or not shard_root.is_dir():
        return 0
    hostname = socket.gethostname()
    previous = get_watermark(_ICLOUD_PULL_WATERMARK)
    watermark = dict(previous) if isinstance(previous, dict) else {}
    imported = 0
    changed = False
    try:
        host_dirs = sorted(shard_root.iterdir())
    except OSError:
        return 0
    for host_dir in host_dirs:
        remote_host = host_dir.name
        if remote_host == hostname or host_dir.is_symlink() or not host_dir.is_dir():
            continue
        if not _SAFE_COMPONENT_RE.fullmatch(remote_host):
            continue
        for source in _ICLOUD_SOURCES:
            source_dir = host_dir / source
            if source_dir.is_symlink() or not source_dir.is_dir():
                continue
            try:
                shards = sorted(source_dir.glob("*.jsonl"))
            except OSError:
                continue
            for shard in shards:
                if shard.is_symlink() or not shard.is_file() or not _SAFE_COMPONENT_RE.fullmatch(shard.name):
                    continue
                signature = _file_signature(shard)
                if signature is None:
                    continue
                key = f"{remote_host}/{source}/{shard.name}"
                if source in {"gtt_ledger", "gtt_receipt", "bot_tl"}:
                    destination = _safe_shard_path(
                        GTT_XFER_DIR / "icloud", remote_host, f"{source}-{shard.name}"
                    )
                    lock = None
                else:
                    destination = _safe_shard_path(
                        RAW_DIR / source, f"icloud-{remote_host}-{shard.name}"
                    )
                    lock = raw_source_lock(RAW_DIR / source)
                if destination is None:
                    continue
                if watermark.get(key) == signature and destination.is_file():
                    continue
                if destination.is_file() and _file_signature(destination) == signature:
                    watermark[key] = signature
                    changed = True
                    continue
                try:
                    if lock is None:
                        copied = _copy_atomically(shard, destination)
                    else:
                        with lock:
                            copied = _copy_atomically(shard, destination)
                except (OSError, TimeoutError):
                    copied = False
                if copied:
                    watermark[key] = signature
                    changed = True
                    imported += 1
    if changed:
        set_watermark(_ICLOUD_PULL_WATERMARK, watermark)
    return imported


def _child_environment() -> dict[str, str]:
    environment = {
        key: os.environ[key]
        for key in _INHERITED_ENVIRONMENT
        if key in os.environ
    }
    environment.update({
        "AZURE_CLOUD_NAME": "AzureCloud",
        "AZURE_LOGGING_ENABLE_FILE_LOGGING": "false",
        "AZURE_CORE_COLLECT_TELEMETRY": "false",
    })
    return environment


def _run_json(executable: str, arguments: list[str], env: dict[str, str]) -> Any:
    result = subprocess.run(  # nosec B603
        [executable, *arguments],
        capture_output=True,
        text=True,
        env=env,
        shell=False,
        check=False,
    )
    if result.returncode != 0:
        return None
    try:
        return json.loads(result.stdout)
    except (TypeError, json.JSONDecodeError):
        return None


def _download(
    executable: str,
    env: dict[str, str],
    blob_name: str,
    destination: Path,
) -> bool:
    result = subprocess.run(  # nosec B603
        [
            executable, "storage", "blob", "download",
            "--account-name", AIDATA_SYNC_STORAGE_ACCOUNT,
            "--container-name", AIDATA_SYNC_CONTAINER,
            "--name", blob_name,
            "--file", str(destination),
            "--auth-mode", "login",
            "--overwrite", "true",
            "--output", "none",
            "--only-show-errors",
        ],
        capture_output=True,
        text=True,
        env=env,
        shell=False,
        check=False,
    )
    return result.returncode == 0


def _sha_suffix(filename: str) -> str | None:
    stem = Path(filename).stem
    parts = stem.rsplit("_", 1)
    return parts[1] if len(parts) == 2 and len(parts[1]) == 12 else None


def _blob_parts(name: str) -> tuple[str, str] | None:
    marker = f"{AIDATA_SYNC_PREFIX}/machines/"
    if not name.startswith(marker) or not name.endswith(".jsonl"):
        return None
    relative = name[len(marker):]
    device_id, separator, tail = relative.partition("/batches/")
    if not separator or not device_id or not tail:
        return None
    if not re.fullmatch(r"[A-Za-z0-9._-]+", device_id):
        return None
    segments = tail.split("/")
    if any(not segment or segment in {".", ".."} for segment in segments):
        return None
    if len(segments) == 2 and not re.fullmatch(r"\d{4}-\d{2}-\d{2}", segments[0]):
        return None
    if len(segments) not in {1, 2}:
        return None
    filename = Path(tail).name
    if not re.fullmatch(r"[A-Za-z0-9._-]+\.jsonl", filename):
        return None
    return device_id, tail


def pull_remote_batches() -> int:
    """Pull iCloud shards and download new Azure JSONL batches."""
    imported = pull_icloud_telemetry_shards()
    if not AIDATA_SYNC_STORAGE_ACCOUNT:
        return imported
    env = _child_environment()
    executable = shutil.which("az", path=env.get("PATH"))
    if not executable:
        return 0
    # Scheduled collectors run in separate processes. Share a short successful
    # refresh window so all three adapters consume one listing/download pass.
    scope = [AIDATA_SYNC_STORAGE_ACCOUNT, AIDATA_SYNC_CONTAINER, AIDATA_SYNC_PREFIX, str(GTT_XFER_DIR.resolve()), "dated-path-v2"]
    refresh = get_watermark("cloud_sync_refresh") or {}
    now = time.time()
    if refresh.get("scope") == scope and 0 <= now - refresh.get("completed_at", 0) < _REFRESH_SECONDS:
        return 0
    prefix = f"{AIDATA_SYNC_PREFIX}/machines/"
    listed = _run_json(
        executable,
        [
            "storage", "blob", "list",
            "--account-name", AIDATA_SYNC_STORAGE_ACCOUNT,
            "--container-name", AIDATA_SYNC_CONTAINER,
            "--prefix", prefix,
            "--auth-mode", "login", "-o", "json", "--only-show-errors",
        ],
        env,
    )
    if not isinstance(listed, list):
        return 0
    # Invalidate flattened-layout watermarks, including undated files that
    # may have been overwritten by a dated batch with the same basename.
    watermark = dict(get_watermark("cloud_sync_batches_v2") or {})
    downloaded = 0
    complete = True
    for item in listed:
        if not isinstance(item, dict):
            continue
        name = item.get("name")
        parts = _blob_parts(name) if isinstance(name, str) else None
        if not parts:
            continue
        marker = item.get("etag") or item.get("contentMd5") or item.get("properties", {}).get("etag")
        if not marker:
            continue
        device_id, relative_path = parts
        filename = Path(relative_path).name
        sync_root = (GTT_XFER_DIR / "azure").resolve()
        target = sync_root / device_id / relative_path
        # Validate every directory, including the optional date component.
        parents = [sync_root / device_id, target.parent]
        if any(path.is_symlink() or not path.resolve().is_relative_to(sync_root) for path in parents):
            complete = False
            continue
        if target.is_symlink() or not target.resolve().is_relative_to(sync_root):
            complete = False
            continue
        # Recover deleted local targets even if their ETag is unchanged.
        if watermark.get(name) == marker and target.is_file():
            continue
        target_dir = target.parent
        try:
            target_dir.mkdir(parents=True, exist_ok=True)
            fd, temp_name = tempfile.mkstemp(prefix=f".{filename}.", dir=target_dir)
        except OSError:
            complete = False
            continue
        os.close(fd)
        temp_path = Path(temp_name)
        try:
            if not _download(executable, env, name, temp_path):
                complete = False
                continue
            expected = _sha_suffix(filename)
            if expected:
                digest = hashlib.sha256(temp_path.read_bytes()).hexdigest()[:12]
                if digest != expected:
                    complete = False
                    continue
            os.replace(temp_path, target)
            watermark[name] = str(marker)
            set_watermark("cloud_sync_batches_v2", watermark)
            downloaded += 1
        except (OSError, ValueError):
            complete = False
            continue
        finally:
            temp_path.unlink(missing_ok=True)
    if complete:
        set_watermark("cloud_sync_refresh", {"scope": scope, "completed_at": time.time()})
    return downloaded
