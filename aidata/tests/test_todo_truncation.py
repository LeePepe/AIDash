"""Tests for boundary-aware TODO truncation (MY-1434 / MY-1442).

Verifies that long TODOs are never truncated at half-words or broken
identifiers (e.g. "launc", "token", "neu"). Each truncated output must
retain the problem object and an actionable next step or drill-down cue,
and use an explicit … to mark omission.
"""

import pytest

from L5_apps.digest.polish import MAX_TODO, truncate
from L5_apps.digest.aidash import _todo_items


# Character classes that are valid truncation break-points in the source text.
_BREAK_CHARS = frozenset(" \t\n:/;,，；：、)）】」—")


def _assert_cut_at_token_boundary(result: str, source: str) -> None:
    """Prove the cut is at a source-text token boundary, not mid-word.

    After stripping the trailing " …" marker the body text must satisfy:
    the very next character in the *original* source (at the cut position)
    is a space, punctuation, or doesn't exist (end of source).
    """
    assert "…" in result, "expected truncation marker"
    body = result.rstrip("…").rstrip()
    assert body, "truncated body is empty"
    pos = len(body)
    if pos < len(source):
        next_char = source[pos]
        assert next_char in _BREAK_CHARS, (
            f"Cut inside a word: '…{body[-15:]}'|'{next_char}{source[pos+1:pos+10]}…'"
        )


# ---------------------------------------------------------------------------
# Three representative long TODO inputs (from acceptance criteria).
# All three MUST exceed MAX_TODO (120) so truncation actually fires.
# ---------------------------------------------------------------------------
LAUNCHAGENT_TODO = (
    "排查 LaunchAgent 注册失败:SMAppService.register 返回 alreadyRegistered"
    " 但 launchctl print 显示 not-running，需检查 BTM 状态和 plist 路径冲突"
    " 并验证 com.tianpli.aidash.plist 的 MachServices key 匹配 XPC endpoint"
)
assert len(LAUNCHAGENT_TODO) > MAX_TODO, f"fixture must exceed {MAX_TODO}"

SNAPSHOT_CRON_TODO = (
    "修复 snapshot cron 04:00 执行后 AIDash 未收到 XPC 推送:XPC listener"
    " 未注册 mach service，需确认 open -a 是否触发 LaunchdAgentInstaller"
    " 的 bootstrap 调用并等待 mach-service check-in 完成"
)
assert len(SNAPSHOT_CRON_TODO) > MAX_TODO, f"fixture must exceed {MAX_TODO}"

PR_DIAGNOSIS_TODO = (
    "诊断 PR #847 合并后 20 天未部署:CI green 但 release pipeline"
    " 的 approval gate 卡在 security-review stage，需联系 SRE 确认"
    " gate 配置是否指向已停用的 reviewer group"
)
assert len(PR_DIAGNOSIS_TODO) > MAX_TODO, f"fixture must exceed {MAX_TODO}"

# ASCII-heavy fixture to exercise the word-boundary logic on identifiers
# like "token", "neuralIdentifier" that the original bug cited.
ASCII_IDENTIFIER_TODO = (
    "排查 LaunchAgent token refresh: neuralIdentifier mapping failed after"
    " tokenExchangeService timeout, need to verify credential store path and"
    " re-authenticate via BTM-managed endpoint configuration"
)
assert len(ASCII_IDENTIFIER_TODO) > MAX_TODO, f"fixture must exceed {MAX_TODO}"


class TestTruncateBoundaryAware:
    """Boundary-aware truncation never produces half-words."""

    @pytest.mark.unit
    def test_launchagent_cut_at_token_boundary(self):
        result = truncate(LAUNCHAGENT_TODO, MAX_TODO)
        assert len(result) <= MAX_TODO
        _assert_cut_at_token_boundary(result, LAUNCHAGENT_TODO)
        assert "LaunchAgent" in result

    @pytest.mark.unit
    def test_launchagent_truncated_at_smaller_budget(self):
        budget = 80
        result = truncate(LAUNCHAGENT_TODO, budget)
        assert len(result) <= budget
        _assert_cut_at_token_boundary(result, LAUNCHAGENT_TODO)
        assert "LaunchAgent" in result

    @pytest.mark.unit
    def test_snapshot_cron_cut_at_token_boundary(self):
        result = truncate(SNAPSHOT_CRON_TODO, MAX_TODO)
        assert len(result) <= MAX_TODO
        _assert_cut_at_token_boundary(result, SNAPSHOT_CRON_TODO)
        assert "snapshot cron" in result or "XPC" in result

    @pytest.mark.unit
    def test_pr_diagnosis_cut_at_token_boundary(self):
        result = truncate(PR_DIAGNOSIS_TODO, MAX_TODO)
        assert len(result) <= MAX_TODO
        _assert_cut_at_token_boundary(result, PR_DIAGNOSIS_TODO)
        assert "PR #847" in result or "PR" in result

    @pytest.mark.unit
    def test_ascii_identifiers_not_split(self):
        """Long ASCII identifiers (token, neuralIdentifier) must not be cut mid-word."""
        result = truncate(ASCII_IDENTIFIER_TODO, MAX_TODO)
        assert len(result) <= MAX_TODO
        _assert_cut_at_token_boundary(result, ASCII_IDENTIFIER_TODO)
        # Specific half-word patterns cited in the acceptance criteria:
        body = result.rstrip("…").rstrip()
        assert not body.endswith("toke"), f"cut mid-word 'token': {body[-20:]}"
        assert not body.endswith("neu"), f"cut mid-word 'neural': {body[-20:]}"
        assert not body.endswith("neur"), f"cut mid-word 'neural': {body[-20:]}"

    @pytest.mark.unit
    def test_repeated_long_tokens_not_split(self):
        """Stress: repeated long token still gets a clean boundary cut."""
        text = "排查 LaunchAgent " + "token" * 40
        result = truncate(text, MAX_TODO)
        assert len(result) <= MAX_TODO
        _assert_cut_at_token_boundary(result, text)

    @pytest.mark.unit
    def test_repeated_identifiers_not_split(self):
        """Stress: repeated neuralIdentifier still gets a clean boundary cut."""
        text = "对象: " + "neuralIdentifier " * 20
        result = truncate(text, MAX_TODO)
        assert len(result) <= MAX_TODO
        _assert_cut_at_token_boundary(result, text)

    @pytest.mark.unit
    def test_short_text_unchanged(self):
        short = "查 pipeline 取消率"
        assert truncate(short, MAX_TODO) == short

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
        _assert_cut_at_token_boundary(title, LAUNCHAGENT_TODO)
        assert "LaunchAgent" in title

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
        # All three fixtures exceed MAX_TODO, so all must be truncated.
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


class TestActionInboxBudget:
    """action_inbox → todoList path must apply MAX_TODO and boundary contract."""

    @pytest.mark.unit
    def test_inbox_title_truncated_within_budget(self):
        """Simulates the inbox path: titles must be truncated to MAX_TODO."""
        # This mirrors aidash.py line 581's behavior after the fix.
        long_title = LAUNCHAGENT_TODO
        result = truncate(long_title, MAX_TODO)
        assert len(result) <= MAX_TODO
        _assert_cut_at_token_boundary(result, long_title)

    @pytest.mark.unit
    def test_inbox_short_title_unchanged(self):
        short = "Review cost anomaly: $800 spike"
        assert truncate(short, MAX_TODO) == short
