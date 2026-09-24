"""TEMPORARY Linux diagnostic (never merged)."""
from __future__ import annotations
import pathlib, subprocess, sys
import pytest
CI_DIR = pathlib.Path(__file__).resolve().parents[1]

@pytest.mark.skipif(sys.platform != "linux", reason="Linux CI diagnostic")
def test_zz_diag() -> None:
    bad = []
    for i in range(300):
        cmd = "exit 3" if i % 2 else "printf ran; exit 0"
        want = "rc=3" if i % 2 else "ranrc=0"
        r = subprocess.run(["/usr/bin/bash", "-e", "-c",
            f'. {CI_DIR}/review-common.sh; rc=0; run_with_timeout 30 /bin/sh -c "{cmd}" || rc=$?; echo "rc=$rc"'],
            capture_output=True, text=True, timeout=60, cwd=CI_DIR)
        if want not in r.stdout.replace("\n", ""):
            bad.append(r.stdout + r.stderr[-300:])
    assert not bad, f"BAD {len(bad)}/300\n" + "\n".join(bad[:10])
