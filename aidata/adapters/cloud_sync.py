"""Incrementally pull telemetry batches from Azure Blob Storage."""

from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import subprocess  # nosec B404 - fixed executable and argument vectors only
import tempfile
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
    segments = tail.split("/")
    if any(not segment or segment == ".." for segment in segments):
        return None
    if len(segments) == 2 and not re.fullmatch(r"\d{4}-\d{2}-\d{2}", segments[0]):
        return None
    if len(segments) not in {1, 2}:
        return None
    return device_id, Path(tail).name


def pull_remote_batches() -> int:
    """Download new JSONL batches; an unavailable cloud is a no-op."""
    if not AIDATA_SYNC_STORAGE_ACCOUNT:
        return 0
    env = _child_environment()
    executable = shutil.which("az", path=env.get("PATH"))
    if not executable:
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
    watermark = dict(get_watermark("cloud_sync_batches") or {})
    downloaded = 0
    for item in listed:
        if not isinstance(item, dict):
            continue
        name = item.get("name")
        parts = _blob_parts(name) if isinstance(name, str) else None
        if not parts:
            continue
        marker = item.get("etag") or item.get("contentMd5") or item.get("properties", {}).get("etag")
        if not marker or watermark.get(name) == marker:
            continue
        device_id, filename = parts
        target_dir = GTT_XFER_DIR / "azure" / device_id
        target_dir.mkdir(parents=True, exist_ok=True)
        fd, temp_name = tempfile.mkstemp(prefix=f".{filename}.", dir=target_dir)
        os.close(fd)
        temp_path = Path(temp_name)
        try:
            if not _download(executable, env, name, temp_path):
                continue
            expected = _sha_suffix(filename)
            if expected:
                digest = hashlib.sha256(temp_path.read_bytes()).hexdigest()[:12]
                if digest != expected:
                    continue
            os.replace(temp_path, target_dir / filename)
            watermark[name] = str(marker)
            set_watermark("cloud_sync_batches", watermark)
            downloaded += 1
        except (OSError, ValueError):
            continue
        finally:
            temp_path.unlink(missing_ok=True)
    return downloaded
