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
mkdir -p "$state_root"

if ! mkdir "$lock_dir" 2>/dev/null; then
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

trap 'rmdir "$lock_dir" 2>/dev/null || true' EXIT
exec "$interpreter" "$script_path"
