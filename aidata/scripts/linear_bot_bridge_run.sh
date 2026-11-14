#!/bin/bash
# Scheduled Pulse wrapper for the Linear @bot bridge.
# Usage: linear_bot_bridge_run.sh; AIDASH_JOB_STATE_FILE and
# LINEAR_BOT_BRIDGE_SCRIPT override paths for hermetic/manual runs.
# The result contract is a state.json receipt plus the upstream exit status.
set -uo pipefail
export PATH="/usr/local/bin:/opt/homebrew/bin:$HOME/.local/bin:$PATH"

STATE_FILE="${AIDASH_JOB_STATE_FILE:-$HOME/Library/Application Support/AIDash/jobs/linear-bot-bridge/state.json}"
OUTPUT_DIR="${AIDASH_JOB_OUTPUT_DIR:-$(dirname "$STATE_FILE")}"
BRIDGE_SCRIPT="${LINEAR_BOT_BRIDGE_SCRIPT:-}"
if [ -z "$BRIDGE_SCRIPT" ]; then
  canonical="$HOME/Development/user-skills/skills/linear-board/scripts/linear-bot-bridge.py"
  fallback="$HOME/Development/worktrees/linear-bot-bridge/skills/linear-board/scripts/linear-bot-bridge.py"
  if [ -f "$canonical" ]; then BRIDGE_SCRIPT="$canonical"; else BRIDGE_SCRIPT="$fallback"; fi
fi
mkdir -p "$OUTPUT_DIR" || exit 1
started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
output_file="$(mktemp "$OUTPUT_DIR/.linear-bot-bridge-output.XXXXXX")" || exit 1
trap 'rm -f "$output_file"' EXIT
exit_code=1
if [ -f "$BRIDGE_SCRIPT" ]; then
  python3 "$BRIDGE_SCRIPT" --once --json >"$output_file" 2>&1
  exit_code=$?
else
  printf '%s\n' "linear bot bridge script missing" >"$output_file"
fi
result="failed"
[ "$exit_code" -eq 0 ] && result="succeeded"
python3 - "$STATE_FILE" "$started_at" "$result" "$exit_code" "$output_file" <<'PY'
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

state_path, started_at, result, exit_code, output_path = sys.argv[1:]
now = datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
try:
    output = Path(output_path).read_text(encoding="utf-8", errors="replace").strip()
except OSError:
    output = ""
overview = "## Linear @bot Bridge\n" + (output or f"- exit {exit_code}")
state = {
    "id": "linear-bot-bridge",
    "jobID": "linear-bot-bridge",
    "lastResult": result,
    "lastRunAt": started_at,
    "updatedAt": now,
    "summary": "Linear @bot 双向桥接巡检完成",
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
