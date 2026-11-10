"""Manual opaque Azure Blob batch landing.

This adapter is intentionally outside the generic source registry. It invokes
the installed Azure CLI once, validates an opaque downloaded tree, and commits
the whole tree as one immutable L1 completion directory.
"""

from __future__ import annotations

import json
import os
import shutil
import stat
import subprocess  # nosec B404 - fixed executable and argument vectors only
import tempfile
import uuid
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit

from config import RAW_DIR

_AZURE_CLI_VERSION = "2.91.0"
_INHERITED_ENVIRONMENT = (
    "PATH",
    "HOME",
    "AZURE_CONFIG_DIR",
    "TMPDIR",
    "TMP",
    "TEMP",
    "LANG",
    "LC_ALL",
    "LC_CTYPE",
    "SSL_CERT_FILE",
    "REQUESTS_CA_BUNDLE",
)
_FIXED_ENVIRONMENT = {
    "AZURE_CLOUD_NAME": "AzureCloud",
    "AZURE_LOGGING_ENABLE_LOG_FILE": "false",
    "AZURE_CORE_COLLECT_TELEMETRY": "false",
}
_CLOUD_QUERY = (
    "{name:name,isActive:isActive,"
    "storageEndpoint:suffixes.storageEndpoint,"
    "resourceManager:endpoints.resourceManager}"
)


def _child_environment() -> dict[str, str]:
    environment = {
        name: os.environ[name]
        for name in _INHERITED_ENVIRONMENT
        if name in os.environ
    }
    environment.update(_FIXED_ENVIRONMENT)
    return environment


def _azure_executable(environment: dict[str, str]) -> str:
    executable = shutil.which("az", path=environment.get("PATH"))
    if executable is None:
        raise RuntimeError("Azure CLI unavailable")
    path = Path(executable).resolve(strict=True)
    if not path.is_file() or not os.access(path, os.X_OK):
        raise RuntimeError("Azure CLI unavailable")
    return str(path)


def _run_json(
    executable: str,
    arguments: list[str],
    environment: dict[str, str],
) -> Any:
    process = subprocess.run(  # nosec B603
        [executable, *arguments],
        capture_output=True,
        text=True,
        env=environment,
        shell=False,
        check=False,
    )
    if process.returncode != 0:
        raise RuntimeError("Azure CLI preflight failed")
    try:
        return json.loads(process.stdout)
    except (json.JSONDecodeError, TypeError) as error:
        raise RuntimeError("Azure CLI preflight failed") from error


def _preflight(executable: str, environment: dict[str, str]) -> None:
    version = _run_json(
        executable,
        ["version", "--output", "json", "--only-show-errors"],
        environment,
    )
    if (
        not isinstance(version, dict)
        or version.get("azure-cli") != _AZURE_CLI_VERSION
        or version.get("azure-cli-core") != _AZURE_CLI_VERSION
        or version.get("extensions") != {}
    ):
        raise RuntimeError("Azure CLI preflight failed")

    cloud = _run_json(
        executable,
        [
            "cloud",
            "show",
            "--name",
            "AzureCloud",
            "--query",
            _CLOUD_QUERY,
            "--output",
            "json",
            "--only-show-errors",
        ],
        environment,
    )
    if (
        not isinstance(cloud, dict)
        or set(cloud) != {
            "name",
            "isActive",
            "storageEndpoint",
            "resourceManager",
        }
        or cloud.get("name") != "AzureCloud"
        or cloud.get("isActive") is not True
        or cloud.get("storageEndpoint") != "core.windows.net"
        or cloud.get("resourceManager") != "https://management.azure.com/"
        or any(
            not isinstance(cloud.get(field), str)
            for field in ("name", "storageEndpoint", "resourceManager")
        )
    ):
        raise RuntimeError("Azure CLI preflight failed")


def _ensure_private_directory(path: Path) -> None:
    try:
        metadata = path.lstat()
    except FileNotFoundError:
        path.mkdir(mode=0o700, parents=True)
        metadata = path.lstat()
    if (
        not stat.S_ISDIR(metadata.st_mode)
        or stat.S_ISLNK(metadata.st_mode)
        or metadata.st_uid != os.geteuid()
        or stat.S_IMODE(metadata.st_mode) & 0o077
    ):
        raise RuntimeError("unsafe product Blob directory")


def _private_roots() -> tuple[Path, Path, Path]:
    product_root = RAW_DIR / "product_blob"
    staging_root = product_root / ".staging"
    completion_root = product_root / "batches"
    for path in (product_root, staging_root, completion_root):
        _ensure_private_directory(path)
    return product_root, staging_root, completion_root


def _validate_stage(stage: Path) -> tuple[list[Path], list[Path]]:
    root = stage.resolve(strict=True)
    files: list[Path] = []
    directories: list[Path] = [stage]
    pending = [stage]
    while pending:
        directory = pending.pop()
        with os.scandir(directory) as entries:
            for entry in entries:
                path = Path(entry.path)
                metadata = path.lstat()
                if (
                    entry.is_symlink()
                    or metadata.st_uid != os.geteuid()
                    or stat.S_IMODE(metadata.st_mode) & 0o077
                ):
                    raise RuntimeError("unsafe product Blob output")
                resolved = path.resolve(strict=True)
                try:
                    resolved.relative_to(root)
                except ValueError as error:
                    raise RuntimeError("unsafe product Blob output") from error
                if stat.S_ISDIR(metadata.st_mode):
                    directories.append(path)
                    pending.append(path)
                elif stat.S_ISREG(metadata.st_mode):
                    files.append(path)
                else:
                    raise RuntimeError("unsafe product Blob output")
    return files, directories


def _fsync_file(path: Path) -> None:
    descriptor = os.open(path, os.O_RDONLY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def _fsync_directory(path: Path) -> None:
    descriptor = os.open(path, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def _fsync_stage(files: list[Path], directories: list[Path]) -> None:
    for path in sorted(files):
        _fsync_file(path)
    for path in sorted(
        directories,
        key=lambda candidate: len(candidate.parts),
        reverse=True,
    ):
        _fsync_directory(path)


def _post_commit() -> None:
    pass


def _download(
    executable: str,
    environment: dict[str, str],
    account: str,
    container: str,
    prefix: str,
    stage: Path,
) -> None:
    process = subprocess.run(  # nosec B603
        [
            executable,
            "storage",
            "blob",
            "download-batch",
            "--account-name",
            account,
            "--source",
            container,
            "--pattern",
            f"{prefix}/*",
            "--destination",
            str(stage),
            "--auth-mode",
            "login",
            "--overwrite",
            "false",
            "--output",
            "none",
            "--no-progress",
            "--only-show-errors",
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        env=environment,
        shell=False,
        check=False,
    )
    if process.returncode != 0:
        raise RuntimeError("Azure Blob batch failed")


def collect(container_url: str, prefix: str) -> dict[str, object]:
    """Land one manual batch, or return an empty result.

    Raises an exception for process, validation, or filesystem failure. The
    caller owns neutral public error rendering. A failure after the atomic
    rename leaves the completed directory intact because that rename is the
    commit point.
    """
    parsed = urlsplit(container_url)
    account = parsed.hostname.split(".", 1)[0]
    container = parsed.path.removeprefix("/")
    environment = _child_environment()
    executable = _azure_executable(environment)

    old_umask = os.umask(0o077)
    stage: Path | None = None
    try:
        _product_root, staging_root, completion_root = _private_roots()
        _preflight(executable, environment)
        stage = Path(tempfile.mkdtemp(prefix="run-", dir=staging_root))
        batch_id = str(uuid.uuid4())
        destination = completion_root / batch_id
        if destination.exists():
            raise RuntimeError("product Blob completion already exists")

        _download(
            executable,
            environment,
            account,
            container,
            prefix,
            stage,
        )
        files, directories = _validate_stage(stage)
        if not files:
            return {"status": "empty", "objectCount": 0}
        _fsync_stage(files, directories)
        os.replace(stage, destination)
        _fsync_directory(destination)
        _fsync_directory(completion_root)
        _post_commit()
        return {
            "status": "completed",
            "batchId": batch_id,
            "objectCount": len(files),
        }
    finally:
        os.umask(old_umask)
        if stage is not None and stage.exists():
            shutil.rmtree(stage)


SOURCE = "product_blob"
_CANONICAL_APPS = {
    "aidash": "AIDash",
    "vitalstride": "VitalStride",
    "voxpocket": "VoxPocket",
    "financial": "Financial",
}
_TELEMETRY_DDL = """CREATE TABLE product_telemetry (
    event_id TEXT PRIMARY KEY,
    app_name TEXT NOT NULL,
    app_version TEXT,
    build_number TEXT,
    platform TEXT,
    event_kind TEXT NOT NULL,
    signature TEXT,
    stack_top_symbol TEXT,
    metric_ms REAL,
    occurred_at TEXT NOT NULL
)"""
_TELEMETRY_COLS = (
    "event_id",
    "app_name",
    "app_version",
    "build_number",
    "platform",
    "event_kind",
    "signature",
    "stack_top_symbol",
    "metric_ms",
    "occurred_at",
)


def _canonical_app_name(raw_value: Any) -> str | None:
    text = str(raw_value or "").strip()
    if not text:
        return None
    lower = text.lower()
    for key, canonical in _CANONICAL_APPS.items():
        if lower == key or lower.startswith(f"{key}.") or f".{key}" in lower:
            return canonical
    return text


def _classify_event_kind(raw_kind: Any, event_name: str, props: dict[str, Any]) -> str:
    explicit = str(raw_kind or "").strip().lower()
    if explicit in {"crash", "perf", "error"}:
        return explicit
    lower_name = event_name.lower()
    if any(tok in lower_name for tok in ("crash", "fatal", "exception", "panic", "abort")):
        return "crash"
    if any(tok in lower_name for tok in ("error", "fail")):
        return "error"
    if (
        any(tok in lower_name for tok in ("perf", "performance", "latency", "launch", "ready_scene", "frame", "slow"))
        or "duration_ms" in props
        or "metric_ms" in props
        or "latency_ms" in props
    ):
        return "perf"
    return "perf" if props.get("metric_ms") is not None else "error"


def _parse_telemetry_record(
    raw: dict[str, Any],
    *,
    rel_path: str = "",
    line_no: int = 1,
) -> dict[str, Any] | None:
    import hashlib
    from datetime import datetime, timezone

    props = raw.get("properties") if isinstance(raw.get("properties"), dict) else {}
    path_parts = [p for p in Path(rel_path).parts if p not in {".", "batches", "product_blob"}]
    inferred_app = _canonical_app_name(
        raw.get("app_name")
        or raw.get("app")
        or props.get("app_name")
        or props.get("app")
        or (str(raw.get("name") or "").split(".", 1)[0] if "." in str(raw.get("name") or "") else None)
        or (path_parts[1] if len(path_parts) >= 2 else (path_parts[0] if path_parts else None))
    )
    if not inferred_app:
        return None

    inferred_build = str(
        raw.get("build_number")
        or raw.get("build")
        or props.get("build_number")
        or props.get("build")
        or (path_parts[2] if len(path_parts) >= 3 else "")
    ).strip() or None
    app_version = str(
        raw.get("app_version")
        or raw.get("version")
        or props.get("app_version")
        or props.get("version")
        or ""
    ).strip() or None
    platform = str(
        raw.get("platform")
        or props.get("platform")
        or ("macos" if inferred_app in {"AIDash", "VoxPocket"} else "ios")
    ).strip() or None

    event_name = str(raw.get("name") or raw.get("event_name") or raw.get("signature") or "").strip()
    event_kind = _classify_event_kind(
        raw.get("event_kind") or props.get("event_kind"),
        event_name,
        props,
    )
    stack_top_symbol = str(
        raw.get("stack_top_symbol")
        or props.get("stack_top_symbol")
        or props.get("symbol")
        or raw.get("symbol")
        or ""
    ).strip() or None
    signature = str(
        raw.get("signature")
        or props.get("signature")
        or props.get("crash_signature")
        or event_name
        or stack_top_symbol
        or f"{inferred_app}.{event_kind}"
    ).strip()

    raw_metric = (
        raw.get("metric_ms")
        if raw.get("metric_ms") is not None
        else raw.get("duration_ms")
        if raw.get("duration_ms") is not None
        else props.get("metric_ms")
        if props.get("metric_ms") is not None
        else props.get("duration_ms")
        if props.get("duration_ms") is not None
        else props.get("latency_ms")
    )
    metric_ms: float | None = None
    if raw_metric is not None and not isinstance(raw_metric, bool):
        try:
            metric_val = float(raw_metric)
            if metric_val >= 0:
                metric_ms = metric_val
        except (TypeError, ValueError):
            metric_ms = None

    raw_ts = (
        raw.get("occurred_at")
        or raw.get("timestamp")
        or raw.get("ts")
        or props.get("occurred_at")
        or props.get("timestamp")
    )
    if not raw_ts:
        return None
    occurred_at = str(raw_ts).strip()
    try:
        parsed_dt = datetime.fromisoformat(occurred_at.replace("Z", "+00:00"))  # noqa: FURB162
        if parsed_dt.tzinfo is None:
            parsed_dt = parsed_dt.replace(tzinfo=timezone.utc)  # noqa: UP017
        occurred_at = (
            parsed_dt.astimezone(timezone.utc)  # noqa: UP017
            .isoformat()
            .replace("+00:00", "Z")
        )
    except ValueError:
        return None

    explicit_id = str(raw.get("event_id") or raw.get("id") or props.get("event_id") or "").strip()
    if explicit_id:
        event_id = explicit_id
    else:
        digest_input = json.dumps(
            [rel_path, line_no, inferred_app, inferred_build, event_kind, signature, stack_top_symbol, metric_ms, occurred_at],
            ensure_ascii=False,
        )
        event_id = f"pt-{hashlib.sha256(digest_input.encode('utf-8')).hexdigest()[:24]}"

    return {
        "event_id": event_id,
        "app_name": inferred_app,
        "app_version": app_version,
        "build_number": inferred_build,
        "platform": platform,
        "event_kind": event_kind,
        "signature": signature,
        "stack_top_symbol": stack_top_symbol,
        "metric_ms": metric_ms,
        "occurred_at": occurred_at,
    }


def _iter_raw_telemetry_records() -> list[dict[str, Any]]:
    import gzip

    product_root = RAW_DIR / SOURCE
    if not product_root.is_dir():
        return []
    candidates: list[Path] = []
    batches_dir = product_root / "batches"
    if batches_dir.is_dir():
        candidates.extend(sorted(p for p in batches_dir.rglob("*") if p.is_file()))
    candidates.extend(sorted(p for p in product_root.glob("*.jsonl") if p.is_file()))

    rows_by_id: dict[str, dict[str, Any]] = {}
    for file_path in candidates:
        try:
            rel_path = str(file_path.relative_to(product_root))
        except ValueError:
            rel_path = file_path.name
        if ".staging" in Path(rel_path).parts:
            continue
        try:
            raw_bytes = file_path.read_bytes()
            if file_path.suffix == ".gz" or raw_bytes.startswith(b"\x1f\x8b"):
                text = gzip.decompress(raw_bytes).decode("utf-8")
            else:
                text = raw_bytes.decode("utf-8")
        except (OSError, EOFError, UnicodeDecodeError):
            continue
        for line_no, line in enumerate(text.splitlines(), start=1):
            stripped = line.strip()
            if not stripped:
                continue
            try:
                obj = json.loads(stripped)
            except json.JSONDecodeError:
                continue
            if not isinstance(obj, dict):
                continue
            parsed = _parse_telemetry_record(obj, rel_path=rel_path, line_no=line_no)
            if parsed is not None:
                rows_by_id[parsed["event_id"]] = parsed
    return list(rows_by_id.values())


def normalize() -> int:
    """Normalize L1 product telemetry batches/shards into clean/product_blob.db."""
    from cleanio import write_clean

    rows = _iter_raw_telemetry_records()
    return write_clean(
        SOURCE,
        "product_telemetry",
        _TELEMETRY_DDL,
        rows,
        _TELEMETRY_COLS,
    )

