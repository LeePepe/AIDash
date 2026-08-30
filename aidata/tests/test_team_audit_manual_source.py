import importlib.util
import sys
import types
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
CONFIG_PATH = ROOT / "config.py"
CLI_PATH = ROOT / "cli.py"


def _load_isolated_config(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.delitem(sys.modules, "config", raising=False)
    monkeypatch.setitem(sys.modules, "config_local", types.ModuleType("config_local"))
    spec = importlib.util.spec_from_file_location("isolated_config", CONFIG_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec is not None and spec.loader is not None
    monkeypatch.setitem(sys.modules, "isolated_config", module)
    spec.loader.exec_module(module)
    monkeypatch.setitem(sys.modules, "config", module)
    return module


def _load_cli_module(config_module, monkeypatch: pytest.MonkeyPatch):
    spec = importlib.util.spec_from_file_location("isolated_cli", CLI_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec is not None and spec.loader is not None
    monkeypatch.setitem(sys.modules, "config", config_module)
    monkeypatch.setitem(sys.modules, "isolated_cli", module)
    spec.loader.exec_module(module)
    return module


@pytest.mark.unit
def test_manual_source_registry_is_separate_from_scheduled_sources(monkeypatch: pytest.MonkeyPatch) -> None:
    config = _load_isolated_config(monkeypatch)
    assert isinstance(config.MANUAL_SOURCES, tuple)
    assert config.MANUAL_SOURCES == ("team_audit_snapshot",)
    assert "team_audit_snapshot" not in config.SOURCES
    assert set(config.SOURCES).isdisjoint(set(config.MANUAL_SOURCES))
    assert set(config.SOURCES) | set(config.MANUAL_SOURCES) == set(
        config.SOURCES + config.MANUAL_SOURCES
    )


@pytest.mark.unit
def test_manual_import_root_is_empty_by_default(monkeypatch: pytest.MonkeyPatch) -> None:
    config = _load_isolated_config(monkeypatch)
    assert not config.TEAM_AUDIT_IMPORT_ROOT


@pytest.mark.unit
@pytest.mark.parametrize(
    ("command", "expected_calls"),
    [
        ("collect", ["collect"]),
        ("normalize", ["normalize"]),
    ],
)
def test_cli_defaults_exclude_manual_source(
    monkeypatch: pytest.MonkeyPatch, command: str, expected_calls: list[str]
) -> None:
    config = _load_isolated_config(monkeypatch)
    cli = _load_cli_module(config, monkeypatch)
    seen: list[tuple[str, str]] = []

    def fake_load_adapter(name: str):
        mod = types.SimpleNamespace()
        source_name = name.removeprefix("adapters.")

        def collect() -> int:
            seen.append(("collect", source_name))
            return 1

        def normalize() -> int:
            seen.append(("normalize", source_name))
            return 1

        mod.collect = collect
        mod.normalize = normalize
        return mod

    monkeypatch.setattr(cli, "_load_adapter", fake_load_adapter)
    monkeypatch.setattr(sys, "argv", ["aidata", command])
    result = cli.main()

    assert result == 0
    assert seen == [(call, name) for name in config.SOURCES for call in expected_calls]
    assert all(name != "team_audit_snapshot" for _, name in seen)


@pytest.mark.unit
@pytest.mark.parametrize(
    ("command", "expected_calls"),
    [
        ("collect", ["collect"]),
        ("normalize", ["normalize"]),
    ],
)
def test_cli_explicit_manual_source_is_selected_only_when_requested(
    monkeypatch: pytest.MonkeyPatch, command: str, expected_calls: list[str]
) -> None:
    config = _load_isolated_config(monkeypatch)
    cli = _load_cli_module(config, monkeypatch)
    seen: list[tuple[str, str]] = []

    def fake_load_adapter(name: str):
        mod = types.SimpleNamespace()
        source_name = name.removeprefix("adapters.")

        def collect() -> int:
            seen.append(("collect", source_name))
            return 1

        def normalize() -> int:
            seen.append(("normalize", source_name))
            return 1

        mod.collect = collect
        mod.normalize = normalize
        return mod

    monkeypatch.setattr(cli, "_load_adapter", fake_load_adapter)
    monkeypatch.setattr(sys, "argv", ["aidata", command, "--source", "team_audit_snapshot"])
    result = cli.main()

    assert result == 0
    assert seen == [(call, "team_audit_snapshot") for call in expected_calls]
