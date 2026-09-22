#!/usr/bin/env python3
"""T020 Process Supervisor for Review Gate CLIs.

Supervises one trusted reviewer CLI invocation on macOS and Linux.
Provides capability-scoped and ancestry-proven process tracking, release barrier,
exact deadline management, byte-preserving output relays, TERM->KILL cleanup,
and fail-closed outcomes (124 on timeout, 125 on supervision/cleanup-proof failure).

See specs/006-team-workflow-audit/contracts/t020-process-supervisor.md.
"""

from __future__ import annotations

import ctypes
from ctypes import util
import errno
import math
import os
import secrets
import signal
import sys
import threading
import time
from typing import Any, NamedTuple, Optional, Sequence


REVIEW_TIMEOUT_RC = 124
SUPERVISOR_ERROR_RC = 125
CAPABILITY_ENV_KEY = "_AIDASH_SUPERVISOR_CAPABILITY"


class ProcessIdentity(NamedTuple):
    pid: int
    birth_marker: str


class CandidateInfo(NamedTuple):
    pid: int
    ppid: int
    pgid: int
    birth_marker: str
    is_zombie: bool
    has_capability: bool


class InspectionError(RuntimeError):
    """Raised when process/adapter inspection encounters uncertainty rather than confirmed absence."""
    pass


def parse_birth_marker(marker: str) -> tuple[int, ...]:
    """Parses birth marker into a tuple of validated integers for numeric comparison.

    Returns:
        Tuple of integer components (e.g. (sec, usec) on Darwin, (ticks,) on Linux).

    Raises:
        InspectionError: If marker cannot be parsed into validated integers.
    """
    if not marker:
        raise InspectionError("empty birth marker")
    try:
        parts = marker.split(".")
        return tuple(int(p) for p in parts)
    except (ValueError, TypeError) as e:
        raise InspectionError(f"malformed birth marker '{marker}': {e}") from e


def compare_birth_markers(m1: str, m2: str) -> int:
    """Compares two birth markers numerically in their platform-native integer form.

    Returns:
        < 0 if m1 < m2, 0 if m1 == m2, > 0 if m1 > m2.

    Raises:
        InspectionError: If either birth marker is malformed.
    """
    t1 = parse_birth_marker(m1)
    t2 = parse_birth_marker(m2)
    if t1 < t2:
        return -1
    elif t1 > t2:
        return 1
    return 0


class Clock:
    def monotonic(self) -> float:
        return time.monotonic()

    def sleep(self, seconds: float) -> None:
        time.sleep(seconds)


class ScriptedClock(Clock):
    def __init__(self, start: float = 0.0):
        self._now = start

    def monotonic(self) -> float:
        return self._now

    def advance(self, seconds: float) -> None:
        self._now += seconds

    def sleep(self, seconds: float) -> None:
        self._now += seconds


class BaseMembershipAdapter:
    """Interface for platform process discovery and identity validation."""

    def get_identity(self, pid: int) -> Optional[ProcessIdentity]:
        """Resolves process identity pair (pid, birth_marker) for a living process.

        Returns:
            ProcessIdentity if process exists and is not a zombie, None if definitively absent.

        Raises:
            InspectionError: When inspection encounters non-definitive error (e.g., EIO, EFAULT,
                or permission failure on living process).
        """
        raise NotImplementedError

    def enumerate_candidates(
        self, capability: str, min_birth_marker: Optional[str] = None
    ) -> list[CandidateInfo]:
        """Discovers candidate processes carrying capability or belonging to caller's tree.

        Returns:
            List of CandidateInfo for discovered candidate processes.

        Raises:
            InspectionError: If process table enumeration or candidate capability/identity
                inspection fails or encounters uncertainty on living processes.
        """
        raise NotImplementedError

    def is_alive(self, identity: ProcessIdentity) -> bool:
        """Verifies if the exact process identity (pid, birth_marker) is currently alive.

        Returns:
            True if process with exact birth marker is alive, False if absent or dead.

        Raises:
            InspectionError: If liveness probe encounters an unexpected inspection error.
        """
        raise NotImplementedError

    def is_pgid_alive(self, pgid: int, root_identity: Optional[ProcessIdentity] = None) -> bool:
        """Verifies if any process in the process group is currently alive.

        Returns:
            True if any process in pgid is alive, False if absent or dead.

        Raises:
            InspectionError: If probing the process group encounters an unexpected inspection error.
        """
        raise NotImplementedError

    def signal_identity(self, identity: ProcessIdentity, sig: int) -> bool:
        """Sends a signal to a specific verified process identity.

        Returns:
            True if process was absent/dead or signal succeeded, False if signal failed.

        Raises:
            InspectionError: If signalling encounters an unexpected error on a living target.
        """
        raise NotImplementedError

    def signal_pgid(self, pgid: int, sig: int, root_identity: Optional[ProcessIdentity] = None) -> bool:
        """Sends a signal to the process group when root process identity is verified.

        Returns:
            True if signal was delivered or group already dead, False otherwise.

        Raises:
            InspectionError: If signalling the process group encounters an unexpected error.
        """
        raise NotImplementedError


class DarwinMembershipAdapter(BaseMembershipAdapter):
    PROC_ALL_PIDS = 1
    PROC_PIDT_BSDINFO = 3
    PROC_PIDT_BSHORTINFO = 13

    class proc_bsdshortinfo(ctypes.Structure):
        _fields_ = [
            ("pbsi_pid", ctypes.c_uint32),
            ("pbsi_ppid", ctypes.c_uint32),
            ("pbsi_pgid", ctypes.c_uint32),
            ("pbsi_status", ctypes.c_uint32),
            ("pbsi_comm", ctypes.c_char * 16),
            ("pbsi_flags", ctypes.c_uint32),
            ("pbsi_uid", ctypes.c_uint32),
            ("pbsi_gid", ctypes.c_uint32),
            ("pbsi_ruid", ctypes.c_uint32),
            ("pbsi_rgid", ctypes.c_uint32),
            ("pbsi_svuid", ctypes.c_uint32),
            ("pbsi_svgid", ctypes.c_uint32),
            ("pbsi_reserved", ctypes.c_uint32),
        ]

    class proc_bsdinfo(ctypes.Structure):
        _fields_ = [
            ("pbi_flags", ctypes.c_uint32),
            ("pbi_status", ctypes.c_uint32),
            ("pbi_xstatus", ctypes.c_uint32),
            ("pbi_pid", ctypes.c_uint32),
            ("pbi_ppid", ctypes.c_uint32),
            ("pbi_uid", ctypes.c_uint32),
            ("pbi_gid", ctypes.c_uint32),
            ("pbi_ruid", ctypes.c_uint32),
            ("pbi_rgid", ctypes.c_uint32),
            ("pbi_svuid", ctypes.c_uint32),
            ("pbi_svgid", ctypes.c_uint32),
            ("pbi_reserved", ctypes.c_uint32),
            ("pbi_comm", ctypes.c_char * 16),
            ("pbi_name", ctypes.c_char * 32),
            ("pbi_nfiles", ctypes.c_uint32),
            ("pbi_pgid", ctypes.c_uint32),
            ("pbi_pjobc", ctypes.c_uint32),
            ("e_tdev", ctypes.c_uint32),
            ("e_tpgid", ctypes.c_uint32),
            ("pbi_nice", ctypes.c_int32),
            ("pbi_start_tvsec", ctypes.c_uint64),
            ("pbi_start_tvusec", ctypes.c_uint64),
        ]

    def __init__(self) -> None:
        proc_lib = util.find_library("proc") or util.find_library("libproc") or "libproc.dylib"
        self.libproc = ctypes.CDLL(proc_lib, use_errno=True)
        self.libc = ctypes.CDLL(util.find_library("c"), use_errno=True)
        CTL_KERN = 1
        KERN_ARGMAX = 8
        mib_argmax = (ctypes.c_int * 2)(CTL_KERN, KERN_ARGMAX)
        argmax = ctypes.c_int(0)
        size_argmax = ctypes.c_size_t(ctypes.sizeof(argmax))
        res = self.libc.sysctl(mib_argmax, 2, ctypes.byref(argmax), ctypes.byref(size_argmax), None, 0)
        self.argmax = argmax.value if res == 0 and argmax.value > 0 else 262144
        self._procargs_buf = ctypes.create_string_buffer(self.argmax)

    def _is_other_user_or_zombie(self, pid: int, my_uid: int) -> bool:
        """Determines if a process is definitively owned by another user, is a zombie, or is dead.

        Returns:
            True if provably another user, zombie, or dead; False if indeterminate or same-UID live process.
        """
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return True
        except OSError as e:
            if e.errno in (errno.ESRCH, errno.ENOENT):
                return True
        except PermissionError:
            pass

        # Try proc_bsdshortinfo (succeeds on setuid/root processes that fail BSDINFO)
        sinfo = self.proc_bsdshortinfo()
        ctypes.set_errno(0)
        sz = self.libproc.proc_pidinfo(
            pid, self.PROC_PIDT_BSHORTINFO, 0, ctypes.byref(sinfo), ctypes.sizeof(sinfo)
        )
        if sz == ctypes.sizeof(sinfo):
            if sinfo.pbsi_status == 5:  # SZOMB
                return True
            if int(sinfo.pbsi_uid) != my_uid:  # Effective UID is provably another user
                return True
            return False
        elif sz > 0:
            raise InspectionError(
                f"proc_pidinfo({pid}, BSHORTINFO) returned partial size {sz} != {ctypes.sizeof(sinfo)}"
            )

        return False

    def _get_bsdinfo(self, pid: int) -> Optional[proc_bsdinfo]:
        """Retrieves Darwin bsdinfo structure for a PID.

        Returns:
            proc_bsdinfo structure if successful, None if process is definitively absent.

        Raises:
            InspectionError: If proc_pidinfo fails with non-absence error on a living process
                or returns a partial record.
        """
        if pid <= 0:
            return None
        info = self.proc_bsdinfo()
        ctypes.set_errno(0)
        size = self.libproc.proc_pidinfo(
            pid, self.PROC_PIDT_BSDINFO, 0, ctypes.byref(info), ctypes.sizeof(info)
        )
        if size <= 0:
            err = ctypes.get_errno()
            if err in (errno.ESRCH, errno.ENOENT):
                return None
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                return None
            except OSError as e:
                if e.errno in (errno.ESRCH, errno.ENOENT):
                    return None
            except PermissionError:
                pass
            if self._is_other_user_or_zombie(pid, os.getuid()):
                return None
            raise InspectionError(f"proc_pidinfo({pid}) failed with errno {err} on living candidate")
        elif size != ctypes.sizeof(info):
            raise InspectionError(
                f"proc_pidinfo({pid}, BSDINFO) returned partial size {size} != {ctypes.sizeof(info)}"
            )
        return info

    def get_identity(self, pid: int) -> Optional[ProcessIdentity]:
        """Resolves process identity on Darwin.

        Returns:
            ProcessIdentity if alive, None if absent or zombie.

        Raises:
            InspectionError: If bsdinfo retrieval encounters non-definitive error.
        """
        info = self._get_bsdinfo(pid)
        if not info or info.pbi_status == 5:
            return None
        try:
            sec = int(info.pbi_start_tvsec)
            usec = int(info.pbi_start_tvusec)
        except (ValueError, TypeError) as e:
            raise InspectionError(f"malformed Darwin starttime in bsdinfo for pid {pid}: {e}") from e
        return ProcessIdentity(pid, f"{sec}.{usec:06d}")

    def _has_capability(self, pid: int, cap_bytes: bytes, birth_marker: Optional[str] = None) -> bool:
        """Inspects process environment via sysctl KERN_PROCARGS2 for supervisor capability token.

        Returns:
            True if capability token is found, False if absent or dead.

        Raises:
            InspectionError: If sysctl fails with an unexpected error on a living same-UID candidate.
        """
        CTL_KERN = 1
        KERN_PROCARGS2 = 49
        mib = (ctypes.c_int * 3)(CTL_KERN, KERN_PROCARGS2, pid)
        delays = [0.002, 0.005, 0.01, 0.02, 0.05, 0.1, 0.2, 0.3]
        for attempt, delay in enumerate(delays):
            size = ctypes.c_size_t(self.argmax)
            ctypes.set_errno(0)
            res = self.libc.sysctl(mib, 3, self._procargs_buf, ctypes.byref(size), None, 0)
            if res == 0:
                if size.value == 0:
                    if attempt < len(delays) - 1:
                        time.sleep(delay)
                        continue
                    info2 = self._get_bsdinfo(pid)
                    if not info2 or info2.pbi_status == 5:
                        return False
                    if birth_marker is not None:
                        current_marker = f"{info2.pbi_start_tvsec}.{info2.pbi_start_tvusec:06d}"
                        if current_marker != birth_marker:
                            return False
                    try:
                        os.kill(pid, 0)
                    except ProcessLookupError:
                        return False
                    except OSError as e:
                        if e.errno in (errno.ESRCH, errno.ENOENT):
                            return False
                    except PermissionError:
                        pass
                    if self._is_other_user_or_zombie(pid, os.getuid()):
                        return False
                    raise InspectionError(f"sysctl KERN_PROCARGS2({pid}) returned zero-length buffer for living candidate")
                return cap_bytes in self._procargs_buf.raw[:size.value]
            err = ctypes.get_errno()
            if err in (errno.ESRCH, errno.ENOENT):
                return False
            if err in (errno.EINVAL, errno.EPERM, errno.EACCES, errno.EIO, 14) and attempt < len(delays) - 1:
                time.sleep(delay)
                continue
            info2 = self._get_bsdinfo(pid)
            if not info2 or info2.pbi_status == 5:
                return False
            if birth_marker is not None:
                current_marker = f"{info2.pbi_start_tvsec}.{info2.pbi_start_tvusec:06d}"
                if current_marker != birth_marker:
                    return False
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                return False
            except OSError as e:
                if e.errno in (errno.ESRCH, errno.ENOENT):
                    return False
            except PermissionError:
                pass
            if self._is_other_user_or_zombie(pid, os.getuid()):
                return False
            raise InspectionError(f"sysctl KERN_PROCARGS2({pid}) failed with errno {err} for living candidate")
        return False

    def enumerate_candidates(
        self, capability: str, min_birth_marker: Optional[str] = None
    ) -> list[CandidateInfo]:
        """Enumerates candidate processes on Darwin.

        Returns:
            List of CandidateInfo.

        Raises:
            InspectionError: If proc_listallpids or inspection of a living candidate fails.
        """
        ctypes.set_errno(0)
        count = self.libproc.proc_listallpids(None, 0)
        if count <= 0:
            err = ctypes.get_errno()
            raise InspectionError(f"proc_listallpids count failed with return {count} (errno {err})")
        buf = (ctypes.c_int * (count + 128))()
        ctypes.set_errno(0)
        actual = self.libproc.proc_listallpids(buf, ctypes.sizeof(buf))
        if actual <= 0:
            err = ctypes.get_errno()
            raise InspectionError(f"proc_listallpids failed with return {actual} (errno {err})")
        cap_bytes = f"{CAPABILITY_ENV_KEY}={capability}".encode("utf-8")

        min_sec = 0
        min_usec = 0
        if min_birth_marker:
            try:
                parts = min_birth_marker.split(".")
                min_sec = int(parts[0])
                min_usec = int(parts[1]) if len(parts) > 1 else 0
            except (ValueError, IndexError):
                min_sec = 0
                min_usec = 0

        candidates: list[CandidateInfo] = []
        my_uid = os.getuid()
        for i in range(actual):
            pid = buf[i]
            if pid <= 0 or pid == os.getpid():
                continue
            info = self.proc_bsdinfo()
            ctypes.set_errno(0)
            size = self.libproc.proc_pidinfo(
                pid, self.PROC_PIDT_BSDINFO, 0, ctypes.byref(info), ctypes.sizeof(info)
            )
            if size <= 0:
                err = ctypes.get_errno()
                if err in (errno.ESRCH, errno.ENOENT):
                    continue
                if self._is_other_user_or_zombie(pid, my_uid):
                    continue
                raise InspectionError(f"proc_pidinfo({pid}) failed with errno {err} for living same-UID process")
            elif size != ctypes.sizeof(info):
                raise InspectionError(
                    f"proc_pidinfo({pid}, BSDINFO) returned partial size {size} != {ctypes.sizeof(info)}"
                )
            if int(info.pbi_uid) != my_uid and int(info.pbi_ruid) != my_uid:
                continue

            # Provably unrelated check: born before supervisor launch
            if min_sec > 0:
                cand_sec = int(info.pbi_start_tvsec)
                cand_usec = int(info.pbi_start_tvusec)
                if (cand_sec, cand_usec) < (min_sec, min_usec):
                    continue

            birth_marker = f"{info.pbi_start_tvsec}.{info.pbi_start_tvusec:06d}"
            is_zombie = (info.pbi_status == 5)  # SZOMB
            has_cap = False if is_zombie else self._has_capability(pid, cap_bytes, birth_marker)
            candidates.append(
                CandidateInfo(
                    pid=pid,
                    ppid=int(info.pbi_ppid),
                    pgid=int(info.pbi_pgid),
                    birth_marker=birth_marker,
                    is_zombie=is_zombie,
                    has_capability=has_cap,
                )
            )
        return candidates

    def is_alive(self, identity: ProcessIdentity) -> bool:
        """Checks if process identity is currently alive on Darwin.

        Returns:
            True if alive with matching birth marker, False if dead/reused/zombie.

        Raises:
            InspectionError: If kill or proc_pidinfo fails unexpectedly.
        """
        info = self._get_bsdinfo(identity.pid)
        if not info:
            return False
        current_marker = f"{info.pbi_start_tvsec}.{info.pbi_start_tvusec:06d}"
        if current_marker != identity.birth_marker:
            return False
        if info.pbi_status == 5:  # SZOMB
            return False
        try:
            os.kill(identity.pid, 0)
            return True
        except ProcessLookupError:
            return False
        except PermissionError as e:
            raise InspectionError(f"kill({identity.pid}, 0) permission denied: {e}") from e
        except OSError as e:
            if e.errno in (errno.ESRCH, errno.ENOENT):
                return False
            raise InspectionError(f"kill({identity.pid}, 0) failed: {e}") from e

    def is_pgid_alive(self, pgid: int, root_identity: Optional[ProcessIdentity] = None) -> bool:
        """Checks if process group is alive on Darwin.

        Returns:
            True if any process in pgid is alive, False otherwise.

        Raises:
            InspectionError: If kill probe on pgid encounters an error.
        """
        if pgid <= 0:
            return False
        if root_identity is not None:
            curr_ident = self.get_identity(root_identity.pid)
            if curr_ident != root_identity:
                return False
        try:
            os.kill(-pgid, 0)
            return True
        except ProcessLookupError:
            return False
        except PermissionError as e:
            raise InspectionError(f"kill(-{pgid}, 0) permission denied: {e}") from e
        except OSError as e:
            if e.errno in (errno.ESRCH, errno.ENOENT):
                return False
            raise InspectionError(f"kill(-{pgid}, 0) failed: {e}") from e

    def signal_identity(self, identity: ProcessIdentity, sig: int) -> bool:
        """Signals specific process identity on Darwin.

        Returns:
            True if signal delivered or process already dead.

        Raises:
            InspectionError: If kill fails unexpectedly on a living process.
        """
        if not self.is_alive(identity):
            return True
        try:
            os.kill(identity.pid, sig)
            return True
        except ProcessLookupError:
            return True
        except PermissionError as e:
            raise InspectionError(f"kill({identity.pid}, {sig}) permission denied: {e}") from e
        except OSError as e:
            if e.errno in (errno.ESRCH, errno.ENOENT):
                return True
            raise InspectionError(f"kill({identity.pid}, {sig}) failed: {e}") from e

    def signal_pgid(self, pgid: int, sig: int, root_identity: Optional[ProcessIdentity] = None) -> bool:
        """Signals process group on Darwin.

        Returns:
            True if signal delivered or group already dead.

        Raises:
            InspectionError: If kill fails unexpectedly on process group.
        """
        if pgid <= 0:
            return False
        if root_identity is not None:
            curr_ident = self.get_identity(root_identity.pid)
            if curr_ident != root_identity:
                return False
        try:
            os.kill(-pgid, sig)
            return True
        except ProcessLookupError:
            return True
        except PermissionError as e:
            raise InspectionError(f"kill(-{pgid}, {sig}) permission denied: {e}") from e
        except OSError as e:
            if e.errno in (errno.ESRCH, errno.ENOENT):
                return True
            raise InspectionError(f"kill(-{pgid}, {sig}) failed: {e}") from e


class LinuxMembershipAdapter(BaseMembershipAdapter):
    def get_identity(self, pid: int) -> Optional[ProcessIdentity]:
        """Resolves process identity on Linux via /proc/<pid>/stat.

        Returns:
            ProcessIdentity if alive, None if absent or zombie.

        Raises:
            InspectionError: If reading /proc/<pid>/stat fails with permission, I/O, or malformed data error.
        """
        stat_path = f"/proc/{pid}/stat"
        try:
            with open(stat_path, "r", encoding="utf-8", errors="replace") as f:
                content = f.read()
            close_paren = content.rfind(")")
            if close_paren == -1:
                raise InspectionError(f"malformed stat in {stat_path}")
            fields = content[close_paren + 1:].split()
            if len(fields) < 20:
                raise InspectionError(f"insufficient fields in {stat_path}")
            if fields[0] == "Z":
                return None
            starttime_raw = fields[19]
            try:
                starttime_int = int(starttime_raw)
            except (ValueError, TypeError) as e:
                raise InspectionError(f"malformed starttime '{starttime_raw}' in {stat_path}: {e}") from e
            return ProcessIdentity(pid, str(starttime_int))
        except (FileNotFoundError, ProcessLookupError):
            return None
        except PermissionError as e:
            raise InspectionError(f"permission denied reading {stat_path}: {e}") from e
        except OSError as e:
            if e.errno in (errno.ESRCH, errno.ENOENT):
                return None
            raise InspectionError(f"failed reading {stat_path}: {e}") from e

    def enumerate_candidates(
        self, capability: str, min_birth_marker: Optional[str] = None
    ) -> list[CandidateInfo]:
        """Enumerates candidate processes on Linux.

        Returns:
            List of CandidateInfo.

        Raises:
            InspectionError: If /proc enumeration or inspecting a living same-UID candidate fails.
        """
        candidates: list[CandidateInfo] = []
        cap_bytes = f"{CAPABILITY_ENV_KEY}={capability}".encode("utf-8")
        try:
            entries = os.listdir("/proc")
        except OSError as e:
            raise InspectionError(f"failed to enumerate /proc: {e}") from e

        min_ticks = 0
        if min_birth_marker:
            try:
                min_ticks = int(min_birth_marker)
            except (ValueError, TypeError):
                min_ticks = 0

        my_uid = os.getuid()
        for entry in entries:
            if not entry.isdigit():
                continue
            pid = int(entry)
            try:
                st = os.stat(f"/proc/{pid}")
            except (FileNotFoundError, ProcessLookupError):
                continue
            except PermissionError:
                # Permission denied on /proc/<pid> stat - check if process is dead
                try:
                    os.kill(pid, 0)
                except ProcessLookupError:
                    continue
                except OSError as e:
                    if e.errno in (errno.ESRCH, errno.ENOENT):
                        continue
                # EPERM from kill does not prove UID mismatch; without definitive UID evidence from stat, fail closed
                raise InspectionError(f"permission denied on /proc/{pid} without definitive UID proof")
            except OSError as e:
                if e.errno in (errno.ESRCH, errno.ENOENT):
                    continue
                raise InspectionError(f"failed to stat /proc/{pid}: {e}") from e

            if st.st_uid != my_uid:
                continue

            try:
                with open(f"/proc/{pid}/stat", "r", encoding="utf-8", errors="replace") as f:
                    content = f.read()
                close_paren = content.rfind(")")
                if close_paren == -1:
                    raise InspectionError(f"malformed /proc/{pid}/stat for living same-UID process")
                fields = content[close_paren + 1:].split()
                if len(fields) < 20:
                    raise InspectionError(f"insufficient fields in /proc/{pid}/stat for living process")
                state = fields[0]
                ppid = int(fields[1])
                pgid = int(fields[2])
                birth_marker_raw = fields[19]
                try:
                    cand_ticks = int(birth_marker_raw)
                except (ValueError, TypeError) as e:
                    raise InspectionError(f"malformed starttime '{birth_marker_raw}' in /proc/{pid}/stat: {e}") from e
                birth_marker = str(cand_ticks)
                is_zombie = (state == "Z")

                if min_ticks > 0 and cand_ticks < min_ticks:
                    continue

                has_cap = False
                try:
                    with open(f"/proc/{pid}/environ", "rb") as ef:
                        env_data = ef.read()
                    has_cap = cap_bytes in env_data
                except (FileNotFoundError, ProcessLookupError):
                    has_cap = False
                except PermissionError as e:
                    raise InspectionError(f"permission denied reading /proc/{pid}/environ for same-UID process: {e}") from e
                except OSError as e:
                    if e.errno in (errno.ESRCH, errno.ENOENT):
                        has_cap = False
                    else:
                        raise InspectionError(f"failed reading /proc/{pid}/environ: {e}") from e

                candidates.append(
                    CandidateInfo(
                        pid=pid,
                        ppid=ppid,
                        pgid=pgid,
                        birth_marker=birth_marker,
                        is_zombie=is_zombie,
                        has_capability=has_cap,
                    )
                )
            except (IndexError, ValueError) as e:
                raise InspectionError(f"malformed /proc/{pid}/stat contents: {e}") from e
            except (FileNotFoundError, ProcessLookupError):
                continue
            except PermissionError as e:
                raise InspectionError(f"permission denied inspecting /proc/{pid} for same-UID process: {e}") from e
            except OSError as e:
                if e.errno in (errno.ESRCH, errno.ENOENT):
                    continue
                raise InspectionError(f"failed inspecting /proc/{pid}: {e}") from e
        return candidates

    def is_alive(self, identity: ProcessIdentity) -> bool:
        """Checks if process identity is currently alive on Linux.

        Returns:
            True if alive with matching birth marker, False if dead/reused/zombie.

        Raises:
            InspectionError: If stat reading or kill probe fails unexpectedly.
        """
        current = self.get_identity(identity.pid)
        if current is None:
            return False
        if current != identity:
            return False
        try:
            with open(f"/proc/{identity.pid}/stat", "r", encoding="utf-8", errors="replace") as f:
                content = f.read()
            close_paren = content.rfind(")")
            if close_paren != -1:
                fields = content[close_paren + 1:].split()
                if len(fields) > 0 and fields[0] == "Z":
                    return False
            os.kill(identity.pid, 0)
            return True
        except (FileNotFoundError, ProcessLookupError):
            return False
        except PermissionError as e:
            raise InspectionError(f"is_alive({identity.pid}) permission denied: {e}") from e
        except OSError as e:
            if e.errno in (errno.ESRCH, errno.ENOENT):
                return False
            raise InspectionError(f"is_alive({identity.pid}) failed: {e}") from e

    def is_pgid_alive(self, pgid: int, root_identity: Optional[ProcessIdentity] = None) -> bool:
        """Checks if process group is alive on Linux.

        Returns:
            True if any process in pgid is alive, False otherwise.

        Raises:
            InspectionError: If kill probe on pgid encounters an error.
        """
        if pgid <= 0:
            return False
        if root_identity is not None:
            curr_ident = self.get_identity(root_identity.pid)
            if curr_ident != root_identity:
                return False
        try:
            os.kill(-pgid, 0)
            return True
        except ProcessLookupError:
            return False
        except PermissionError as e:
            raise InspectionError(f"kill(-{pgid}, 0) permission denied: {e}") from e
        except OSError as e:
            if e.errno in (errno.ESRCH, errno.ENOENT):
                return False
            raise InspectionError(f"kill(-{pgid}, 0) failed: {e}") from e

    def signal_identity(self, identity: ProcessIdentity, sig: int) -> bool:
        """Signals specific process identity on Linux using atomic pidfd.

        Returns:
            True if signal delivered or process already dead.

        Raises:
            InspectionError: If pidfd signaling is unavailable or fails unexpectedly on a living process.
        """
        if not (hasattr(os, "pidfd_open") and hasattr(signal, "pidfd_send_signal")):
            raise InspectionError("Linux atomic pidfd signaling is unavailable")

        try:
            fd = os.pidfd_open(identity.pid, 0)
        except ProcessLookupError:
            return True
        except OSError as e:
            if e.errno in (errno.ESRCH, errno.ENOENT):
                return True
            raise InspectionError(f"pidfd_open({identity.pid}) failed: {e}") from e
        try:
            current = self.get_identity(identity.pid)
            if current != identity:
                return True
            signal.pidfd_send_signal(fd, sig)
            return True
        except ProcessLookupError:
            return True
        except PermissionError as e:
            raise InspectionError(f"pidfd_send_signal({identity.pid}, {sig}) permission denied: {e}") from e
        except OSError as e:
            if e.errno in (errno.ESRCH, errno.ENOENT):
                return True
            raise InspectionError(f"pidfd_send_signal({identity.pid}, {sig}) failed: {e}") from e
        finally:
            try:
                os.close(fd)
            except OSError:
                pass

    def signal_pgid(self, pgid: int, sig: int, root_identity: Optional[ProcessIdentity] = None) -> bool:
        """Signals process group on Linux.

        Returns:
            True if signal delivered or group already dead.

        Raises:
            InspectionError: If kill fails unexpectedly on process group.
        """
        if pgid <= 0:
            return False
        if root_identity is not None:
            curr_ident = self.get_identity(root_identity.pid)
            if curr_ident != root_identity:
                return False
        try:
            os.kill(-pgid, sig)
            return True
        except ProcessLookupError:
            return True
        except PermissionError as e:
            raise InspectionError(f"signal_pgid(-{pgid}, {sig}) permission denied: {e}") from e
        except OSError as e:
            if e.errno in (errno.ESRCH, errno.ENOENT):
                return True
            raise InspectionError(f"signal_pgid(-{pgid}, {sig}) failed: {e}") from e


class ScriptedAdapter(BaseMembershipAdapter):
    """Deterministic in-memory adapter for contract and state machine verification."""

    def __init__(self) -> None:
        self.identities: dict[int, ProcessIdentity] = {}
        self.processes: dict[int, CandidateInfo] = {}
        self.alive: set[int] = set()
        self.term_resistant: set[int] = set()
        self.pgids: dict[int, set[int]] = {}
        self.signal_log: list[tuple[str, int, int]] = []
        self.signal_hooks: list[tuple[int, int, Any]] = []
        self.fail_membership = False
        self.fail_cleanup_proof = False
        self.fail_signalling = False
        self.fail_inspection_pids: set[int] = set()
        self.fail_capability_pids: set[int] = set()
        self.fail_candidate_discovery = False

    def register_process(
        self,
        pid: int,
        ppid: int,
        pgid: int,
        birth_marker: str,
        has_capability: bool = False,
        is_zombie: bool = False,
        term_resistant: bool = False,
    ) -> ProcessIdentity:
        """Registers a simulated process in the in-memory adapter state.

        Returns:
            The created ProcessIdentity instance.
        """
        ident = ProcessIdentity(pid, birth_marker)
        self.identities[pid] = ident
        self.processes[pid] = CandidateInfo(
            pid=pid,
            ppid=ppid,
            pgid=pgid,
            birth_marker=birth_marker,
            is_zombie=is_zombie,
            has_capability=has_capability,
        )
        if not is_zombie:
            self.alive.add(pid)
        if term_resistant:
            self.term_resistant.add(pid)
        self.pgids.setdefault(pgid, set()).add(pid)
        return ident

    def get_identity(self, pid: int) -> Optional[ProcessIdentity]:
        """Resolves process identity pair (pid, birth_marker) for a living process.

        Returns:
            ProcessIdentity if process exists in adapter state, None if absent.

        Raises:
            InspectionError: If pid is marked in fail_inspection_pids.
        """
        if pid in self.fail_inspection_pids:
            raise InspectionError(f"Scripted get_identity failure for PID {pid}")
        return self.identities.get(pid)

    def enumerate_candidates(
        self, capability: str, min_birth_marker: Optional[str] = None
    ) -> list[CandidateInfo]:
        """Enumerates registered candidate processes.

        Returns:
            List of CandidateInfo structures for all registered processes.

        Raises:
            InspectionError: If fail_membership, fail_candidate_discovery, or any candidate in fail_capability_pids.
        """
        if self.fail_membership or self.fail_candidate_discovery:
            raise InspectionError("Scripted candidate discovery failure")
        for cand in self.processes.values():
            if cand.pid in self.fail_capability_pids:
                raise InspectionError(f"Scripted capability inspection failure for candidate PID {cand.pid}")
        return list(self.processes.values())

    def is_alive(self, identity: ProcessIdentity) -> bool:
        """Checks if process identity is living.

        Returns:
            True if process is alive or fail_cleanup_proof is set, False otherwise.

        Raises:
            InspectionError: If identity.pid is marked in fail_inspection_pids.
        """
        if identity.pid in self.fail_inspection_pids:
            raise InspectionError(f"Scripted inspection failure for PID {identity.pid}")
        if self.fail_cleanup_proof:
            return True
        curr = self.identities.get(identity.pid)
        return (curr == identity) and (identity.pid in self.alive)

    def is_pgid_alive(self, pgid: int, root_identity: Optional[ProcessIdentity] = None) -> bool:
        """Checks if any process in pgid is alive.

        Returns:
            True if any process in pgid is alive, False if absent or dead.

        Raises:
            InspectionError: If root_identity inspection raises InspectionError.
        """
        if pgid <= 0:
            return False
        if root_identity is not None:
            curr_ident = self.get_identity(root_identity.pid)
            if curr_ident != root_identity:
                return False
        pids = self.pgids.get(pgid, set())
        return any(pid in self.alive for pid in pids)

    def signal_identity(self, identity: ProcessIdentity, sig: int) -> bool:
        """Sends signal to simulated process identity.

        Returns:
            True if signal delivered, False if process dead or fail_signalling is set.

        Raises:
            InspectionError: If identity.pid is marked in fail_inspection_pids.
        """
        self.signal_log.append(("pid", identity.pid, sig))
        if identity.pid in self.fail_inspection_pids:
            raise InspectionError(f"Scripted signalling failure for PID {identity.pid}")
        if self.fail_signalling:
            return False
        if not self.is_alive(identity):
            return False
        for target_pid, target_sig, hook in list(self.signal_hooks):
            if target_pid == identity.pid and target_sig == sig:
                hook()
        if sig == signal.SIGTERM:
            if identity.pid not in self.term_resistant:
                self.alive.discard(identity.pid)
        elif sig == signal.SIGKILL:
            self.alive.discard(identity.pid)
        return True

    def signal_pgid(self, pgid: int, sig: int, root_identity: Optional[ProcessIdentity] = None) -> bool:
        """Sends signal to simulated process group.

        Returns:
            True if signal delivered, False if pgid invalid or fail_signalling is set.

        Raises:
            InspectionError: If root_identity inspection raises InspectionError.
        """
        if pgid <= 0:
            return False
        if root_identity is not None:
            curr_ident = self.get_identity(root_identity.pid)
            if curr_ident != root_identity:
                return False
        self.signal_log.append(("pgid", pgid, sig))
        if self.fail_signalling:
            return False
        pids = list(self.pgids.get(pgid, set()))
        for pid in pids:
            if pid in self.alive:
                for target_pid, target_sig, hook in list(self.signal_hooks):
                    if target_pid == pid and target_sig == sig:
                        hook()
                if sig == signal.SIGTERM:
                    if pid not in self.term_resistant:
                        self.alive.discard(pid)
                elif sig == signal.SIGKILL:
                    self.alive.discard(pid)
        return True


def get_default_adapter() -> BaseMembershipAdapter:
    if sys.platform == "darwin":
        return DarwinMembershipAdapter()
    return LinuxMembershipAdapter()


class ProcessSupervisor:
    """State machine governing launch, release barrier, monitoring, relays, and cleanup."""

    def __init__(
        self,
        timeout_seconds: float,
        command: Sequence[str],
        adapter: Optional[BaseMembershipAdapter] = None,
        clock: Optional[Clock] = None,
        wait_event_fn: Optional[Any] = None,
    ) -> None:
        t_val = float(timeout_seconds)
        if not math.isfinite(t_val) or t_val <= 0:
            raise ValueError("timeout_seconds must be a positive finite number")
        self.timeout_seconds = t_val
        self.command = list(command)
        self.adapter = adapter or get_default_adapter()
        self.clock = clock or Clock()
        self.wait_event_fn = wait_event_fn
        self.capability = secrets.token_hex(16)
        self.ledger: dict[ProcessIdentity, ProcessIdentity] = {}
        self.root_identity: Optional[ProcessIdentity] = None
        self.root_pgid: int = 0
        self.deadline: float = 0.0
        self.start_time: float = 0.0
        self.observed_events: list[tuple[int, float]] = []
        self.terminal_reaped: bool = False
        self.supervision_error: bool = False
        self._in_drain: bool = False

    def _drain_wait_events(self, pid: int, wait_flags: int) -> None:
        """Atomically drains all available wait events for pid into observed_events,
        recording an exact observation timestamp per reaped status."""
        if self._in_drain:
            return
        self._in_drain = True
        try:
            while True:
                try:
                    wpid, st = os.waitpid(pid, wait_flags)
                    if wpid == pid:
                        ts = self.clock.monotonic()
                        self.observed_events.append((st, ts))
                        if os.WIFEXITED(st) or os.WIFSIGNALED(st):
                            self.terminal_reaped = True
                            break
                    elif wpid == 0:
                        break
                    else:
                        break
                except ChildProcessError:
                    if not self.terminal_reaped and not any(os.WIFEXITED(st) or os.WIFSIGNALED(st) for st, _ in self.observed_events):
                        self.supervision_error = True
                    break
                except (BlockingIOError, InterruptedError):
                    continue
                except OSError as e:
                    if e.errno in (errno.ECHILD, errno.ESRCH):
                        if not self.terminal_reaped and not any(os.WIFEXITED(st) or os.WIFSIGNALED(st) for st, _ in self.observed_events):
                            self.supervision_error = True
                        break
                    self.supervision_error = True
                    break
                except Exception:
                    self.supervision_error = True
                    break
        finally:
            self._in_drain = False

    def _poll_leader(self, pid: int, flags: int) -> tuple[int, int, float]:
        """Polls leader process status, returning (waited_pid, status, observation_time).

        Returns:
            Tuple of (waited_pid, status, observation_timestamp).

        Raises:
            ChildProcessError: If leader process is no longer a child of supervisor.
        """
        if self.wait_event_fn is not None:
            wpid, st, t = self.wait_event_fn(pid, flags)
            if wpid == pid and (os.WIFEXITED(st) or os.WIFSIGNALED(st)):
                self.terminal_reaped = True
            return wpid, st, t
        if not self.observed_events:
            self._drain_wait_events(pid, flags)
        if self.observed_events:
            status, event_time = self.observed_events.pop(0)
            return pid, status, event_time
        return 0, 0, self.clock.monotonic()

    def _refresh_ledger(self) -> None:
        try:
            min_birth = self.root_identity.birth_marker if self.root_identity is not None else None
            candidates = self.adapter.enumerate_candidates(self.capability, min_birth_marker=min_birth)
        except Exception:
            self.supervision_error = True
            return

        progress = True
        while progress:
            progress = False
            for cand in candidates:
                cand_ident = ProcessIdentity(cand.pid, cand.birth_marker)
                if cand_ident in self.ledger:
                    continue

                # Check if there is an existing stale entry for the same PID
                existing_for_pid = [ident for ident in self.ledger.keys() if ident.pid == cand.pid]
                if existing_for_pid:
                    stale_ident = existing_for_pid[0]
                    if cand.birth_marker == stale_ident.birth_marker:
                        continue
                    # Candidate is a newer process reusing this PID.
                    # Retire stale entry only if it is dead/absent.
                    try:
                        if self.adapter.is_alive(stale_ident):
                            continue
                    except Exception:
                        self.supervision_error = True
                        continue

                # Admittance proof 1: carries target capability
                # Admittance proof 2: exact parent identity is verified in ledger
                # Admittance proof 3: verified member of still-owned root PGID born after launch
                admitted = False
                if cand.has_capability:
                    admitted = True
                else:
                    # Check parent identity in ledger
                    matching_parents = [ident for ident in self.ledger.keys() if ident.pid == cand.ppid]
                    if matching_parents:
                        expected_parent = matching_parents[0]
                        try:
                            current_parent = self.adapter.get_identity(cand.ppid)
                            if (
                                current_parent == expected_parent
                                and compare_birth_markers(cand.birth_marker, expected_parent.birth_marker) >= 0
                            ):
                                admitted = True
                        except Exception:
                            self.supervision_error = True

                    if (
                        not admitted
                        and self.root_identity is not None
                        and cand.pgid == self.root_pgid
                        and cand.pgid > 0
                        and compare_birth_markers(cand.birth_marker, self.root_identity.birth_marker) >= 0
                    ):
                        try:
                            curr_root = self.adapter.get_identity(self.root_identity.pid)
                            if curr_root == self.root_identity:
                                admitted = True
                        except Exception:
                            self.supervision_error = True

                if admitted:
                    # If this PID previously had a dead entry in ledger, retire it
                    if existing_for_pid:
                        for stale in existing_for_pid:
                            self.ledger.pop(stale, None)
                    self.ledger[cand_ident] = cand_ident
                    progress = True

    def classify_outcome(
        self,
        leader_completion_time: Optional[float],
        child_status: Optional[int],
        timed_out: bool,
        cleanup_ok: bool,
    ) -> int:
        """Classifies execution outcome into process status, 124 (timeout), or 125 (error)."""
        if self.supervision_error or not cleanup_ok:
            return SUPERVISOR_ERROR_RC

        if timed_out:
            return REVIEW_TIMEOUT_RC

        if (
            self.deadline > 0.0
            and leader_completion_time is not None
            and leader_completion_time > self.deadline
        ):
            return REVIEW_TIMEOUT_RC

        if child_status is not None:
            return child_status

        return SUPERVISOR_ERROR_RC

    def _cleanup(self, leader_pid: int = 0) -> bool:
        """Executes bounded TERM->KILL cleanup across all ledger members and root PGID."""
        try:
            self._refresh_ledger()
        except Exception:
            self.supervision_error = True

        # 1. Initial grace phase signal
        if self.root_pgid > 0 and self.root_identity is not None:
            try:
                if self.adapter.is_pgid_alive(self.root_pgid, self.root_identity):
                    if not self.adapter.signal_pgid(self.root_pgid, signal.SIGTERM, self.root_identity):
                        self.supervision_error = True
            except Exception:
                self.supervision_error = True

        for ident in list(self.ledger.values()):
            try:
                if self.adapter.is_alive(ident):
                    if not self.adapter.signal_identity(ident, signal.SIGTERM):
                        self.supervision_error = True
            except Exception:
                self.supervision_error = True

        # 2. Bounded grace period
        grace_steps = 20
        all_dead = False
        for _ in range(grace_steps):
            try:
                self._refresh_ledger()
            except Exception:
                self.supervision_error = True

            for ident in list(self.ledger.values()):
                try:
                    if self.adapter.is_alive(ident):
                        if not self.adapter.signal_identity(ident, signal.SIGTERM):
                            self.supervision_error = True
                except Exception:
                    self.supervision_error = True

            still_alive = False
            for i in list(self.ledger.values()):
                try:
                    if self.adapter.is_alive(i):
                        still_alive = True
                except Exception:
                    self.supervision_error = True
                    still_alive = True

            root_pgid_alive = False
            if self.root_pgid > 0 and self.root_identity is not None:
                try:
                    root_pgid_alive = self.adapter.is_pgid_alive(self.root_pgid, self.root_identity)
                except Exception:
                    self.supervision_error = True
                    root_pgid_alive = True

            if not still_alive and not root_pgid_alive:
                all_dead = True
                break
            self.clock.sleep(0.05)

        # 3. KILL phase across group and ledger
        if not all_dead:
            if self.root_pgid > 0 and self.root_identity is not None:
                try:
                    if self.adapter.is_pgid_alive(self.root_pgid, self.root_identity):
                        if not self.adapter.signal_pgid(self.root_pgid, signal.SIGKILL, self.root_identity):
                            self.supervision_error = True
                except Exception:
                    self.supervision_error = True

            for ident in list(self.ledger.values()):
                try:
                    if self.adapter.is_alive(ident):
                        if not self.adapter.signal_identity(ident, signal.SIGKILL):
                            self.supervision_error = True
                except Exception:
                    self.supervision_error = True
            self.clock.sleep(0.05)

        # 4. Post-KILL bounded discovery & KILL loop until quiescent
        for _ in range(10):
            try:
                self._refresh_ledger()
            except Exception:
                self.supervision_error = True

            new_live = []
            for i in list(self.ledger.values()):
                try:
                    if self.adapter.is_alive(i):
                        new_live.append(i)
                except Exception:
                    self.supervision_error = True
                    new_live.append(i)

            if not new_live:
                break

            for ident in new_live:
                try:
                    if not self.adapter.signal_identity(ident, signal.SIGKILL):
                        self.supervision_error = True
                except Exception:
                    self.supervision_error = True
            self.clock.sleep(0.05)

        # 5. Authoritative bounded reap for leader
        if leader_pid > 0:
            reaped = False
            for _ in range(20):
                try:
                    wpid, _ = os.waitpid(leader_pid, os.WNOHANG)
                    if wpid == leader_pid:
                        reaped = True
                        break
                except ChildProcessError:
                    reaped = True
                    break
                except OSError as e:
                    if e.errno in (errno.ECHILD, errno.ESRCH):
                        reaped = True
                        break
                self.clock.sleep(0.01)
            if not reaped:
                # If leader was already reaped by main loop or absent
                try:
                    os.kill(leader_pid, 0)
                except ProcessLookupError:
                    reaped = True
                except Exception:
                    pass
            if not reaped:
                self.supervision_error = True

        # 6. Final quiescence verification across all ledger members and root PGID
        try:
            self._refresh_ledger()
        except Exception:
            self.supervision_error = True

        for ident in list(self.ledger.values()):
            try:
                if self.adapter.is_alive(ident):
                    return False
            except Exception:
                self.supervision_error = True
                return False

        if self.root_pgid > 0 and self.root_identity is not None:
            try:
                if self.adapter.is_pgid_alive(self.root_pgid, self.root_identity):
                    return False
            except Exception:
                self.supervision_error = True
                return False

        if self.supervision_error:
            return False

        return True

    def run(self) -> int:
        """Runs the command behind the barrier and manages timeout/exit lifecycle."""
        if not self.command:
            return SUPERVISOR_ERROR_RC

        barrier_r, barrier_w = -1, -1
        ready_r, ready_w = -1, -1
        stdout_r, stdout_w = -1, -1
        stderr_r, stderr_w = -1, -1
        orig_sigchld = None
        pid = -1
        t_stdout, t_stderr = None, None
        stdout_info: dict = {"eof": False, "error": None}
        stderr_info: dict = {"eof": False, "error": None}
        cleaned_up = False
        leader_completion_time: Optional[float] = None
        child_status: Optional[int] = None
        timed_out = False
        cleanup_ok = False

        try:
            try:
                barrier_r, barrier_w = os.pipe()
                ready_r, ready_w = os.pipe()
                stdout_r, stdout_w = os.pipe()
                stderr_r, stderr_w = os.pipe()
            except OSError:
                return SUPERVISOR_ERROR_RC

            env = os.environ.copy()
            env[CAPABILITY_ENV_KEY] = self.capability

            try:
                pid = os.fork()
            except OSError:
                return SUPERVISOR_ERROR_RC

            if pid == 0:
                # Child process
                try:
                    os.close(barrier_w)
                    os.close(ready_r)
                    os.close(stdout_r)
                    os.close(stderr_r)

                    os.dup2(stdout_w, 1)
                    os.dup2(stderr_w, 2)
                    os.close(stdout_w)
                    os.close(stderr_w)

                    os.setsid()

                    # Signal readiness to supervisor
                    os.write(ready_w, b"R")
                    os.close(ready_w)

                    # Wait on barrier release - must be exact token b"GO"
                    data = b""
                    while len(data) < 2:
                        chunk = os.read(barrier_r, 2 - len(data))
                        if not chunk:
                            break
                        data += chunk
                    os.close(barrier_r)

                    if data != b"GO":
                        os._exit(SUPERVISOR_ERROR_RC)

                    os.execvpe(self.command[0], self.command, env)
                except Exception:
                    os._exit(SUPERVISOR_ERROR_RC)

            # Supervisor process
            os.close(barrier_r)
            barrier_r = -1
            os.close(ready_w)
            ready_w = -1
            os.close(stdout_w)
            stdout_w = -1
            os.close(stderr_w)
            stderr_w = -1

            def relay_worker(pipe_r: int, dest_fd: int, info: dict):
                try:
                    while True:
                        try:
                            chunk = os.read(pipe_r, 65536)
                        except (BlockingIOError, InterruptedError):
                            continue
                        except OSError as e:
                            if e.errno in (errno.EBADF, errno.EIO):
                                info["eof"] = True
                                break
                            info["error"] = e
                            break
                        if not chunk:
                            info["eof"] = True
                            break
                        total_written = 0
                        while total_written < len(chunk):
                            try:
                                n = os.write(dest_fd, chunk[total_written:])
                                if n <= 0:
                                    info["error"] = True
                                    break
                                total_written += n
                            except (BlockingIOError, InterruptedError):
                                continue
                            except Exception:
                                info["error"] = True
                                break
                        if info.get("error"):
                            break
                except Exception as e:
                    info["error"] = e
                finally:
                    try:
                        os.close(pipe_r)
                    except OSError:
                        pass

            t_stdout = threading.Thread(
                target=relay_worker, args=(stdout_r, 1, stdout_info), daemon=True
            )
            t_stderr = threading.Thread(
                target=relay_worker, args=(stderr_r, 2, stderr_info), daemon=True
            )
            t_stdout.start()
            t_stderr.start()
            stdout_r = -1
            stderr_r = -1

            # Main supervision loop
            poll_count = 0
            wait_flags = os.WNOHANG | os.WUNTRACED
            if hasattr(os, "WCONTINUED"):
                wait_flags |= os.WCONTINUED

            def _on_sigchld(signum, frame):
                self._drain_wait_events(pid, wait_flags)

            try:
                orig_sigchld = signal.signal(signal.SIGCHLD, _on_sigchld)
            except (ValueError, OSError):
                self.supervision_error = True

            # Wait for child readiness behind barrier
            ready_token = b""
            try:
                ready_token = os.read(ready_r, 1)
                os.close(ready_r)
                ready_r = -1
            except OSError:
                self.supervision_error = True

            if ready_token != b"R":
                self.supervision_error = True
                if barrier_w >= 0:
                    try:
                        os.close(barrier_w)
                    except OSError:
                        pass
                    barrier_w = -1
                cleanup_ok = self._cleanup(leader_pid=pid)
                cleaned_up = True
                return SUPERVISOR_ERROR_RC

            root_ident = self.adapter.get_identity(pid)
            if not root_ident:
                self.supervision_error = True
                if barrier_w >= 0:
                    try:
                        os.close(barrier_w)
                    except OSError:
                        pass
                    barrier_w = -1
                cleanup_ok = self._cleanup(leader_pid=pid)
                cleaned_up = True
                if t_stdout and t_stdout.is_alive():
                    t_stdout.join(timeout=1.0)
                if t_stderr and t_stderr.is_alive():
                    t_stderr.join(timeout=1.0)
                return SUPERVISOR_ERROR_RC

            self.root_identity = root_ident
            self.root_pgid = pid
            self.ledger[root_ident] = root_ident

            # Set monotonic deadline immediately before releasing barrier
            self.start_time = self.clock.monotonic()
            self.deadline = self.start_time + self.timeout_seconds

            # Release target with exact token b"GO"
            try:
                os.write(barrier_w, b"GO")
                os.close(barrier_w)
                barrier_w = -1
            except OSError:
                self.supervision_error = True
                cleanup_ok = self._cleanup(leader_pid=pid)
                cleaned_up = True
                return SUPERVISOR_ERROR_RC

            # Main supervision loop
            poll_count = 0
            last_ledger_refresh = 0.0
            while True:
                now = self.clock.monotonic()
                if poll_count == 0 or (now - last_ledger_refresh) >= 0.05:
                    self._refresh_ledger()
                    last_ledger_refresh = now

                try:
                    waited_pid, status, event_time = self._poll_leader(pid, wait_flags)
                    if waited_pid == pid:
                        if os.WIFSTOPPED(status):
                            pass
                        elif hasattr(os, "WIFCONTINUED") and os.WIFCONTINUED(status):
                            pass
                        elif os.WIFEXITED(status):
                            leader_completion_time = event_time
                            child_status = os.WEXITSTATUS(status)
                            break
                        elif os.WIFSIGNALED(status):
                            leader_completion_time = event_time
                            child_status = 128 + os.WTERMSIG(status)
                            break
                except ChildProcessError:
                    if child_status is None:
                        while self.observed_events:
                            status, event_time = self.observed_events.pop(0)
                            if os.WIFSTOPPED(status):
                                pass
                            elif hasattr(os, "WIFCONTINUED") and os.WIFCONTINUED(status):
                                pass
                            elif os.WIFEXITED(status):
                                leader_completion_time = event_time
                                child_status = os.WEXITSTATUS(status)
                                break
                            elif os.WIFSIGNALED(status):
                                leader_completion_time = event_time
                                child_status = 128 + os.WTERMSIG(status)
                                break
                        if child_status is None:
                            leader_completion_time = self.clock.monotonic()
                            self.supervision_error = True
                    break

                if self.supervision_error:
                    break

                now = self.clock.monotonic()
                if now > self.deadline:
                    self._drain_wait_events(pid, wait_flags)
                    while self.observed_events:
                        status, event_time = self.observed_events.pop(0)
                        if os.WIFEXITED(status):
                            leader_completion_time = event_time
                            child_status = os.WEXITSTATUS(status)
                            break
                        elif os.WIFSIGNALED(status):
                            leader_completion_time = event_time
                            child_status = 128 + os.WTERMSIG(status)
                            break
                    if child_status is None:
                        timed_out = True
                        break
                    else:
                        if leader_completion_time is not None and leader_completion_time > self.deadline:
                            timed_out = True
                        break

                poll_count += 1
                if poll_count < 30:
                    self.clock.sleep(0.0005)
                else:
                    self.clock.sleep(0.002)

            # Cleanup phase
            cleanup_ok = self._cleanup(leader_pid=pid)
            cleaned_up = True

            # Drain output relays to EOF
            if t_stdout:
                t_stdout.join(timeout=5.0)
            if t_stderr:
                t_stderr.join(timeout=5.0)

            if not stdout_info.get("eof") or not stderr_info.get("eof") or stdout_info.get("error") or stderr_info.get("error"):
                self.supervision_error = True

            return self.classify_outcome(
                leader_completion_time=leader_completion_time,
                child_status=child_status,
                timed_out=timed_out,
                cleanup_ok=cleanup_ok,
            )
        finally:
            if pid > 0 and not cleaned_up:
                try:
                    self._cleanup(leader_pid=pid)
                except Exception:
                    pass
            for fd in [barrier_r, barrier_w, ready_r, ready_w, stdout_r, stdout_w, stderr_r, stderr_w]:
                if fd >= 0:
                    try:
                        os.close(fd)
                    except OSError:
                        pass
            if t_stdout and t_stdout.is_alive():
                t_stdout.join(timeout=1.0)
            if t_stderr and t_stderr.is_alive():
                t_stderr.join(timeout=1.0)
            if orig_sigchld is not None:
                try:
                    signal.signal(signal.SIGCHLD, orig_sigchld)
                except (ValueError, OSError):
                    pass


def main() -> int:
    if len(sys.argv) < 3 or sys.argv[1] != "run":
        sys.stderr.write("Usage: review_process_supervisor.py run <timeout_seconds> <command...>\n")
        return SUPERVISOR_ERROR_RC

    try:
        timeout_sec = float(sys.argv[2])
        if not math.isfinite(timeout_sec) or timeout_sec <= 0:
            sys.stderr.write("Error: timeout_seconds must be positive and finite\n")
            return SUPERVISOR_ERROR_RC
    except ValueError:
        sys.stderr.write("Error: invalid timeout_seconds\n")
        return SUPERVISOR_ERROR_RC

    command = sys.argv[3:]
    if not command:
        sys.stderr.write("Error: command must be non-empty\n")
        return SUPERVISOR_ERROR_RC

    try:
        supervisor = ProcessSupervisor(timeout_seconds=timeout_sec, command=command)
        rc = supervisor.run()
        return rc
    except Exception as e:
        sys.stderr.write(f"Supervisor internal error: {e}\n")
        return SUPERVISOR_ERROR_RC


if __name__ == "__main__":
    sys.exit(main())
