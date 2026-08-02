import pytest

from L5_apps.digest.sources import fetch_raven_trends, RavenTrends, SourceHealth


@pytest.mark.integration
def test_fetch_raven_trends_returns_series_and_ok_health():
    t = fetch_raven_trends()
    assert isinstance(t, RavenTrends)
    assert t.health.state == "ok"
    # cost series has 2026-07-09 with a plausible positive value. Range-based,
    # not an exact literal — cost drifts as new raven data is collected, so a
    # hardcoded number would break on every re-collect (this is an integration
    # test against the live warehouse). The hermetic exact-value check lives in
    # test_digest_golden.py against a frozen fixture.
    cost = dict(t.cost)
    assert cost["2026-07-09"] > 1000.0
    # every series is a list of (day, number) tuples
    for day, val in t.cost:
        assert isinstance(day, str) and isinstance(val, (int, float))


@pytest.mark.unit
def test_source_health_dataclass_shape():
    h = SourceHealth(name="raven", state="ok", detail="")
    assert h.name == "raven" and h.state == "ok"


@pytest.mark.unit
def test_fetch_raven_trends_degrades_on_query_failure(monkeypatch):
    # ADR-23: a query failure must degrade to empty series + error health,
    # never propagate the exception.
    import serve

    def boom(*args, **kwargs):
        raise RuntimeError("simulated query failure")

    monkeypatch.setattr(serve, "run_query", boom)
    t = fetch_raven_trends()
    assert t.health.state == "error"
    assert "simulated query failure" in t.health.detail
    assert t.cost == [] and t.tokens == [] and t.requests == []
    assert t.waste == [] and t.pipeline_completed == [] and t.sessions == []
