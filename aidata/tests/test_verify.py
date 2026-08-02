"""Unit tests for the number-verification guard (ADR-18).

The guard is the core M4 safety mechanism: it rejects any LLM-polished digest
whose numbers differ from the deterministic template (hallucination or
alteration), forcing a template fallback.
"""

import pytest

from L5_apps.digest.verify import (
    extract_numbers, verify_numbers, VerificationResult,
)


@pytest.mark.unit
def test_extract_numbers_ints_decimals_negatives():
    nums = extract_numbers("cost 2699$ ↑ 24% vs -5 and 262.01 done")
    assert "2699" in nums
    assert "24" in nums
    assert "5" in nums          # from -5, sign stripped for comparison
    assert "262.01" in nums


@pytest.mark.unit
def test_clean_commentary_passes():
    template = "- 成本: 2699$ ↑(+24%) vs 昨 2180$"
    # Qualitative commentary that introduces NO new numbers and drops none.
    polished = ("> 💡 点评: 成本明显上升，值得关注\n"
                "- 成本: 2699$ ↑(+24%) vs 昨 2180$")
    result = verify_numbers(template, polished)
    assert isinstance(result, VerificationResult)
    assert result.ok
    assert result.introduced == frozenset()
    assert result.missing == frozenset()


@pytest.mark.unit
def test_altered_number_is_rejected():
    template = "- P0: 查 pipeline 取消率 32%"
    polished = "- P0: 查 pipeline 取消率 45%"   # LLM changed 32 -> 45
    result = verify_numbers(template, polished)
    assert not result.ok
    assert "45" in result.introduced
    assert "32" in result.missing


@pytest.mark.unit
def test_invented_number_is_rejected():
    template = "- 昨日无显著浪费信号"
    polished = "- 昨日浪费高达 $500，需优化"   # LLM invented 500
    result = verify_numbers(template, polished)
    assert not result.ok
    assert "500" in result.introduced


@pytest.mark.unit
def test_dropped_number_is_rejected():
    template = "- 昨日花费 $2699.44，请求 8273 次"
    polished = "- 昨日花费很高，请求 8273 次"   # dropped 2699.44
    result = verify_numbers(template, polished)
    assert not result.ok
    assert "2699.44" in result.missing


@pytest.mark.unit
def test_reason_is_populated_on_failure():
    result = verify_numbers("32%", "45%")
    assert not result.ok
    assert result.reason  # non-empty explanation for logging
