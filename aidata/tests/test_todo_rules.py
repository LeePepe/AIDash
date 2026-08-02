import pytest

from L5_apps.digest.sources import RavenTrends, SourceHealth
from L5_apps.digest.todo_rules import todo_candidates


def _rt(**kw) -> RavenTrends:
    empty = []
    base = dict(cost=empty, tokens=empty, requests=empty, waste=empty,
                pipeline_completed=empty, pipeline_cancelled=empty,
                sessions=empty, health=SourceHealth("raven", "ok"))
    base.update(kw)
    return RavenTrends(**base)


@pytest.mark.unit
def test_waste_over_threshold_makes_p1():
    t = _rt(waste=[("2026-07-09", 800.0)])
    todos = todo_candidates(t, "2026-07-10")
    assert any(td.priority == "P1" and "浪费" in td.text for td in todos)


@pytest.mark.unit
def test_no_signals_no_todos():
    t = _rt(waste=[("2026-07-09", 10.0)])
    todos = todo_candidates(t, "2026-07-10")
    assert todos == []


@pytest.mark.unit
def test_pipeline_high_cancel_makes_p0():
    t = _rt(pipeline_completed=[("2026-07-09", 5.0)],
            pipeline_cancelled=[("2026-07-09", 10.0)])  # 10/15 = 67% cancelled
    todos = todo_candidates(t, "2026-07-10")
    assert any(td.priority == "P0" and "pipeline" in td.text.lower() for td in todos)
