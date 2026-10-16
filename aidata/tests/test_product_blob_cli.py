import json
import sys
import types
import uuid

import pytest

import cli


def _run(monkeypatch, capsys, *args):
    monkeypatch.setattr(sys, "argv", ["aidata", "product-blob", *args])
    exit_code = cli.main()
    captured = capsys.readouterr()
    return exit_code, captured.out, captured.err


def _assert_uuid(value):
    assert str(uuid.UUID(value)) == value


@pytest.mark.unit
def test_disabled_product_blob_is_empty_without_loading_adapter(
    monkeypatch, capsys
):
    monkeypatch.setattr(cli, "PRODUCT_BLOB_CONTAINER_URL", "")
    monkeypatch.setattr(cli, "PRODUCT_BLOB_PREFIX", "")
    monkeypatch.setattr(
        cli,
        "_load_adapter",
        lambda _name: pytest.fail("disabled command must not import adapter"),
    )

    exit_code, stdout, stderr = _run(monkeypatch, capsys)

    assert exit_code == 0
    assert stderr == ""
    envelope = json.loads(stdout)
    assert stdout == json.dumps(envelope, separators=(",", ":")) + "\n"
    assert envelope["ok"] is True
    assert envelope["data"] == {"status": "empty", "objectCount": 0}
    _assert_uuid(envelope["requestId"])


@pytest.mark.unit
def test_completed_product_blob_uses_exact_success_envelope(monkeypatch, capsys):
    batch_id = str(uuid.uuid4())
    adapter = types.SimpleNamespace(
        collect=lambda _url, _prefix: {
            "status": "completed",
            "batchId": batch_id,
            "objectCount": 2,
        }
    )
    monkeypatch.setattr(
        cli,
        "PRODUCT_BLOB_CONTAINER_URL",
        "https://sampleacct.blob.core.windows.net/sample-container",
    )
    monkeypatch.setattr(cli, "PRODUCT_BLOB_PREFIX", "synthetic/v1")
    monkeypatch.setattr(cli, "_load_adapter", lambda name: adapter)

    exit_code, stdout, stderr = _run(monkeypatch, capsys)

    assert exit_code == 0
    assert stderr == ""
    envelope = json.loads(stdout)
    assert envelope["data"] == {
        "status": "completed",
        "batchId": batch_id,
        "objectCount": 2,
    }
    _assert_uuid(envelope["requestId"])


@pytest.mark.unit
@pytest.mark.parametrize(
    ("url", "prefix"),
    [
        ("", "synthetic/v1"),
        ("https://sampleacct.blob.core.windows.net/sample-container", ""),
        ("http://sampleacct.blob.core.windows.net/sample-container", "valid"),
        ("https://UPPER.blob.core.windows.net/sample-container", "valid"),
        ("https://sampleacct.blob.core.windows.net/a/b", "valid"),
        ("https://sampleacct.blob.core.windows.net/sample-container?q=1", "valid"),
        ("https://sampleacct.blob.core.windows.net/sample-container?", "valid"),
        ("https://sampleacct.blob.core.windows.net/sample-container#", "valid"),
        ("https://sampleacct.blob.core.windows.net/sample-container", "../escape"),
        ("https://sampleacct.blob.core.windows.net/sample-container", "a//b"),
        ("https://sampleacct.blob.core.windows.net/sample-container", "a/*"),
    ],
)
def test_invalid_selectors_fail_before_adapter_import(
    monkeypatch, capsys, url, prefix
):
    monkeypatch.setattr(cli, "PRODUCT_BLOB_CONTAINER_URL", url)
    monkeypatch.setattr(cli, "PRODUCT_BLOB_PREFIX", prefix)
    monkeypatch.setattr(
        cli,
        "_load_adapter",
        lambda _name: pytest.fail("invalid selectors must fail before import"),
    )

    exit_code, stdout, stderr = _run(monkeypatch, capsys)

    assert exit_code == 1
    assert stdout == ""
    envelope = json.loads(stderr)
    assert set(envelope) == {"ok", "error"}
    assert envelope["ok"] is False
    assert set(envelope["error"]) == {"code", "message", "field", "requestId"}
    assert envelope["error"]["code"] == "product_blob.collection_failed"
    assert envelope["error"]["message"] == "product blob collection failed"
    assert envelope["error"]["field"] is None
    _assert_uuid(envelope["error"]["requestId"])
    private_values = (url, prefix)
    assert all(not value or value not in stderr for value in private_values)


@pytest.mark.unit
@pytest.mark.parametrize(
    "result",
    [
        None,
        {"status": "empty", "objectCount": 0, "batchId": "sentinel"},
        {"status": "completed", "objectCount": 0, "batchId": str(uuid.uuid4())},
        {"status": "completed", "objectCount": 1, "batchId": "not-a-uuid"},
        {"status": "completed", "objectCount": True, "batchId": str(uuid.uuid4())},
        {"status": "unknown", "objectCount": 1},
        {"status": "empty", "objectCount": 0, "private": "sentinel"},
    ],
)
def test_malformed_adapter_results_use_neutral_failure(
    monkeypatch, capsys, result
):
    monkeypatch.setattr(
        cli,
        "PRODUCT_BLOB_CONTAINER_URL",
        "https://sampleacct.blob.core.windows.net/sample-container",
    )
    monkeypatch.setattr(cli, "PRODUCT_BLOB_PREFIX", "synthetic/v1")
    monkeypatch.setattr(
        cli,
        "_load_adapter",
        lambda _name: types.SimpleNamespace(collect=lambda *_args: result),
    )

    exit_code, stdout, stderr = _run(monkeypatch, capsys)

    assert exit_code == 1
    assert stdout == ""
    assert "sentinel" not in stderr
    assert json.loads(stderr)["error"]["message"] == (
        "product blob collection failed"
    )


@pytest.mark.unit
def test_extra_argument_and_adapter_exception_are_neutral(monkeypatch, capsys):
    monkeypatch.setattr(
        cli,
        "PRODUCT_BLOB_CONTAINER_URL",
        "https://sampleacct.blob.core.windows.net/sample-container",
    )
    monkeypatch.setattr(cli, "PRODUCT_BLOB_PREFIX", "synthetic/v1")

    exit_code, stdout, stderr = _run(
        monkeypatch, capsys, "private-selector"
    )
    assert exit_code == 1
    assert stdout == ""
    assert "private-selector" not in stderr

    def raise_private_error(*_args):
        raise RuntimeError("private endpoint and absolute /private/path")

    monkeypatch.setattr(
        cli,
        "_load_adapter",
        lambda _name: types.SimpleNamespace(collect=raise_private_error),
    )
    exit_code, stdout, stderr = _run(monkeypatch, capsys)
    assert exit_code == 1
    assert stdout == ""
    assert "private endpoint" not in stderr
    assert "/private/path" not in stderr


@pytest.mark.unit
@pytest.mark.parametrize("load_behavior", ["import_error", "missing", "noncallable"])
def test_adapter_import_and_load_failures_are_neutral(
    monkeypatch, capsys, load_behavior
):
    monkeypatch.setattr(
        cli,
        "PRODUCT_BLOB_CONTAINER_URL",
        "https://sampleacct.blob.core.windows.net/sample-container",
    )
    monkeypatch.setattr(cli, "PRODUCT_BLOB_PREFIX", "synthetic/v1")

    if load_behavior == "import_error":
        def fail_import(_name):
            raise ImportError("private adapter load detail")

        monkeypatch.setattr(cli, "_load_adapter", fail_import)
    elif load_behavior == "missing":
        monkeypatch.setattr(
            cli,
            "_load_adapter",
            lambda _name: types.SimpleNamespace(),
        )
    else:
        monkeypatch.setattr(
            cli,
            "_load_adapter",
            lambda _name: types.SimpleNamespace(collect=None),
        )

    exit_code, stdout, stderr = _run(monkeypatch, capsys)

    assert exit_code == 1
    assert stdout == ""
    envelope = json.loads(stderr)
    assert envelope["ok"] is False
    assert envelope["error"]["code"] == "product_blob.collection_failed"
    assert envelope["error"]["message"] == "product blob collection failed"
    assert envelope["error"]["field"] is None
    _assert_uuid(envelope["error"]["requestId"])
    assert "private adapter load detail" not in stderr
