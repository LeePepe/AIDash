import pytest

from adapters.model_canon import model_canon


@pytest.mark.unit
def test_none_and_empty():
    assert model_canon(None) is None
    assert model_canon("") is None


@pytest.mark.unit
def test_dotted_minor_to_hyphen():
    # dotted minor version unified to hyphen form
    assert model_canon("claude-opus-4.7") == "claude-opus-4-7"
    assert model_canon("claude-opus-4.6") == "claude-opus-4-6"
    assert model_canon("claude-opus-4.8") == "claude-opus-4-8"
    assert model_canon("claude-sonnet-4.6") == "claude-sonnet-4-6"


@pytest.mark.unit
def test_one_million_suffix_unified():
    # both spellings collapse to one canonical
    assert model_canon("claude-opus-4.6-1m") == model_canon("claude-opus-4-6-1m")
    assert model_canon("claude-opus-4.6-1m") == "claude-opus-4-6-1m"


@pytest.mark.unit
def test_already_canonical_untouched():
    assert model_canon("claude-opus-4-7") == "claude-opus-4-7"
    assert model_canon("gpt-5.5") == "gpt-5.5"   # gpt dotted versions are canonical
    assert model_canon("claude-haiku-4-5-20251001") == "claude-haiku-4-5-20251001"


@pytest.mark.unit
def test_haiku_short_and_long_same():
    assert model_canon("claude-haiku-4.5") == "claude-haiku-4-5"
    assert model_canon("claude-haiku-4-5") == "claude-haiku-4-5"


@pytest.mark.unit
def test_unknown_passthrough():
    assert model_canon("models") == "models"
    assert model_canon("gpt-4o-mini") == "gpt-4o-mini"


@pytest.mark.unit
def test_price_map_covers_common_models():
    import csv
    from pathlib import Path
    from adapters.model_canon import model_canon

    csv_path = Path(__file__).resolve().parent.parent / "schema" / "dim_model.csv"
    priced = {row["model"] for row in csv.DictReader(csv_path.open())}
    # Models that appear with real tokens must be priced under their canonical id.
    for raw in ["gpt-5-mini", "claude-sonnet-4", "claude-sonnet-4-5",
                "claude-opus-4-6-1m", "gpt-4.1", "claude-opus-4-8", "gpt-5.5"]:
        assert model_canon(raw) in priced, f"{raw} -> {model_canon(raw)} not priced"
