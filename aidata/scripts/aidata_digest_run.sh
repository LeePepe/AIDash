#!/bin/bash
# aidata-digest cron runner (ADR-12). Prepared, NOT auto-installed.
#
# Runs the full digest chain for "yesterday" (CST): collect fresh source data,
# normalize each source, rebuild the warehouse, then build + archive + push the
# digest. The AIDash push is best-effort and non-fatal — the local md archive is
# always written first, so a push failure never loses the digest (ADR-16/23).
#
# The Hermes cron job (scripts/aidata_digest_cron.py) invokes this at 04:00 CST.
# `collect` must run before `digest`; this script chains them so the single job
# is self-contained.
#
# ⚠️ DUAL MAINTENANCE: cron actually executes ~/.hermes/scripts/aidata_digest_run.sh,
# which is an independent COPY of this file (not a symlink). After editing this
# one you MUST sync it:
#     cp aidata/scripts/aidata_digest_run.sh ~/.hermes/scripts/aidata_digest_run.sh
# Forgetting this is why an edit here can appear to have no effect.
set -uo pipefail

AIDATA_HOME="${AIDATA_HOME:-$HOME/Development/AIDash/aidata}"
cd "$AIDATA_HOME" || { echo "aidata home not found: $AIDATA_HOME" >&2; exit 1; }

# CST (Asia/Shanghai) "today" — digest reports on the CST day before this.
TODAY="$(TZ=Asia/Shanghai date +%Y-%m-%d)"
JOB_STATE_FILE="${AIDASH_JOB_STATE_FILE:-$HOME/Library/Application Support/AIDash/jobs/aidata-digest/state.json}"
JOB_OUTPUT_DIR="${AIDASH_JOB_OUTPUT_DIR:-$(dirname "$JOB_STATE_FILE")}"
SKILLS_ROI_FILE="$JOB_OUTPUT_DIR/skills-roi.json"
CHAIN_START_TS="$(date +%s)"

echo "[aidata-digest] $(date) — chain start (report_date=$TODAY)"

# Destructive worktree cleanup is intentionally not part of the digest chain.
# Operators may run git-gc separately after reviewing its receipt.

# Stage 1: L1 collect — per-source with a wall-clock budget so no single slow/hung source
# (e.g. multica_run's per-issue CLI walk, or an az SSO stall) blocks the whole
# chain. Each source is incremental (watermarks), so a timed-out source resumes
# next run; the digest still builds from whatever landed.
STAGE1_START="$(date +%s)"
COLLECT_OK=0
COLLECT_FAIL=0
PER_SOURCE_TIMEOUT="${PER_SOURCE_TIMEOUT:-300}"
_TIMEOUT_BIN="$(command -v timeout || command -v gtimeout || true)"
SOURCES="raven claude_jsonl claude_prompts codex_prompts kimi_prompts multica_issue linear_issue multica_run multica_comment claude_job github_repo github_pr pr_cache ado_pr state_db hermes_tools copilot_cli hermes_messages memory_claude memory_hermes_db memory_hermes_md news aidash_events local_git browser_history gecko gtt_ledger gtt_receipt bot_tl workspace_hygiene github_ci github_ruleset release_tf mail_inbox work_teams_bridge"
for src in $SOURCES; do
  echo "[aidata-digest]   collect $src (budget ${PER_SOURCE_TIMEOUT}s)"
  if [ -n "$_TIMEOUT_BIN" ]; then
    if "$_TIMEOUT_BIN" "$PER_SOURCE_TIMEOUT" python3 cli.py collect --source "$src"; then
      COLLECT_OK=$((COLLECT_OK + 1))
    else
      COLLECT_FAIL=$((COLLECT_FAIL + 1))
      echo "[aidata-digest]   ! $src collect timed out/failed — using prior data"
    fi
  else
    if python3 cli.py collect --source "$src"; then
      COLLECT_OK=$((COLLECT_OK + 1))
    else
      COLLECT_FAIL=$((COLLECT_FAIL + 1))
      echo "[aidata-digest]   ! $src collect failed — using prior data"
    fi
  fi
done
STAGE1_DUR=$(( $(date +%s) - STAGE1_START ))
STAGE1_STATUS=$([ "$COLLECT_FAIL" -eq 0 ] && echo "ok" || echo "warning")
STAGE1_RC=$([ "$COLLECT_FAIL" -eq 0 ] && echo 0 || echo 1)

# Stage 2: L2 normalize & L3 merge
STAGE2_START="$(date +%s)"
STAGE2_RC=0
python3 cli.py normalize || STAGE2_RC=$?
if [ "$STAGE2_RC" -eq 0 ]; then
  python3 cli.py merge || STAGE2_RC=$?
fi
STAGE2_DUR=$(( $(date +%s) - STAGE2_START ))
STAGE2_STATUS=$([ "$STAGE2_RC" -eq 0 ] && echo "ok" || echo "failed")

# Stage 3: Compute M1-M5 Agent Efficiency, S1-S12 Skill ROI, and L4 Retro Signals
STAGE3_START="$(date +%s)"
STAGE3_RC=0
RETRO_ENGINE="${RETRO_ENGINE:-$HOME/Development/user-skills/skills/retro-loop/scripts/retro_story_engine.py}"
mkdir -p "$JOB_OUTPUT_DIR"
ROI_REPORT="$(mktemp "$JOB_OUTPUT_DIR/.skills-roi-report.XXXXXX")" || exit 1
ROI_RC=1
trap 'rm -f "$ROI_REPORT"' EXIT
if [ -f "$RETRO_ENGINE" ]; then
  python3 "$RETRO_ENGINE" agent-efficiency --auto-propose >/dev/null \
    || { echo "[aidata-digest]   ! agent-efficiency auto-propose warning"; STAGE3_RC=1; }
  ROI_RC=0
  python3 "$RETRO_ENGINE" skill-roi --auto-propose >"$ROI_REPORT" \
    || { ROI_RC=$?; echo "[aidata-digest]   ! skill-roi auto-propose warning"; STAGE3_RC=1; }
  python3 "$RETRO_ENGINE" discover >/dev/null \
    || { echo "[aidata-digest]   ! retro discover warning"; STAGE3_RC=1; }
else
  echo "[aidata-digest]   ! retro engine missing"
  STAGE3_RC=1
fi
if ! python3 -m L5_apps.digest.skills_roi_snapshot --report "$ROI_REPORT" --output "$SKILLS_ROI_FILE" --producer-exit-code "$ROI_RC"; then
  echo "[aidata-digest]   ! skills-roi snapshot failed"
  STAGE3_RC=1
fi
STAGE3_DUR=$(( $(date +%s) - STAGE3_START ))
STAGE3_STATUS=$([ "$STAGE3_RC" -eq 0 ] && echo "ok" || echo "warning")

# Stage 4: Three Daily Learning Topic Candidates → Linear & AIDash (--no-materialize)
STAGE4_START="$(date +%s)"
STAGE4_RC=0
DIGEST_VAULT_SCRIPT="${DIGEST_VAULT_SCRIPT:-$HOME/Development/user-skills/skills/knowledge-digest/scripts/digest_vault.py}"
if [ -f "$DIGEST_VAULT_SCRIPT" ]; then
  python3 "$DIGEST_VAULT_SCRIPT" discover-topics --top 3 --propose-aidash --propose-linear --no-materialize >/dev/null \
    || { echo "[aidata-digest]   ! discover-topics warning"; STAGE4_RC=1; }
else
  echo "[aidata-digest]   ! digest vault missing"
  STAGE4_RC=1
fi
python3 -m L5_apps.digest.event_bridge --consume-learning >/dev/null \
  || { echo "[aidata-digest]   ! approved learning queue consumer blocked"; STAGE4_RC=1; }
STAGE4_DUR=$(( $(date +%s) - STAGE4_START ))
STAGE4_STATUS=$([ "$STAGE4_RC" -eq 0 ] && echo "ok" || echo "warning")

# Stage 5: L5 build + archive (必成) + best-effort AIDash push (非阻塞)
STAGE5_START="$(date +%s)"
STAGE5_RC=0
python3 cli.py digest --date "$TODAY" --llm --aidash || STAGE5_RC=$?
STAGE5_DUR=$(( $(date +%s) - STAGE5_START ))
STAGE5_STATUS=$([ "$STAGE5_RC" -eq 0 ] && echo "ok" || echo "failed")

TOTAL_DUR=$(( $(date +%s) - CHAIN_START_TS ))
FINAL_RC=0
if [ "$STAGE1_RC" -ne 0 ] || [ "$STAGE2_RC" -ne 0 ] || [ "$STAGE3_RC" -ne 0 ] || [ "$STAGE4_RC" -ne 0 ] || [ "$STAGE5_RC" -ne 0 ]; then
  FINAL_RC=1
fi

# Write structured 5-stage receipt into ~/Library/Application Support/AIDash/jobs/aidata-digest/state.json
python3 - "$JOB_STATE_FILE" "$TODAY" "$FINAL_RC" "$TOTAL_DUR" \
  "$STAGE1_STATUS" "$STAGE1_DUR" "$COLLECT_OK" "$COLLECT_FAIL" \
  "$STAGE2_STATUS" "$STAGE2_DUR" \
  "$STAGE3_STATUS" "$STAGE3_DUR" \
  "$STAGE4_STATUS" "$STAGE4_DUR" \
  "$STAGE5_STATUS" "$STAGE5_DUR" "$SKILLS_ROI_FILE" <<'PYEOF' || true
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

(
    state_path_raw,
    report_date,
    final_rc_s,
    total_dur_s,
    s1_st,
    s1_dur,
    col_ok,
    col_fail,
    s2_st,
    s2_dur,
    s3_st,
    s3_dur,
    s4_st,
    s4_dur,
    s5_st,
    s5_dur,
    skills_snapshot_path,
) = sys.argv[1:18]

state_path = Path(state_path_raw)
state_path.parent.mkdir(parents=True, exist_ok=True)
now_iso = datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
final_rc = int(final_rc_s)
total_dur = int(total_dur_s)
try:
    existing = json.loads(state_path.read_text(encoding="utf-8")) if state_path.exists() else {}
except (OSError, json.JSONDecodeError):
    existing = {}
if not isinstance(existing, dict):
    existing = {}
try:
    roi_snapshot = json.loads(Path(skills_snapshot_path).read_text(encoding="utf-8"))
except (OSError, ValueError):
    roi_snapshot = {}

stages = [
    {
        "id": "collect",
        "title": "① 个人源采集",
        "status": s1_st,
        "exitCode": 0 if s1_st == "ok" else 1,
        "durationSec": int(s1_dur),
        "sourceAsOf": report_date,
        "detail": f"{col_ok} 源成功" + (f" · {col_fail} 降级" if int(col_fail) > 0 else ""),
    },
    {
        "id": "normalize_merge",
        "title": "② L2/L3 入仓",
        "status": s2_st,
        "exitCode": 0 if s2_st == "ok" else 1,
        "durationSec": int(s2_dur),
        "sourceAsOf": report_date,
        "detail": "幂等合并完成" if s2_st == "ok" else "入仓异常",
    },
    {
        "id": "retro_roi",
        "title": "③ Retro/ROI",
        "status": s3_st,
        "exitCode": 0 if s3_st == "ok" else 1,
        "durationSec": int(s3_dur),
        "sourceAsOf": roi_snapshot.get("source_as_of") or "unknown",
        "detail": "M1-M5 & S1-S12 · " + str(roi_snapshot.get("coverage_status", "unknown")),
    },
    {
        "id": "learning_topics",
        "title": "④ 学习寻题",
        "status": s4_st,
        "exitCode": 0 if s4_st == "ok" else 1,
        "durationSec": int(s4_dur),
        "sourceAsOf": report_date,
        "detail": "每日 3 题候选 → Linear & AIDash",
    },
    {
        "id": "digest_push",
        "title": "⑤ Brief 投递",
        "status": s5_st,
        "exitCode": 0 if s5_st == "ok" else 1,
        "durationSec": int(s5_dur),
        "sourceAsOf": report_date,
        "detail": "已归档并推送" if s5_st == "ok" else "投递失败",
    },
]
pass_cnt = sum(1 for st in stages if st["status"] == "ok")
overview_md = (
    f"最近脉搏 ({report_date})：{pass_cnt}/5 阶段通过，总耗时 {total_dur}s。"
    f"采集 {col_ok} 个数据源，完成 L2/L3 星型入仓、Skills ROI (S1-S12) 诊断、每日新学习选题去重与 Brief/Actionable 投递。"
)

doc = dict(existing)
doc.update({
    "id": existing.get("id", "aidata-digest"),
    "jobID": existing.get("jobID", "aidata-digest"),
    "status": "idle" if final_rc == 0 else "failed",
    "lastResult": "success" if final_rc == 0 else "failure",
    "lastRunAt": now_iso,
    "lastExitCode": final_rc,
    "durationSec": total_dur,
    "sourceAsOf": report_date,
    "overviewMd": overview_md,
    "stages": stages,
})
tmp = state_path.with_suffix(".json.tmp")
tmp.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
tmp.replace(state_path)
PYEOF

echo "[aidata-digest] $(date) — chain done (rc=$FINAL_RC, duration=${TOTAL_DUR}s)"
exit "$FINAL_RC"
