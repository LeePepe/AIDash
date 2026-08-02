"""Unit tests for the shared time helpers (timeutil.py, T2).

Every conversion is checked at valid / 0 / negative / None / bad-type / extreme
inputs, and each old adapter wrapper is asserted to stay behaviour-equivalent to
the new timeutil function it now delegates to (the plan's hard requirement — the
six copies had DIFFERENT boundary contracts, precisely reproduced here).
"""

import pytest

import timeutil as tu


# A known Unix epoch <-> CST cross-check.
# 2026-07-27T00:00:00Z == 2026-07-27T08:00:00+08:00 (CST). Unix = 1785110400.
_UNIX_20260727 = 1785110400
_CHROME_20260727 = (_UNIX_20260727 + 11_644_473_600) * 1_000_000
_MS_20260709_2330Z = 1783639800000  # 2026-07-09T23:30:00Z -> CST 2026-07-10


# ---- CST constant ----------------------------------------------------------
@pytest.mark.unit
def test_cst_is_plus_eight():
    assert tu.CST.utcoffset(None).total_seconds() == 8 * 3600


# ---- cst_today -------------------------------------------------------------
@pytest.mark.unit
def test_cst_today_shape(monkeypatch):
    out = tu.cst_today()
    assert len(out) == 10 and out[4] == "-" and out[7] == "-"


# ---- epoch_ms_to_cst_day (was cst.cst_date_of_ms): ms, RAISES on bad --------
@pytest.mark.unit
def test_epoch_ms_to_cst_day_shifts_plus8():
    assert tu.epoch_ms_to_cst_day(_MS_20260709_2330Z) == "2026-07-10"
    assert tu.epoch_ms_to_cst_day(1783609200000) == "2026-07-09"  # 15:00Z


@pytest.mark.unit
def test_epoch_ms_to_cst_day_boundary_16utc_flips_day():
    assert tu.epoch_ms_to_cst_day(1783612800000) == "2026-07-10"  # 16:00Z


@pytest.mark.unit
def test_epoch_ms_to_cst_day_zero_is_1970_not_none():
    # No guard (matches original): epoch 0 ms -> the 1970 CST day, never None.
    assert tu.epoch_ms_to_cst_day(0) == "1970-01-01"


@pytest.mark.unit
def test_epoch_ms_to_cst_day_raises_on_bad():
    with pytest.raises((TypeError, ValueError)):
        tu.epoch_ms_to_cst_day(None)  # type: ignore[arg-type]


# ---- epoch_s_to_cst_day (was hermes._cst_day): sec, None on bad, NO <=0 guard
@pytest.mark.unit
def test_epoch_s_to_cst_day_valid():
    assert tu.epoch_s_to_cst_day(_UNIX_20260727) == "2026-07-27"


@pytest.mark.unit
def test_epoch_s_to_cst_day_zero_is_1970_not_none():
    # Deliberately NO <=0 guard (matches original hermes_tools._cst_day).
    assert tu.epoch_s_to_cst_day(0) == "1970-01-01"


@pytest.mark.unit
def test_epoch_s_to_cst_day_bad_returns_none():
    assert tu.epoch_s_to_cst_day(None) is None
    assert tu.epoch_s_to_cst_day("nope") is None


@pytest.mark.unit
def test_epoch_s_to_cst_day_extreme_returns_none():
    assert tu.epoch_s_to_cst_day(10**20) is None  # OverflowError/OSError path


# ---- epoch_s_to_cst_iso (was gecko.epoch_to_iso): sec, REJECTS <=0 ---------
@pytest.mark.unit
def test_epoch_s_to_cst_iso_valid():
    assert tu.epoch_s_to_cst_iso(_UNIX_20260727) == "2026-07-27T08:00:00+08:00"
    assert tu.epoch_s_to_cst_iso(_UNIX_20260727 + 0.0) == "2026-07-27T08:00:00+08:00"


@pytest.mark.unit
def test_epoch_s_to_cst_iso_rejects_zero_neg_none_bad():
    assert tu.epoch_s_to_cst_iso(0) is None
    assert tu.epoch_s_to_cst_iso(-5) is None
    assert tu.epoch_s_to_cst_iso(None) is None
    assert tu.epoch_s_to_cst_iso("nope") is None


@pytest.mark.unit
def test_epoch_s_to_cst_iso_extreme_returns_none():
    assert tu.epoch_s_to_cst_iso(10**20) is None


# ---- chrome_epoch_to_unix (µs since 1601) ----------------------------------
@pytest.mark.unit
def test_chrome_epoch_to_unix_known_value():
    assert tu.chrome_epoch_to_unix(_CHROME_20260727) == pytest.approx(_UNIX_20260727)


@pytest.mark.unit
def test_chrome_epoch_to_unix_microsecond_offset():
    # 1 second past 1601 = 1e6 µs -> 1 - offset.
    assert tu.chrome_epoch_to_unix(1_000_000) == pytest.approx(1 - 11_644_473_600)


@pytest.mark.unit
def test_chrome_epoch_to_unix_rejects_zero_neg_none_bad():
    assert tu.chrome_epoch_to_unix(0) is None
    assert tu.chrome_epoch_to_unix(-5) is None
    assert tu.chrome_epoch_to_unix(None) is None
    assert tu.chrome_epoch_to_unix("nope") is None


# ---- chrome_epoch_to_cst_iso (NO second <=0 guard, unlike gecko) -----------
@pytest.mark.unit
def test_chrome_epoch_to_cst_iso_valid():
    assert tu.chrome_epoch_to_cst_iso(_CHROME_20260727) == "2026-07-27T08:00:00+08:00"


@pytest.mark.unit
def test_chrome_epoch_to_cst_iso_zero_none_passthrough():
    assert tu.chrome_epoch_to_cst_iso(0) is None
    assert tu.chrome_epoch_to_cst_iso(None) is None


# ---- adapter wrappers stay equivalent to timeutil (seam preservation) ------
@pytest.mark.unit
@pytest.mark.parametrize("val", [_UNIX_20260727, 0, -5, None, "nope", 10**20])
def test_gecko_epoch_to_iso_matches_timeutil(val):
    import adapters.gecko as gk
    assert gk.epoch_to_iso(val) == tu.epoch_s_to_cst_iso(val)


@pytest.mark.unit
@pytest.mark.parametrize("val", [_CHROME_20260727, 0, -5, None, "nope", 1_000_000])
def test_browser_chrome_to_unix_matches_timeutil(val):
    import adapters.browser_history as bh
    assert bh.chrome_to_unix(val) == tu.chrome_epoch_to_unix(val)


@pytest.mark.unit
@pytest.mark.parametrize("val", [_CHROME_20260727, 0, None])
def test_browser_chrome_to_iso_matches_timeutil(val):
    import adapters.browser_history as bh
    assert bh.chrome_to_iso(val) == tu.chrome_epoch_to_cst_iso(val)


@pytest.mark.unit
@pytest.mark.parametrize("val", [_UNIX_20260727, 0, None, "nope"])
def test_hermes_cst_day_matches_timeutil(val):
    import adapters.hermes_tools as ht
    assert ht._cst_day(val) == tu.epoch_s_to_cst_day(val)


@pytest.mark.unit
def test_cst_date_of_ms_matches_timeutil():
    from L5_apps.digest import cst
    assert cst.cst_date_of_ms(_MS_20260709_2330Z) == tu.epoch_ms_to_cst_day(_MS_20260709_2330Z)
