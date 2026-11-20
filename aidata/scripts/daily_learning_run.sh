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

sync_job_artifacts() {
  local job_output_dir="$1" state_file="$2" job_id="$3"
  local cloud_docs="$HOME/Library/Mobile Documents/com~apple~CloudDocs"
  local sync_root="${AIDASH_ICLOUD_SYNC_DIR:-$cloud_docs/AIDashSync}"
  if [ -z "${AIDASH_ICLOUD_SYNC_DIR:-}" ] && [ ! -d "$cloud_docs" ]; then
    return 0
  fi
  local target_dir="$sync_root/jobs/$job_id"
  mkdir -p "$target_dir" || return 1
  local name source tmp
  for name in state.json actions.jsonl skills-roi.json agent-efficiency.json; do
    source="$job_output_dir/$name"
    [ "$name" = "state.json" ] && source="$state_file"
    [ -f "$source" ] || continue
    tmp="$(mktemp "$target_dir/.${name}.XXXXXX")" || return 1
    if ! cp "$source" "$tmp"; then
      rm -f "$tmp"
      return 1
    fi
    mv -f "$tmp" "$target_dir/$name" || return 1
  done
}

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
if ! sync_job_artifacts "$OUTPUT_DIR" "$STATE_FILE" "daily-learning"; then
  echo "daily-learning: iCloud job artifact mirror warning" >&2
fi
exit "$exit_code"
