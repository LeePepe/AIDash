#!/bin/zsh
set -u

job_id="${1:-}"
interpreter="${2:-}"
script_path="${3:-}"
if [[ -z "$job_id" || -z "$interpreter" || -z "$script_path" ]]; then
  exit 64
fi

state_root="$HOME/Library/Application Support/AIDash/jobs/$job_id"
lock_dir="$state_root/.running.lock"
pid_file="$lock_dir/pid"
mkdir -p "$state_root"

acquire_lock() {
  if mkdir "$lock_dir" 2>/dev/null; then
    printf '%s\n' "$$" > "$pid_file" 2>/dev/null || true
    return 0
  fi

  if [[ -f "$pid_file" ]]; then
    local holder_pid
    holder_pid="$(cat "$pid_file" 2>/dev/null | tr -d '[:space:]')"
    if [[ -n "$holder_pid" && "$holder_pid" =~ ^[0-9]+$ ]] && kill -0 "$holder_pid" 2>/dev/null; then
      return 1
    fi
  fi

  rm -f "$pid_file" 2>/dev/null || true
  rmdir "$lock_dir" 2>/dev/null || true
  if mkdir "$lock_dir" 2>/dev/null; then
    printf '%s\n' "$$" > "$pid_file" 2>/dev/null || true
    return 0
  fi
  return 1
}

if ! acquire_lock; then
  /usr/bin/python3 - "$state_root/state.json" "$job_id" <<'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

path = Path(sys.argv[1])
job_id = sys.argv[2]
now = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
path.write_text(json.dumps({
    "id": job_id,
    "updatedAt": now,
    "lastResult": "coalesced",
    "lastRunAt": now,
}, ensure_ascii=False) + "\n", encoding="utf-8")
PY
  exit 0
fi

cleanup_lock() {
  rm -f "$pid_file" 2>/dev/null || true
  rmdir "$lock_dir" 2>/dev/null || true
}
trap 'cleanup_lock' EXIT INT TERM
"$interpreter" "$script_path"
exit_code=$?
cleanup_lock
exit "$exit_code"
