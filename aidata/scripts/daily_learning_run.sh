#!/bin/bash
# Scheduled Pulse wrapper for the daily learning proposal job.
# Usage: daily_learning_run.sh; AIDASH_JOB_STATE_FILE and DIGEST_VAULT_SCRIPT
# override the state path and upstream script for hermetic/manual runs.
# The result contract is a state.json receipt plus the upstream exit status.
set -uo pipefail
export PATH="/usr/local/bin:/opt/homebrew/bin:$HOME/.local/bin:$PATH"

STATE_FILE="${AIDASH_JOB_STATE_FILE:-$HOME/Library/Application Support/AIDash/jobs/daily-learning/state.json}"
OUTPUT_DIR="${AIDASH_JOB_OUTPUT_DIR:-$(dirname "$STATE_FILE")}"
VAULT_SCRIPT="${DIGEST_VAULT_SCRIPT:-$HOME/Development/user-skills/skills/knowledge-digest/scripts/digest_vault.py}"
mkdir -p "$OUTPUT_DIR" || exit 1

started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
last_result="failed"
exit_code=1
fallback_used=0
output_file="$(mktemp "$OUTPUT_DIR/.daily-learning-output.XXXXXX")" || exit 1
trap 'rm -f "$output_file"' EXIT

if [ -f "$VAULT_SCRIPT" ]; then
  python3 "$VAULT_SCRIPT" discover-topics --top 3 --propose-aidash --propose-linear --no-materialize >"$output_file" 2>&1
  exit_code=$?
  if [ "$exit_code" -eq 2 ] && awk '/--propose-linear/ && /(unknown option|unrecognized arguments|no such option)/ { found=1 } END { exit !found }' "$output_file"; then
    fallback_used=1
    python3 "$VAULT_SCRIPT" discover-topics --top 3 --propose-aidash --no-materialize >"$output_file" 2>&1
    exit_code=$?
  fi
else
  printf '%s\n' "digest vault script missing" >"$output_file"
fi

[ "$exit_code" -eq 0 ] && last_result="succeeded"
python3 - "$STATE_FILE" "$started_at" "$last_result" "$exit_code" "$output_file" "$fallback_used" <<'PY'
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

state_path, started_at, result, exit_code, output_path, fallback_used = sys.argv[1:]
now = datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
try:
    output = Path(output_path).read_text(encoding="utf-8", errors="replace").strip()
except OSError:
    output = ""
context = "- Compatibility fallback: AIDash-only; Linear unsupported.\n" if fallback_used == "1" else ""
overview = "## Daily Learning\n" + context + (output or f"- exit {exit_code}")
state = {
    "id": "daily-learning",
    "jobID": "daily-learning",
    "lastResult": result,
    "lastRunAt": started_at,
    "updatedAt": now,
    "summary": "每日 3 题候选 → Linear & AIDash",
    "overviewMd": overview,
}
path = Path(state_path)
path.parent.mkdir(parents=True, exist_ok=True)
tmp = path.with_name(f".{path.name}.{os.getpid()}.tmp")
try:
    tmp.write_text(json.dumps(state, ensure_ascii=False) + "\n", encoding="utf-8")
    os.replace(tmp, path)
finally:
    try:
        tmp.unlink()
    except FileNotFoundError:
        pass
PY
state_write_code=$?
if [ "$state_write_code" -ne 0 ]; then
  exit "$state_write_code"
fi
exit "$exit_code"
