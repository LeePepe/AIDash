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

echo "[aidata-digest] $(date) — chain start (report_date=$TODAY)"

# L1 collect — per-source with a wall-clock budget so no single slow/hung source
# (e.g. multica_run's per-issue CLI walk, or an az SSO stall) blocks the whole
# chain. Each source is incremental (watermarks), so a timed-out source resumes
# next run; the digest still builds from whatever landed. PER_SOURCE_TIMEOUT can
# be overridden via env. `timeout` may be absent on stock macOS — fall back to
# an unbounded call if so.
PER_SOURCE_TIMEOUT="${PER_SOURCE_TIMEOUT:-300}"
_TIMEOUT_BIN="$(command -v timeout || command -v gtimeout || true)"
# Order matters: the GitHub sources (github_repo radar, github_pr) are fast `gh
# api` calls but were previously LAST, so on a slow night the per-source budget
# accumulated and they got starved (Mac asleep / earlier source hung) — leaving
# the radar stale and PR counts empty. Move them ahead of the slow/optional
# sources so a daily snapshot is reliably captured. github_pr is new (feeds the
# 开了N个PR line); without it the chain never collects GitHub PRs.
#
# This explicit list MUST equal config.SOURCES (asserted by
# tests/test_runner_sources.py so a newly-added source can never silently miss
# the 04:00 cron again). Ordering: multica_* grouped, then the fast GitHub
# snapshot, then the cheap DB/memory sources, then the slower/optional new L1
# sources (news, aidash_events, local_git, browser_history, gecko) last so their
# per-source budget can't starve the reliable snapshot sources.
SOURCES="raven claude_jsonl claude_prompts codex_prompts kimi_prompts multica_issue multica_run multica_comment claude_job github_repo github_pr pr_cache ado_pr state_db hermes_tools hermes_messages memory_claude memory_hermes_db memory_hermes_md news aidash_events local_git browser_history gecko"
for src in $SOURCES; do
  echo "[aidata-digest]   collect $src (budget ${PER_SOURCE_TIMEOUT}s)"
  if [ -n "$_TIMEOUT_BIN" ]; then
    "$_TIMEOUT_BIN" "$PER_SOURCE_TIMEOUT" python3 cli.py collect --source "$src" \
      || echo "[aidata-digest]   ! $src collect timed out/failed — using prior data"
  else
    python3 cli.py collect --source "$src" \
      || echo "[aidata-digest]   ! $src collect failed — using prior data"
  fi
done

python3 cli.py normalize
python3 cli.py merge

# L5: build + archive (必成) + best-effort AIDash push (非阻塞). --llm adds the
# guarded polish; it too falls back to the pure template on any failure.
python3 cli.py digest --date "$TODAY" --llm --aidash

echo "[aidata-digest] $(date) — chain done"
