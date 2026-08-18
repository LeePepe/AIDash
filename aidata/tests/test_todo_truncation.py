"""Tests for boundary-aware TODO truncation (MY-1434).

Verifies that long TODOs are never truncated at half-words or broken
identifiers (e.g. "launc", "token", "neu"). Each truncated output must
retain the problem object and an actionable next step or drill-down cue,
and use an explicit … to mark omission.
"""

import pytest

from L5_apps.digest.polish import MAX_TODO, truncate
from L5_apps.digest.aidash import _todo_items


# ---------------------------------------------------------------------------
# Three representative long TODO inputs (from acceptance criteria).
# ---------------------------------------------------------------------------
LAUNCHAGENT_TODO = (
    "排查 LaunchAgent 注册失败:SMAppService.register 返回 alreadyRegistered"
    " 但 launchctl print 显示 not-running，需检查 BTM 状态和 plist 路径冲突"
)

SNAPSHOT_CRON_TODO = (
    "修复 snapshot cron 04:00 执行后 AIDash 未收到 XPC 推送:XPC listener"
    " 未注册 mach service，需确认 open -a 是否触发 LaunchdAgentInstaller"
    " 的 bootstrap 调用并等待 mach-service check-in 完成"
)

PR_DIAGNOSIS_TODO = (
    "诊断 PR #847 合并后 20 天未部署:CI green 但 release pipeline"
    " 的 approval gate 卡在 security-review stage，需联系 SRE 确认"
    " gate 配置是否指向已停用的 reviewer group"
)


class TestTruncateBoundaryAware:
    """Boundary-aware truncation never produces half-words."""

    @pytest.mark.unit
    def test_launchagent_not_cut_mid_word(self):
        result = truncate(LAUNCHAGENT_TODO, MAX_TODO)
        assert len(result) <= MAX_TODO
        assert "…" in result
        # Must NOT end with partial identifiers.
        assert not result.rstrip(" …").endswith("launc")
        assert not result.rstrip(" …").endswith("Launc")
        assert not result.rstrip(" …").endswith("LaunchAgen")
        # Must retain the problem object "LaunchAgent".
        assert "LaunchAgent" in result

    @pytest.mark.unit
    def test_snapshot_cron_not_cut_mid_word(self):
        result = truncate(SNAPSHOT_CRON_TODO, MAX_TODO)
        assert len(result) <= MAX_TODO
        assert "…" in result
        # Must NOT end with partial identifiers.
        assert not result.rstrip(" …").endswith("snapsho")
        assert not result.rstrip(" …").endswith("Launchd")
        # Must retain the problem object "snapshot cron" or "XPC".
        assert "snapshot cron" in result or "XPC" in result

    @pytest.mark.unit
    def test_pr_diagnosis_not_cut_mid_word(self):
        result = truncate(PR_DIAGNOSIS_TODO, MAX_TODO)
        assert len(result) <= MAX_TODO
        assert "…" in result
        # Must NOT end with partial identifiers.
        assert not result.rstrip(" …").endswith("pipelin")
        assert not result.rstrip(" …").endswith("securit")
        # Must retain the PR reference.
        assert "PR #847" in result or "PR" in result

    @pytest.mark.unit
    def test_short_text_unchanged(self):
        short = "查 pipeline 取消率"
        assert truncate(short, MAX_TODO) == short

    @pytest.mark.unit
    def test_result_ends_on_complete_word(self):
        """Generic: the text before … must end on a complete word."""
        result = truncate(LAUNCHAGENT_TODO, MAX_TODO)
        # Strip the trailing " …" marker and check the last char is not
        # a letter that would indicate a mid-word cut.
        body = result.rstrip("…").rstrip()
        # The body should end on a punctuation or a CJK char or a word boundary.
        last = body[-1] if body else ""
        # A half-word cut would end on an ASCII letter mid-identifier.
        # Allow: CJK chars, digits, close-parens, punctuation, full words.
        # (Not a perfect check, but catches the class of bugs described.)
        if last.isascii() and last.isalpha():
            # If it ends on an ASCII letter, confirm the next char (had it
            # not been cut) would be a space or punctuation (i.e., word end).
            pos = len(body)
            if pos < len(LAUNCHAGENT_TODO):
                next_char = LAUNCHAGENT_TODO[pos]
                assert next_char in " \t\n:/;,，；：、)）】」—", (
                    f"Truncation split inside a word: '...{body[-10:]}'|'{next_char}...'"
                )

    @pytest.mark.unit
    def test_budget_respected_strictly(self):
        """Output never exceeds the character budget."""
        for text in [LAUNCHAGENT_TODO, SNAPSHOT_CRON_TODO, PR_DIAGNOSIS_TODO]:
            result = truncate(text, MAX_TODO)
            assert len(result) <= MAX_TODO, f"Over budget: {len(result)} > {MAX_TODO}"

    @pytest.mark.unit
    def test_ellipsis_is_explicit(self):
        """Truncated output uses an explicit … (not three dots)."""
        for text in [LAUNCHAGENT_TODO, SNAPSHOT_CRON_TODO, PR_DIAGNOSIS_TODO]:
            result = truncate(text, MAX_TODO)
            assert "…" in result


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
        # Not cut mid-word.
        assert not title.rstrip(" …").endswith("launc")

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
            assert "…" in item["title"]
