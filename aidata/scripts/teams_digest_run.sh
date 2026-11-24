#!/bin/bash
# Scheduled Pulse wrapper for the Teams self-meeting digest.
# The upstream dsh-teams CLI is deliberately injected through environment
# variables in tests and may degrade to read-only when delivery is unavailable.
set -uo pipefail
export PATH="/usr/local/bin:/opt/homebrew/bin:$HOME/.local/bin:$PATH"

STATE_FILE="${AIDASH_JOB_STATE_FILE:-$HOME/Library/Application Support/AIDash/jobs/teams-digest/state.json}"
OUTPUT_DIR="${AIDASH_JOB_OUTPUT_DIR:-$(dirname "$STATE_FILE")}"
TEAMS_SCRIPT="${TEAMS_DIGEST_CLI_SCRIPT:-$HOME/Development/dsh-personal-plugins/packages/dsh-teams/cli.js}"
NODE="${NODE_BIN:-node}"
mkdir -p "$OUTPUT_DIR" || exit 1

started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
output_file="$(mktemp "$OUTPUT_DIR/.teams-digest-output.XXXXXX")" || exit 1
trap 'rm -f "$output_file"' EXIT

"$NODE" "$TEAMS_SCRIPT" run --deliver-self-meeting >"$output_file" 2>&1
exit_code=$?
fallback_used=0
if [ "$exit_code" -ne 0 ] && grep -Eq 'only `run --read-only` is supported|(--deliver-self-meeting.*(unrecognized|unknown|unsupported))|(unrecognized.*--deliver-self-meeting)' "$output_file"; then
  fallback_used=1
  "$NODE" "$TEAMS_SCRIPT" run --read-only >"$output_file" 2>&1
  exit_code=$?
fi

result="failed"
[ "$exit_code" -eq 0 ] && result="succeeded"
python3 - "$STATE_FILE" "$started_at" "$result" "$exit_code" "$output_file" "$fallback_used" <<'PY'
import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

state_path, started_at, result, exit_code, output_path, fallback_used = sys.argv[1:]
exit_code = int(exit_code)
try:
    output = Path(output_path).read_text(encoding="utf-8", errors="replace")
except OSError:
    output = ""

stage_defs = [
    ("auth_check", "[Stage 1/4] Auth Check"),
    ("unread_sync", "[Stage 2/4] Unread Sync"),
    ("jev_draft", "[Stage 3/4] Jev & Draft"),
    ("self_meeting_delivery", "[Stage 4/4] Self-Meeting Delivery"),
]
pattern = re.compile(r"^\[Stage ([1-4])/4\] ([^:]+):?\s*(.*)$")
reached: dict[int, str] = {}
for line in output.splitlines():
    match = pattern.match(line.strip())
    if match:
        reached[int(match.group(1))] = match.group(3).strip()
last_reached = max(reached, default=0)
stages = []
for index, (stage_id, title) in enumerate(stage_defs, start=1):
    if exit_code == 0:
        status = "passed" if not reached or index in reached else "unknown"
    elif index < last_reached:
        status = "passed"
    elif index == last_reached:
        status = "failed"
    else:
        status = "unknown"
    stage = {"id": stage_id, "title": title, "status": status}
    if index in reached and reached[index]:
        stage["detail"] = reached[index]
    if status == "passed":
        stage["exitCode"] = 0
    elif status == "failed":
        stage["exitCode"] = exit_code
    stages.append(stage)

bullets = []
if fallback_used == "1":
    bullets.append("- Compatibility fallback: --read-only")
for index, (_, title) in enumerate(stage_defs, start=1):
    detail = reached.get(index, "")
    suffix = f": {detail}" if detail else ""
    bullets.append(f"- {title}{suffix}")
overview = "## Teams 会话草稿\n" + "\n".join(bullets)
now = datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
state = {
    "id": "teams-digest",
    "jobID": "teams-digest",
    "lastResult": result,
    "lastRunAt": started_at,
    "updatedAt": now,
    "summary": "Teams 未读扫描与 Self-Meeting 草稿投递",
    "overviewMd": overview,
    "stages": stages,
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
