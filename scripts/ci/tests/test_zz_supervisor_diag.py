"""TEMPORARY Linux diagnostic for the intermittent 125 (never merged)."""
from __future__ import annotations

import pathlib
import subprocess
import sys

import pytest

CI_DIR = pathlib.Path(__file__).resolve().parents[1]

DIAG = r'''
import sys, traceback, collections, os
sys.path.insert(0, sys.argv[1])
import review_process_supervisor as m

def pstat(pid):
    try:
        return open(f"/proc/{pid}/stat").read().strip()[:160]
    except Exception as e:
        return repr(e)

class Diag(m.ProcessSupervisor):
    @property
    def supervision_error(self):
        return self.__dict__.get("_se", False)
    @supervision_error.setter
    def supervision_error(self, v):
        if v and not self.__dict__.get("_se"):
            exc = sys.exc_info()[1]
            self.__dict__["_why"] = repr(exc) + " @ " + " <- ".join(
                f"{f.name}:{f.lineno}" for f in traceback.extract_stack(limit=7)[:-1])
        self.__dict__["_se"] = v
    def _cleanup(self, leader_pid=0):
        ok = super()._cleanup(leader_pid)
        if not ok:
            self.__dict__["_cl"] = "cleanup_ok=False ledger=" + "; ".join(
                f"{i} stat={pstat(i.pid)}" for i in self.ledger)
        return ok

reasons = collections.Counter()
N = int(sys.argv[2])
for i in range(N):
    s = Diag(30, ["/bin/sh", "-c", "exit 3"])
    rc = s.run()
    if rc != 3:
        why = s.__dict__.get("_why") or s.__dict__.get("_cl") or "unknown"
        reasons[f"rc={rc} {why}"] += 1
print("RUNS", N, "BAD", sum(reasons.values()))
for k, v in reasons.most_common(15):
    print(v, k)
'''


@pytest.mark.skipif(sys.platform != "linux", reason="Linux CI diagnostic")
def test_zz_supervisor_diag() -> None:
    r = subprocess.run([sys.executable, "-c", DIAG, str(CI_DIR), "300"],
                       capture_output=True, text=True, timeout=200)
    assert "BAD 0" in r.stdout, r.stdout + r.stderr
