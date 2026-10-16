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
