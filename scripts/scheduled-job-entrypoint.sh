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

exec /usr/bin/python3 - "$state_root" "$lock_dir" "$job_id" "$interpreter" "$script_path" <<'PY'
from datetime import datetime, timezone
import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys

state_root = Path(sys.argv[1])
lock_dir = Path(sys.argv[2])
job_id = sys.argv[3]
interpreter = sys.argv[4]
script_path = sys.argv[5]

lock_file_path = state_root / ".running.flock"
state_path = state_root / "state.json"

lock_fd = os.open(str(lock_file_path), os.O_CREAT | os.O_RDWR, 0o600)
try:
    fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
except BlockingIOError:
    os.close(lock_fd)
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    state_path.write_text(json.dumps({
        "id": job_id,
        "updatedAt": now,
        "lastResult": "coalesced",
        "lastRunAt": now,
    }, ensure_ascii=False) + "\n", encoding="utf-8")
    sys.exit(0)

os.ftruncate(lock_fd, 0)
os.write(lock_fd, f"{os.getpid()}\n".encode("utf-8"))
try:
    lock_dir.mkdir(exist_ok=True)
except OSError:
    pass

def state_signature(path: Path):
    try:
        st = path.stat()
        return (st.st_mtime_ns, st.st_size, path.read_bytes())
    except OSError:
        return None

try:
    before_sig = state_signature(state_path)
    proc = subprocess.run([interpreter, script_path], close_fds=True)
    exit_code = proc.returncode
    after_sig = state_signature(state_path)
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    default_result = "succeeded" if exit_code == 0 else "failed"
    existing = {}
    if state_path.exists():
        try:
            existing = json.loads(state_path.read_text(encoding="utf-8"))
        except Exception:
            existing = {}
    child_updated_state = (
        after_sig is not None
        and after_sig != before_sig
        and existing.get("id") == job_id
        and existing.get("lastResult") not in (None, "coalesced")
    )
    if not child_updated_state:
        state_path.write_text(json.dumps({
            "id": job_id,
            "updatedAt": now,
            "lastResult": default_result,
            "lastRunAt": now,
            "summary": "成功" if exit_code == 0 else f"exit {exit_code}",
            "overviewMd": "运行完成" if exit_code == 0 else f"任务退出码 {exit_code}",
        }, ensure_ascii=False) + "\n", encoding="utf-8")
finally:
    try:
        os.rmdir(lock_dir)
    except OSError:
        pass
    try:
        fcntl.flock(lock_fd, fcntl.LOCK_UN)
    finally:
        os.close(lock_fd)

sys.exit(exit_code)
PY
