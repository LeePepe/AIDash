import pytest

from adapters.raven import _cost, _load_prices
import adapters.raven as raven


@pytest.mark.unit
def test_cost_uses_canonical_lookup():
    prices = _load_prices()
    # dotted spelling must still price (via canon) — same as hyphen form
    c_dotted = _cost("claude-opus-4.7", 1_000_000, 1_000_000, prices)
    c_hyphen = _cost("claude-opus-4-7", 1_000_000, 1_000_000, prices)
    assert c_dotted is not None
    assert c_dotted == c_hyphen


@pytest.mark.unit
def test_cost_null_tokens_stay_null():
    prices = _load_prices()
    assert _cost("claude-opus-4-8", None, 5, prices) is None
    assert _cost("claude-opus-4-8", 100, None, prices) is None


@pytest.mark.unit
def test_previously_unpriced_model_now_costs():
    prices = _load_prices()
    # gpt-5-mini and claude-sonnet-4 were NULL-cost before the price map fix
    assert _cost("gpt-5-mini", 1_000_000, 1_000_000, prices) is not None
    assert _cost("claude-sonnet-4", 1_000_000, 1_000_000, prices) is not None


@pytest.mark.unit
def test_normalize_preserves_cache_tokens(monkeypatch):
    raw = [{
        "id": "req-1",
        "timestamp": 1,
        "client_name": "codex_exec/1.0",
        "session_id": "",
        "model": "gpt-5-mini",
        "resolved_model": None,
        "input_tokens": 11,
        "output_tokens": 7,
        "cache_read_tokens": 101,
        "cache_write_tokens": 13,
    }]
    captured = {}
    monkeypatch.setattr(raven, "read_raw", lambda _source: raw)
    monkeypatch.setattr(
        raven,
        "write_clean",
        lambda source, table, ddl, rows, columns: captured.update(
            source=source, table=table, ddl=ddl, rows=rows, columns=columns
        ) or len(rows),
    )

    assert raven.normalize() == 1
    assert captured["rows"][0]["cache_read"] == 101
    assert captured["rows"][0]["cache_write"] == 13
    assert "cache_read" in captured["columns"]
    assert "cache_write" in captured["columns"]
