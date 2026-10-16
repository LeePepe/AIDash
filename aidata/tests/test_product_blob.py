import json
import os
import stat
import sys
from pathlib import Path

import pytest

import cli
import adapters.product_blob as product_blob

CONTAINER_URL = "https://sampleacct.blob.core.windows.net/sample-container"
PREFIX = "synthetic/v1"


def _fake_az(tmp_path: Path, scenario: str) -> tuple[Path, Path]:
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    ledger = tmp_path / "ledger.jsonl"
    executable = bin_dir / "az"
    executable.write_text(
        f"""#!/usr/bin/python3
import json
import os
import pathlib
import signal
import sys

scenario = {scenario!r}
ledger = pathlib.Path({str(ledger)!r})
with ledger.open("a", encoding="utf-8") as handle:
    handle.write(json.dumps({{"argv": sys.argv[1:], "env": dict(os.environ)}},
                            sort_keys=True) + "\\n")

if sys.argv[1] == "version":
    version = "0.0.0" if scenario == "bad_version" else "2.91.0"
    print(json.dumps({{"azure-cli": version, "azure-cli-core": "2.91.0",
                      "extensions": {{}}}}))
    raise SystemExit(0)

if sys.argv[1:3] == ["cloud", "show"]:
    cloud = {{
        "name": "WrongCloud" if scenario == "bad_cloud" else "AzureCloud",
        "isActive": 1 if scenario == "numeric_active" else True,
        "storageEndpoint": "core.windows.net",
        "resourceManager": "https://management.azure.com/",
    }}
    print(json.dumps(cloud))
    raise SystemExit(0)

destination = pathlib.Path(sys.argv[sys.argv.index("--destination") + 1])
if scenario == "batch_fail":
    print("private child output", file=sys.stderr)
    raise SystemExit(9)
if scenario == "interrupted":
    os.kill(os.getpid(), signal.SIGKILL)
if scenario == "empty":
    raise SystemExit(0)
if scenario == "traversal":
    raise SystemExit(9)
if scenario == "symlink":
    outside = destination.parents[2] / "outside.bin"
    outside.write_bytes(b"outside")
    (destination / "unsafe").symlink_to(outside)
    raise SystemExit(0)
if scenario == "fifo":
    os.mkfifo(destination / "unsafe")
    raise SystemExit(0)

output = destination / "synthetic" / "v1"
output.mkdir(parents=True)
(output / "events.gz").write_bytes(b"opaque-gzip-bytes")
print("discarded batch stdout")
print("discarded batch stderr", file=sys.stderr)
""",
        encoding="utf-8",
    )
    executable.chmod(0o700)
    return bin_dir, ledger


def _configure(monkeypatch, tmp_path: Path, scenario: str) -> tuple[Path, Path]:
    bin_dir, ledger = _fake_az(tmp_path, scenario)
    raw_dir = tmp_path / "raw"
    monkeypatch.setattr(cli, "PRODUCT_BLOB_CONTAINER_URL", CONTAINER_URL)
    monkeypatch.setattr(cli, "PRODUCT_BLOB_PREFIX", PREFIX)
    monkeypatch.setattr(product_blob, "RAW_DIR", raw_dir)
    monkeypatch.setenv("PATH", str(bin_dir))
    monkeypatch.setenv("HOME", str(tmp_path / "home"))
    monkeypatch.setenv("SECRET_SENTINEL", "must-not-reach-child")
    monkeypatch.setenv("HTTPS_PROXY", "https://proxy.invalid")
    monkeypatch.setenv("HTTP_PROXY", "http://proxy.invalid")
    monkeypatch.setenv("PYTHONPATH", "/private/injection")
    monkeypatch.setenv("ARM_CLIENT_SECRET", "must-not-reach-child")
    monkeypatch.setenv("AZURE_STORAGE_KEY", "must-not-reach-child")
    monkeypatch.setenv(
        "AZURE_CLI_DISABLE_CONNECTION_VERIFICATION",
        "1",
    )
    return raw_dir, ledger


def _run_cli(monkeypatch, capsys):
    monkeypatch.setattr(sys, "argv", ["aidata", "product-blob"])
    exit_code = cli.main()
    captured = capsys.readouterr()
    return exit_code, captured.out, captured.err


def _ledger(path: Path) -> list[dict]:
    return [
        json.loads(line)
        for line in path.read_text(encoding="utf-8").splitlines()
    ]


def _mode(path: Path) -> int:
    return stat.S_IMODE(path.lstat().st_mode)


@pytest.mark.unit
def test_real_cli_publishes_one_private_opaque_batch_with_exact_azure_calls(
    monkeypatch, tmp_path, capsys
):
    raw_dir, ledger_path = _configure(monkeypatch, tmp_path, "success")
    durability_events = []
    replace_calls = []
    child_environments = []
    real_replace = product_blob.os.replace
    real_fsync_file = product_blob._fsync_file
    real_fsync_directory = product_blob._fsync_directory
    real_run = product_blob.subprocess.run

    def record_replace(source, destination):
        durability_events.append(("replace", Path(source), Path(destination)))
        replace_calls.append((Path(source), Path(destination)))
        return real_replace(source, destination)

    def record_fsync_file(path):
        durability_events.append(("fsync-file", Path(path)))
        return real_fsync_file(path)

    def record_fsync_directory(path):
        durability_events.append(("fsync-directory", Path(path)))
        return real_fsync_directory(path)

    def record_run(*args, **kwargs):
        child_environments.append(dict(kwargs["env"]))
        return real_run(*args, **kwargs)

    monkeypatch.setattr(product_blob.os, "replace", record_replace)
    monkeypatch.setattr(product_blob.subprocess, "run", record_run)
    monkeypatch.setattr(product_blob, "_fsync_file", record_fsync_file)
    monkeypatch.setattr(
        product_blob,
        "_fsync_directory",
        record_fsync_directory,
    )

    exit_code, stdout, stderr = _run_cli(monkeypatch, capsys)

    assert exit_code == 0
    assert stderr == ""
    envelope = json.loads(stdout)
    assert envelope["data"]["status"] == "completed"
    assert envelope["data"]["objectCount"] == 1
    batches = raw_dir / "product_blob" / "batches"
    completions = list(batches.iterdir())
    assert len(completions) == 1
    completion = completions[0]
    assert completion.name == envelope["data"]["batchId"]
    assert (completion / "synthetic/v1/events.gz").read_bytes() == (
        b"opaque-gzip-bytes"
    )
    for private_dir in (
        raw_dir / "product_blob",
        raw_dir / "product_blob" / ".staging",
        batches,
        completion,
        completion / "synthetic",
        completion / "synthetic/v1",
    ):
        assert private_dir.stat().st_uid == os.geteuid()
        assert _mode(private_dir) == 0o700
    assert _mode(completion / "synthetic/v1/events.gz") == 0o600
    assert len(replace_calls) == 1
    assert replace_calls[0][1] == completion
    source_stage = replace_calls[0][0]
    assert durability_events == [
        ("fsync-file", source_stage / "synthetic/v1/events.gz"),
        ("fsync-directory", source_stage / "synthetic/v1"),
        ("fsync-directory", source_stage / "synthetic"),
        ("fsync-directory", source_stage),
        ("replace", source_stage, completion),
        ("fsync-directory", completion),
        ("fsync-directory", batches),
    ]

    calls = _ledger(ledger_path)
    expected_argv = [
        ["version", "--output", "json", "--only-show-errors"],
        [
            "cloud",
            "show",
            "--name",
            "AzureCloud",
            "--query",
            "{name:name,isActive:isActive,storageEndpoint:suffixes.storageEndpoint,resourceManager:endpoints.resourceManager}",
            "--output",
            "json",
            "--only-show-errors",
        ],
    ]
    destination = replace_calls[0][0]
    expected_argv.append(
        [
            "storage",
            "blob",
            "download-batch",
            "--account-name",
            "sampleacct",
            "--source",
            "sample-container",
            "--pattern",
            "synthetic/v1/*",
            "--destination",
            str(destination),
            "--auth-mode",
            "login",
            "--overwrite",
            "false",
            "--output",
            "none",
            "--no-progress",
            "--only-show-errors",
        ]
    )
    assert [call["argv"] for call in calls] == expected_argv
    inherited_names = (
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
    expected_environment = {
        name: os.environ[name]
        for name in inherited_names
        if name in os.environ
    }
    expected_environment.update(
        {
            "AZURE_CLOUD_NAME": "AzureCloud",
            "AZURE_LOGGING_ENABLE_LOG_FILE": "false",
            "AZURE_CORE_COLLECT_TELEMETRY": "false",
        }
    )
    assert child_environments == [expected_environment] * 3


@pytest.mark.unit
@pytest.mark.parametrize(
    ("scenario", "expected_status", "expected_exit"),
    [
        ("empty", "empty", 0),
        ("batch_fail", None, 1),
        ("interrupted", None, 1),
        ("bad_version", None, 1),
        ("bad_cloud", None, 1),
        ("numeric_active", None, 1),
    ],
)
def test_empty_and_azure_failures_publish_no_completion(
    monkeypatch, tmp_path, capsys, scenario, expected_status, expected_exit
):
    raw_dir, ledger_path = _configure(monkeypatch, tmp_path, scenario)

    exit_code, stdout, stderr = _run_cli(monkeypatch, capsys)

    assert exit_code == expected_exit
    if expected_status:
        assert json.loads(stdout)["data"] == {
            "status": expected_status,
            "objectCount": 0,
        }
        assert stderr == ""
    else:
        assert stdout == ""
        assert json.loads(stderr)["error"]["message"] == (
            "product blob collection failed"
        )
        assert "private child output" not in stderr
    batches = raw_dir / "product_blob" / "batches"
    assert not batches.exists() or not list(batches.iterdir())
    staging = raw_dir / "product_blob" / ".staging"
    assert not staging.exists() or not list(staging.iterdir())
    calls = _ledger(ledger_path)
    if scenario in {"bad_version", "bad_cloud", "numeric_active"}:
        assert all(call["argv"][:3] != ["storage", "blob", "download-batch"]
                   for call in calls)


@pytest.mark.unit
@pytest.mark.parametrize("scenario", ["symlink", "fifo"])
def test_unsafe_download_entries_are_rejected_without_completion(
    monkeypatch, tmp_path, capsys, scenario
):
    raw_dir, _ledger_path = _configure(monkeypatch, tmp_path, scenario)

    exit_code, stdout, stderr = _run_cli(monkeypatch, capsys)

    assert exit_code == 1
    assert stdout == ""
    assert json.loads(stderr)["error"]["code"] == (
        "product_blob.collection_failed"
    )
    assert not list((raw_dir / "product_blob" / "batches").iterdir())
    assert not list((raw_dir / "product_blob" / ".staging").iterdir())


@pytest.mark.unit
@pytest.mark.parametrize(
    ("terminal_name", "terminal_kind"),
    [
        ("product", "symlink"),
        ("product", "file"),
        ("product", "public"),
        ("staging", "symlink"),
        ("staging", "file"),
        ("staging", "public"),
        ("batches", "symlink"),
        ("batches", "file"),
        ("batches", "public"),
    ],
)
def test_unsafe_terminal_root_fails_before_azure(
    monkeypatch, tmp_path, capsys, terminal_name, terminal_kind
):
    raw_dir, ledger_path = _configure(monkeypatch, tmp_path, "success")
    product_root = raw_dir / "product_blob"
    raw_dir.mkdir(mode=0o700)
    if terminal_name != "product":
        product_root.mkdir(mode=0o700)
    terminal = {
        "product": product_root,
        "staging": product_root / ".staging",
        "batches": product_root / "batches",
    }[terminal_name]
    if terminal_kind == "symlink":
        target = tmp_path / "target"
        target.mkdir(mode=0o700)
        terminal.symlink_to(target, target_is_directory=True)
    elif terminal_kind == "file":
        terminal.write_text("not a directory", encoding="utf-8")
    else:
        terminal.mkdir(mode=0o700)
        terminal.chmod(0o755)

    exit_code, stdout, stderr = _run_cli(monkeypatch, capsys)

    assert exit_code == 1
    assert stdout == ""
    assert json.loads(stderr)["error"]["code"] == (
        "product_blob.collection_failed"
    )
    assert not ledger_path.exists()


@pytest.mark.unit
def test_resolved_output_escape_is_rejected_without_completion(
    monkeypatch, tmp_path, capsys
):
    raw_dir, _ledger_path = _configure(monkeypatch, tmp_path, "success")
    real_resolve = Path.resolve

    def escape_downloaded_file(path, *args, **kwargs):
        if path.name == "events.gz":
            return tmp_path / "outside" / "events.gz"
        return real_resolve(path, *args, **kwargs)

    monkeypatch.setattr(Path, "resolve", escape_downloaded_file)

    exit_code, stdout, stderr = _run_cli(monkeypatch, capsys)

    assert exit_code == 1
    assert stdout == ""
    assert json.loads(stderr)["error"]["code"] == (
        "product_blob.collection_failed"
    )
    assert not list((raw_dir / "product_blob" / "batches").iterdir())
    assert not list((raw_dir / "product_blob" / ".staging").iterdir())


@pytest.mark.unit
def test_cli_traversal_rejection_publishes_nothing_and_cleans_stage(
    monkeypatch, tmp_path, capsys
):
    raw_dir, ledger_path = _configure(monkeypatch, tmp_path, "traversal")

    exit_code, stdout, stderr = _run_cli(monkeypatch, capsys)

    assert exit_code == 1
    assert stdout == ""
    assert json.loads(stderr)["error"]["code"] == (
        "product_blob.collection_failed"
    )
    assert not list((raw_dir / "product_blob" / "batches").iterdir())
    staging = raw_dir / "product_blob" / ".staging"
    assert not list(staging.iterdir())
    calls = _ledger(ledger_path)
    assert len(calls) == 3
    assert calls[-1]["argv"][:3] == ["storage", "blob", "download-batch"]


@pytest.mark.unit
def test_precommit_failure_removes_stage_but_postcommit_failure_keeps_batch(
    monkeypatch, tmp_path, capsys
):
    raw_dir, _ledger_path = _configure(monkeypatch, tmp_path, "success")
    real_replace = os.replace

    def fail_before_commit(_source, _destination):
        raise OSError("pre-commit interruption")

    monkeypatch.setattr(product_blob.os, "replace", fail_before_commit)
    exit_code, stdout, stderr = _run_cli(monkeypatch, capsys)
    assert exit_code == 1
    assert stdout == ""
    assert json.loads(stderr)["ok"] is False
    assert not list((raw_dir / "product_blob" / "batches").iterdir())
    assert not list((raw_dir / "product_blob" / ".staging").iterdir())

    def fail_after_commit():
        raise OSError("response lost after commit")

    monkeypatch.setattr(product_blob.os, "replace", real_replace)
    monkeypatch.setattr(product_blob, "_post_commit", fail_after_commit)
    exit_code, stdout, stderr = _run_cli(monkeypatch, capsys)
    assert exit_code == 1
    assert stdout == ""
    assert json.loads(stderr)["ok"] is False
    completions = list((raw_dir / "product_blob" / "batches").iterdir())
    assert len(completions) == 1
    assert (completions[0] / "synthetic/v1/events.gz").read_bytes() == (
        b"opaque-gzip-bytes"
    )


@pytest.mark.unit
def test_later_success_ignores_abandoned_stage_and_preserves_prior_batch(
    monkeypatch, tmp_path, capsys
):
    raw_dir, _ledger_path = _configure(monkeypatch, tmp_path, "success")
    product_root = raw_dir / "product_blob"
    product_root.mkdir(parents=True, mode=0o700)
    staging = product_root / ".staging"
    staging.mkdir(mode=0o700)
    abandoned = staging / "abandoned"
    abandoned.mkdir(mode=0o700)
    (abandoned / "partial").write_bytes(b"partial")

    first_exit, _, _ = _run_cli(monkeypatch, capsys)
    assert first_exit == 0
    batches = raw_dir / "product_blob" / "batches"
    first = next(batches.iterdir())
    first_snapshot = {
        path.relative_to(first): (
            path.lstat().st_ino,
            path.lstat().st_mode,
            path.lstat().st_size,
            path.lstat().st_mtime_ns,
            path.read_bytes() if path.is_file() else None,
        )
        for path in (first, *first.rglob("*"))
    }

    second_exit, _, _ = _run_cli(monkeypatch, capsys)

    assert second_exit == 0
    completions = list(batches.iterdir())
    assert len(completions) == 2
    assert first in completions
    assert {
        path.relative_to(first): (
            path.lstat().st_ino,
            path.lstat().st_mode,
            path.lstat().st_size,
            path.lstat().st_mtime_ns,
            path.read_bytes() if path.is_file() else None,
        )
        for path in (first, *first.rglob("*"))
    } == first_snapshot
    assert abandoned.exists()
    assert (abandoned / "partial").read_bytes() == b"partial"
