"""Incrementally pull telemetry batches from Azure Blob Storage."""

from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import subprocess  # nosec B404 - fixed executable and argument vectors only
import tempfile
import time
from pathlib import Path
from typing import Any

from config import (
    AIDATA_SYNC_CONTAINER,
    AIDATA_SYNC_PREFIX,
    AIDATA_SYNC_STORAGE_ACCOUNT,
    GTT_XFER_DIR,
)
from state import get_watermark, set_watermark

_INHERITED_ENVIRONMENT = (
    "PATH", "HOME", "AZURE_CONFIG_DIR", "TMPDIR", "TMP", "TEMP",
    "LANG", "LC_ALL", "LC_CTYPE", "SSL_CERT_FILE", "REQUESTS_CA_BUNDLE",
)
_REFRESH_SECONDS = 60


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
    """Download new JSONL batches; an unavailable cloud is a no-op."""
    if not AIDATA_SYNC_STORAGE_ACCOUNT:
        return 0
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
