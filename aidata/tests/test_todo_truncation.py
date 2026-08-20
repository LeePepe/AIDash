"""Tests for boundary-aware TODO truncation (MY-1434 / MY-1442).

Verifies that long TODOs are never truncated at half-words or broken
identifiers (e.g. "launc", "token", "neu"). Each truncated output must
retain the problem object and an actionable next step or drill-down cue,
and use an explicit … to mark omission.
"""

import pytest

from L5_apps.digest.polish import MAX_TODO, truncate, _is_cjk
from L5_apps.digest.aidash import _todo_items, _prose_containers
from L5_apps.digest.inbox import InboxItem


# Character classes that are valid truncation break-points in the source text.
_BREAK_CHARS = frozenset(" \t\n:/;,，；：、)）】」—")


def _assert_cut_at_token_boundary(result: str, source: str) -> None:
    """Prove the cut is at a source-text token boundary, not mid-word.

    Handles both head-only (' …' suffix) and head+tail (' … ' separator)
    results.  For head+tail, checks the head boundary in the source.
    For head-only/explicit, checks the body-end boundary in the source.
    """
    assert "…" in result, "expected truncation marker"

    if " … " in result:
        # Head+tail: verify the head ends at a word boundary in the source
        head = result.partition(" … ")[0].rstrip()
        assert head, "head is empty"
        pos = len(head)
        if pos < len(source):
            next_char = source[pos]
            assert next_char in _BREAK_CHARS or _is_cjk(next_char), (
                f"Head cut inside a word: '…{head[-15:]}'|"
                f"'{next_char}{source[pos + 1:pos + 10]}…'"
            )
        return

    # Head-only or explicit omission
    body = result.rstrip("…").rstrip()
    assert body, "truncated body is empty"
    pos = len(body)
    if pos < len(source):
        next_char = source[pos]
        assert next_char in _BREAK_CHARS or _is_cjk(next_char), (
            f"Cut inside a word: '…{body[-15:]}'|"
            f"'{next_char}{source[pos + 1:pos + 10]}…'"
        )


# ---------------------------------------------------------------------------
# Representative long TODO inputs (from acceptance criteria).
# All MUST exceed MAX_TODO (120) so truncation actually fires.
# NOTE: fixture identities use neutral invented values per public-repo
# red line — no real account / workspace / bundle identifiers.
# ---------------------------------------------------------------------------
LAUNCHAGENT_TODO = (
    "排查 LaunchAgent 注册失败:SMAppService.register 返回 alreadyRegistered"
    " 但 launchctl print 显示 not-running，需检查 BTM 状态和 plist 路径冲突"
    " 并验证 com.example.myapp.plist 的 MachServices key 匹配 XPC endpoint"
)
assert len(LAUNCHAGENT_TODO) > MAX_TODO, f"fixture must exceed {MAX_TODO}"

SNAPSHOT_CRON_TODO = (
    "修复 snapshot cron 04:00 执行后未收到 XPC 推送:XPC listener"
    " 未注册 mach service，需确认 open -a 是否触发 AgentInstaller"
    " 的 bootstrap 调用并等待 mach-service check-in 完成"
)
assert len(SNAPSHOT_CRON_TODO) > MAX_TODO, f"fixture must exceed {MAX_TODO}"

PR_DIAGNOSIS_TODO = (
    "诊断 PR #847 合并后 20 天未部署:CI green 但 release pipeline"
    " 的 approval gate 卡在 security-review stage，需联系 SRE 确认"
    " gate 配置是否指向已停用的 reviewer group"
)
assert len(PR_DIAGNOSIS_TODO) > MAX_TODO, f"fixture must exceed {MAX_TODO}"

# ASCII-heavy fixture to exercise the word-boundary logic on identifiers.
ASCII_IDENTIFIER_TODO = (
    "排查 LaunchAgent token refresh: neuralIdentifier mapping failed after"
    " tokenExchangeService timeout, need to verify credential store path and"
    " re-authenticate via BTM-managed endpoint configuration"
)
assert len(ASCII_IDENTIFIER_TODO) > MAX_TODO, f"fixture must exceed {MAX_TODO}"


class TestTruncateHeadTail:
    """Head+tail truncation preserves object AND actionable cue."""

    @pytest.mark.unit
    def test_launchagent_preserves_object_and_cue(self):
        """LaunchAgent diagnosis: head has object, tail has actionable cue."""
        result = truncate(LAUNCHAGENT_TODO, MAX_TODO)
        assert len(result) <= MAX_TODO
        assert "…" in result
        # Object must survive in the head
        assert "LaunchAgent" in result
        # Actionable cue from the tail must survive
        assert any(cue in result for cue in ["验证", "匹配", "endpoint", "MachServices"]), (
            f"no actionable cue in: {result}"
        )

    @pytest.mark.unit
    def test_snapshot_cron_preserves_object_and_cue(self):
        result = truncate(SNAPSHOT_CRON_TODO, MAX_TODO)
        assert len(result) <= MAX_TODO
        assert "…" in result
        assert "snapshot cron" in result or "XPC" in result
        assert any(cue in result for cue in ["check-in", "完成", "bootstrap"]), (
            f"no actionable cue in: {result}"
        )

    @pytest.mark.unit
    def test_pr_diagnosis_preserves_object_and_cue(self):
        result = truncate(PR_DIAGNOSIS_TODO, MAX_TODO)
        assert len(result) <= MAX_TODO
        assert "…" in result
        assert "PR" in result
        assert any(cue in result for cue in ["reviewer group", "确认", "gate"]), (
            f"no actionable cue in: {result}"
        )

    @pytest.mark.unit
    def test_ascii_identifiers_not_split(self):
        """Long ASCII identifiers (token, neuralIdentifier) must not be cut mid-word."""
        result = truncate(ASCII_IDENTIFIER_TODO, MAX_TODO)
        assert len(result) <= MAX_TODO
        assert "…" in result
        body = result.rstrip("…").rstrip()
        assert not body.endswith("toke"), f"cut mid-word 'token': {body[-20:]}"
        assert not body.endswith("neu"), f"cut mid-word 'neural': {body[-20:]}"
        assert not body.endswith("neur"), f"cut mid-word 'neural': {body[-20:]}"

    @pytest.mark.unit
    def test_launchagent_truncated_at_smaller_budget(self):
        budget = 80
        result = truncate(LAUNCHAGENT_TODO, budget)
        assert len(result) <= budget
        assert "…" in result
        assert "LaunchAgent" in result

    @pytest.mark.unit
    def test_budget_respected_strictly(self):
        for text in [LAUNCHAGENT_TODO, SNAPSHOT_CRON_TODO, PR_DIAGNOSIS_TODO,
                     ASCII_IDENTIFIER_TODO]:
            result = truncate(text, MAX_TODO)
            assert len(result) <= MAX_TODO, f"Over budget: {len(result)} > {MAX_TODO}"

    @pytest.mark.unit
    def test_ellipsis_is_explicit(self):
        for text in [LAUNCHAGENT_TODO, SNAPSHOT_CRON_TODO, PR_DIAGNOSIS_TODO]:
            result = truncate(text, MAX_TODO)
            assert "…" in result

    @pytest.mark.unit
    def test_short_text_unchanged(self):
        short = "查 pipeline 取消率"
        assert truncate(short, MAX_TODO) == short


class TestRetentionFloor:
    """Truncation must retain meaningful content, not collapse."""

    @pytest.mark.unit
    def test_repeated_long_token_uses_explicit_omission(self):
        """An indivisible tail is named as omitted, never emitted partially."""
        text = "排查 LaunchAgent " + "token" * 40
        result = truncate(text, MAX_TODO)
        assert len(result) <= MAX_TODO
        assert "…" in result
        assert result.startswith("排查 LaunchAgent")
        assert "oversized token omitted" in result
        assert "tokentoke" not in result

    @pytest.mark.unit
    def test_repeated_identifiers_boundary(self):
        """Repeated identifiers with spaces get proper boundary cuts."""
        text = "对象: " + "neuralIdentifier " * 20
        result = truncate(text, MAX_TODO)
        assert len(result) <= MAX_TODO
        _assert_cut_at_token_boundary(result, text)

    @pytest.mark.unit
    def test_continuous_cjk_retains_sixty_percent(self):
        """Continuous CJK text must retain >= 60% of budget, not collapse."""
        text = "排查 " + "一" * 200
        result = truncate(text, MAX_TODO)
        assert len(result) <= MAX_TODO
        assert "…" in result
        body = result.rstrip("…").rstrip()
        assert len(body) >= MAX_TODO * 0.6, (
            f"CJK retention too low: {len(body)}/{MAX_TODO} "
            f"({len(body) / MAX_TODO:.0%})"
        )

    @pytest.mark.unit
    def test_cjk_cut_at_valid_boundary(self):
        """CJK characters are individually addressable cut points."""
        text = "排查 " + "一" * 200
        result = truncate(text, MAX_TODO)
        _assert_cut_at_token_boundary(result, text)


class TestNoBoundaryASCII:
    """Indivisible ASCII tokens are omitted, never partially emitted."""

    @pytest.mark.unit
    def test_indivisible_token_explicit_omission(self):
        """A 200-char token with no boundaries gets a marker, not a hard cut."""
        result = truncate("a" * 200, MAX_TODO)
        assert len(result) <= MAX_TODO
        assert "…" in result
        assert "a" not in result
        assert "oversized token omitted" in result

    @pytest.mark.unit
    def test_indivisible_token_content(self):
        """No prefix of an indivisible identifier leaks as a partial token."""
        result = truncate("x" * 200, MAX_TODO)
        assert "x" not in result
        assert result == "… [oversized token omitted]"

    @pytest.mark.unit
    def test_n_zero_returns_empty(self):
        assert truncate("hello", 0) == ""

    @pytest.mark.unit
    def test_n_negative_returns_empty(self):
        assert truncate("hello", -5) == ""

    @pytest.mark.unit
    def test_n_one_returns_ellipsis(self):
        assert truncate("hello world", 1) == "…"


class TestTodoItemsFallbackTruncation:
    """Rule-based fallback path (_todo_items) respects the same contract."""

    @pytest.mark.unit
    def test_long_todo_line_truncated_at_boundary(self):
        line = f"- P0: {LAUNCHAGENT_TODO}"
        items = _todo_items([line])
        assert len(items) == 1
        title = items[0]["title"]
        assert len(title) <= MAX_TODO
        assert "LaunchAgent" in title

    @pytest.mark.unit
    def test_long_todo_retains_actionable_cue(self):
        """Fallback TODO must retain actionable cue from the tail."""
        line = f"- P0: {LAUNCHAGENT_TODO}"
        items = _todo_items([line])
        title = items[0]["title"]
        assert any(cue in title for cue in ["验证", "匹配", "endpoint", "MachServices"]), (
            f"no actionable cue in fallback: {title}"
        )

    @pytest.mark.unit
    def test_short_todo_line_unchanged(self):
        line = "- P1: 审查浪费:$800"
        items = _todo_items([line])
        assert items[0]["title"] == "审查浪费:$800"
        assert items[0]["priority"] == "medium"  # mapped from P1

    @pytest.mark.unit
    def test_multiple_long_todos_all_respect_budget(self):
        lines = [
            f"- P0: {LAUNCHAGENT_TODO}",
            f"- P1: {SNAPSHOT_CRON_TODO}",
            f"- P2: {PR_DIAGNOSIS_TODO}",
        ]
        items = _todo_items(lines)
        for item in items:
            assert len(item["title"]) <= MAX_TODO
        for item in items:
            assert "…" in item["title"], f"expected truncation: {item['title']}"

    @pytest.mark.unit
    def test_fallback_retains_problem_object(self):
        """Each truncated fallback TODO must retain its problem object."""
        cases = [
            (f"- P0: {LAUNCHAGENT_TODO}", "LaunchAgent"),
            (f"- P1: {SNAPSHOT_CRON_TODO}", "snapshot cron"),
            (f"- P2: {PR_DIAGNOSIS_TODO}", "PR"),
        ]
        for line, expected_obj in cases:
            items = _todo_items([line])
            assert expected_obj in items[0]["title"], (
                f"missing '{expected_obj}' in: {items[0]['title']}"
            )


class TestProseContainersInboxMapping:
    """_prose_containers action_inbox path: real InboxItem → truncated todoList."""

    @pytest.mark.unit
    def test_inbox_long_title_truncated_within_budget(self):
        """Real InboxItem with long title must be truncated via _prose_containers."""
        items = [InboxItem(title=LAUNCHAGENT_TODO, priority="high", bucket="卡顿")]
        containers = _prose_containers("0101", {}, inbox_items=items)
        # Find the 今日规划 container
        plan = [c for c in containers if c.title == "今日规划"]
        assert len(plan) == 1, "expected 今日规划 container"
        card = plan[0].cards[0]
        assert card.type == "todoList"
        todo_items = card.payload["items"]
        assert len(todo_items) == 1
        assert len(todo_items[0]["title"]) <= MAX_TODO

    @pytest.mark.unit
    def test_inbox_preserves_actionable_cue(self):
        """InboxItem title must retain object AND actionable cue after truncation."""
        items = [InboxItem(title=LAUNCHAGENT_TODO, priority="high", bucket="卡顿")]
        containers = _prose_containers("0101", {}, inbox_items=items)
        plan = [c for c in containers if c.title == "今日规划"]
        title = plan[0].cards[0].payload["items"][0]["title"]
        assert "LaunchAgent" in title
        assert any(cue in title for cue in ["验证", "匹配", "endpoint", "MachServices"]), (
            f"no actionable cue in inbox item: {title}"
        )

    @pytest.mark.unit
    def test_inbox_short_title_unchanged(self):
        """Short InboxItem titles pass through without truncation."""
        short = "Review cost anomaly: $800 spike"
        items = [InboxItem(title=short, priority="medium", bucket="计划")]
        containers = _prose_containers("0101", {}, inbox_items=items)
        plan = [c for c in containers if c.title == "今日规划"]
        title = plan[0].cards[0].payload["items"][0]["title"]
        assert title == short

    @pytest.mark.unit
    def test_inbox_multiple_items_all_within_budget(self):
        """Multiple long InboxItems all respect MAX_TODO."""
        items = [
            InboxItem(title=LAUNCHAGENT_TODO, priority="high", bucket="卡顿"),
            InboxItem(title=SNAPSHOT_CRON_TODO, priority="medium", bucket="计划"),
            InboxItem(title=PR_DIAGNOSIS_TODO, priority="low", bucket="发现"),
        ]
        containers = _prose_containers("0101", {}, inbox_items=items)
        plan = [c for c in containers if c.title == "今日规划"]
        # _capped_actions limits to MAX_ACTIONS (3), all should survive
        todo_items = plan[0].cards[0].payload["items"]
        for item in todo_items:
            assert len(item["title"]) <= MAX_TODO, (
                f"inbox item over budget: {len(item['title'])} > {MAX_TODO}"
            )
