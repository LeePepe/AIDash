import pytest

from adapters.raven import _cost, _load_prices


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
