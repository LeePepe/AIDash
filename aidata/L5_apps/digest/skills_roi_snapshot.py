"""Canonical aidash-personal-skills-roi/v1 artifact for the read-only App.

The configured retro producer owns S1/S2/S3/S4/S6..S12 and their metadata.
Keep its complete report under diagnostics, never rename it to a metrics-only
map or invent S5. skills/daily remains separate day/source/skill populations.
Missing producer/query data is an explicit degraded artifact, not healthy zeros.
"""

from __future__ import annotations

import argparse
import contextlib
import hashlib
import json
import os
import re
import sqlite3
import subprocess
import tempfile
from collections.abc import Callable, Mapping, Sequence
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

import config
import serve
from config import resolve_icloud_sync_dir
from timeutil import CST

_SECTION_TYPES = {
    "S1_pin_drift": dict, "S2_gate_catch": dict, "S3_skill_health": dict,
    "S4_usage_and_r1": dict, "S6_load_vs_script": list,
    "S7_disclosure_funnel": list, "S8_post_skill_churn": list,
    "S9_escape_attribution": list, "S10_skill_roi_ranking": list,
    "S11_context_composition": dict, "S12_tool_context_burn": list,
}
_META = ("window_cst", "window_start", "window_end", "source_as_of", "sample_size", "coverage_status")
_COVERAGE = {"healthy", "partial", "unknown", "missing", "error"}
_VERSION_EVOLUTION_STATUSES = {"improved", "regressed", "observing", "baseline"}
_STATUS_LABELS_ZH = {
    "improved": "✅ 有效演进",
    "regressed": "⚠️ 退化告警",
    "observing": "⏳ 样本积累中",
    "baseline": "🕰️ 基准版本",
}
_DEFAULT_SKILLS_REPO = Path.home() / "Development" / "user-skills"
_DEFAULT_USAGE_JSONL = Path.home() / ".local" / "share" / "skill-telemetry" / "usage.jsonl"
_SKILL_Version_FINGERPRINT_RE = re.compile(
    r"^(?:(?P<semver>[0-9A-Za-z._-]+)\+)?v(?P<commit_count>\d+)@(?P<subtree_sha>[0-9a-fA-F]{4,40})$"
)


def _norm_skill_name(name: Any) -> str:
    raw = str(name or "").strip().lstrip("/")
    if raw in {"goal-target-task", "goal-task"}:
        return "team-lead"
    return raw


def _parse_iso_timestamp(value: Any) -> datetime | None:
    if value is None or value == "":
        return None
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        with contextlib.suppress(OverflowError, OSError, ValueError):
            ts_val = float(value)
            if ts_val > 1e12:
                ts_val /= 1000.0
            return datetime.fromtimestamp(ts_val, tz=timezone.utc).astimezone(CST)  # noqa: UP017
    text = str(value).strip()
    if not text:
        return None
    if text.isdigit():
        with contextlib.suppress(OverflowError, OSError, ValueError):
            ts_val = float(text)
            if ts_val > 1e12:
                ts_val /= 1000.0
            return datetime.fromtimestamp(ts_val, tz=timezone.utc).astimezone(CST)  # noqa: UP017
    with contextlib.suppress(ValueError):
        normalized = re.sub(r"([+-]\d{2})(\d{2})$", r"\1:\2", text.replace("Z", "+00:00"))
        stamp = datetime.fromisoformat(normalized)
        if stamp.tzinfo is None:
            stamp = stamp.replace(tzinfo=CST if len(text) == 10 else timezone.utc)  # noqa: UP017
        return stamp.astimezone(CST)
    return None


def _percentile(values: Sequence[float], pct: float) -> float | None:
    if not values:
        return None
    ordered = sorted(float(v) for v in values)
    idx = max(0, min(len(ordered) - 1, int((len(ordered) * pct + 99) // 100) - 1))
    return round(ordered[idx], 2)


def _content_hash_subtree(pkg_dir: Path) -> str:
    digest = hashlib.sha256()
    if pkg_dir.is_dir():
        for file_path in sorted(pkg_dir.rglob("*")):
            if not file_path.is_file() or "__pycache__" in file_path.parts or file_path.name.startswith("."):
                continue
            with contextlib.suppress(OSError):
                rel = file_path.relative_to(pkg_dir).as_posix()
                digest.update(rel.encode("utf-8") + b"\0" + file_path.read_bytes() + b"\0")
    return digest.hexdigest()[:7]


def _read_plugin_semver(pkg_dir: Path) -> str:
    manifest = pkg_dir / ".claude-plugin" / "plugin.json"
    if manifest.is_file():
        with contextlib.suppress(OSError, json.JSONDecodeError):
            doc = json.loads(manifest.read_text(encoding="utf-8"))
            if isinstance(doc, Mapping):
                ver = str(doc.get("version") or "").strip()
                if ver:
                    return ver
    return "1.0.0"


def _read_plugin_semver_at_commit(git_root: Path, commit_sha: str, skill_name: str, default_semver: str) -> str:
    clean_env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    rel_manifest = f"skills/{skill_name}/.claude-plugin/plugin.json"
    with contextlib.suppress(OSError, subprocess.SubprocessError, json.JSONDecodeError):
        proc = subprocess.run(
            ["git", "--no-optional-locks", "show", f"{commit_sha}:{rel_manifest}"],
            cwd=git_root,
            env=clean_env,
            capture_output=True,
            text=True,
            timeout=1.5,
            check=False,
        )
        if proc.returncode == 0 and proc.stdout.strip():
            doc = json.loads(proc.stdout)
            if isinstance(doc, Mapping):
                ver = str(doc.get("version") or "").strip()
                if ver:
                    return ver
    return default_semver


def _normalize_rel_drawer(raw_path: Any) -> str:
    cleaned = str(raw_path or "").strip().replace("\\", "/")
    if not cleaned:
        return ""
    idx = cleaned.find("/references/")
    if idx != -1:
        return f"references/{cleaned[idx + len('/references/'):].lstrip('/')}"
    if cleaned.startswith("references/"):
        return cleaned
    return f"references/{cleaned.lstrip('/')}"


def _normalize_rel_script(raw_path: Any) -> str:
    cleaned = str(raw_path or "").strip().replace("\\", "/")
    if not cleaned or cleaned.startswith("legacy:"):
        return ""
    idx = cleaned.find("/scripts/")
    if idx != -1:
        return f"scripts/{cleaned[idx + len('/scripts/'):].lstrip('/')}"
    if cleaned.startswith("scripts/"):
        return cleaned
    return f"scripts/{cleaned.lstrip('/')}"


def _discover_skill_drawers_and_links(pkg_dir: Path) -> dict[str, Any]:
    """Inspect SKILL.md, references/, and scripts/ to identify drawers and broken/unreferenced links."""
    refs_dir = pkg_dir / "references"
    scripts_dir = pkg_dir / "scripts"
    skill_md = pkg_dir / "SKILL.md"
    l0_text = ""
    if skill_md.is_file():
        with contextlib.suppress(OSError):
            l0_text = skill_md.read_text(encoding="utf-8", errors="ignore")

    script_texts: list[str] = []
    if scripts_dir.is_dir():
        for sp in sorted(scripts_dir.rglob("*")):
            if not sp.is_file() or sp.name.startswith(".") or "__pycache__" in sp.parts:
                continue
            if sp.suffix.lower() in {".py", ".sh"}:
                with contextlib.suppress(OSError):
                    script_texts.append(sp.read_text(encoding="utf-8", errors="ignore"))

    ref_texts: dict[str, str] = {}
    drawers: list[str] = []
    broken_links = 0
    if refs_dir.is_dir():
        for rp in sorted(refs_dir.rglob("*")):
            if rp.is_symlink() and not rp.exists():
                broken_links += 1
                continue
            if not rp.is_file() or rp.name.startswith(".") or "__pycache__" in rp.parts:
                continue
            rel = f"references/{rp.relative_to(refs_dir).as_posix()}"
            drawers.append(rel)
            if rp.suffix.lower() in {".md", ".json", ".yaml", ".yml"}:
                with contextlib.suppress(OSError):
                    ref_texts[rel] = rp.read_text(encoding="utf-8", errors="ignore")

    # Check markdown links in SKILL.md pointing to missing references/ files
    for match in re.finditer(r"\((?:\./)?(references/[^)#\s]+)", l0_text):
        target_rel = match.group(1).strip()
        if not (pkg_dir / target_rel).exists():
            broken_links += 1

    static_unreferenced: set[str] = set()
    script_linked: set[str] = set()
    l0_linked: set[str] = set()
    scripts_joined = "\n".join(script_texts)
    for rel in drawers:
        short_name = Path(rel).name
        if rel in l0_text or short_name in l0_text:
            l0_linked.add(rel)
        if rel in scripts_joined or short_name in scripts_joined:
            script_linked.add(rel)
        other_refs = "\n".join(txt for k, txt in ref_texts.items() if k != rel)
        if rel not in l0_text and short_name not in l0_text and rel not in scripts_joined and short_name not in scripts_joined and rel not in other_refs and short_name not in other_refs:
            static_unreferenced.add(rel)

    return {
        "drawers": drawers,
        "broken_links": broken_links,
        "static_unreferenced": static_unreferenced,
        "l0_linked": l0_linked,
        "script_linked": script_linked,
    }


def resolve_skill_version_history(
    skills_repo: Path | None = None,
    *,
    skill_names: Sequence[str] | None = None,
) -> dict[str, list[dict[str, Any]]]:
    """Resolve per-skill dual-track version history (`semver` + `v<commit_count>@<subtree_sha>`) and `[t_start, t_end)` windows."""
    repo_root = Path(skills_repo) if skills_repo is not None else _DEFAULT_SKILLS_REPO
    skills_dir = repo_root / "skills" if (repo_root / "skills").is_dir() else repo_root
    if not skills_dir.is_dir():
        return {}

    target_filter = {_norm_skill_name(s) for s in skill_names if _norm_skill_name(s)} if skill_names else None
    pkg_dirs: dict[str, Path] = {}
    for child in sorted(skills_dir.iterdir()):
        if not child.is_dir() or not (child / "SKILL.md").is_file():
            continue
        sk_name = _norm_skill_name(child.name)
        if target_filter is not None and sk_name not in target_filter:
            continue
        pkg_dirs[sk_name] = child

    if not pkg_dirs:
        return {}

    git_root = repo_root if (repo_root / ".git").exists() else (skills_dir.parent if (skills_dir.parent / ".git").exists() else None)
    raw_commits_by_skill: dict[str, list[tuple[str, int, str, str, str]]] = {}

    if git_root is not None:
        clean_env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
        with contextlib.suppress(OSError, subprocess.SubprocessError):
            proc = subprocess.run(
                [
                    "git",
                    "--no-optional-locks",
                    "log",
                    "--reverse",
                    "-c",
                    "--raw",
                    "-t",
                    "--no-abbrev",
                    "--format=COMMIT|%H|%ct|%cI|%s",
                    "--",
                    "skills",
                ],
                cwd=git_root,
                env=clean_env,
                capture_output=True,
                text=True,
                timeout=8.0,
                check=False,
            )
            if proc.returncode == 0:
                cur_commit: tuple[str, int, str, str] | None = None
                seen_in_commit: set[str] = set()
                for line in proc.stdout.splitlines():
                    if line.startswith("COMMIT|"):
                        parts = line.split("|", 4)
                        if len(parts) == 5 and parts[2].strip().lstrip("-").isdigit():
                            cur_commit = (parts[1].strip(), int(parts[2].strip()), parts[3].strip(), parts[4].strip())
                            seen_in_commit = set()
                        else:
                            cur_commit = None
                    elif line.startswith(":") and "\tskills/" in line and cur_commit is not None:
                        meta_part, path_part = line.split("\t", 1)
                        path_segs = path_part.strip().split("/")
                        if len(path_segs) == 2 and path_segs[0] == "skills":
                            sk_raw = _norm_skill_name(path_segs[1])
                            if sk_raw not in pkg_dirs or sk_raw in seen_in_commit:
                                continue
                            tokens = meta_part.split()
                            if len(tokens) >= 5:
                                new_tree = tokens[-2].strip()
                                if set(new_tree) != {"0"}:
                                    seen_in_commit.add(sk_raw)
                                    raw_commits_by_skill.setdefault(sk_raw, []).append((*cur_commit, new_tree[:7]))

    histories: dict[str, list[dict[str, Any]]] = {}
    for sk_name, pkg_dir in sorted(pkg_dirs.items()):
        head_semver = _read_plugin_semver(pkg_dir)
        drawer_meta = _discover_skill_drawers_and_links(pkg_dir)
        commits = raw_commits_by_skill.get(sk_name) or []
        if not commits:
            subtree_sha = _content_hash_subtree(pkg_dir)
            mtime_epoch = 0
            with contextlib.suppress(OSError):
                mtime_epoch = int((pkg_dir / "SKILL.md").stat().st_mtime)
            t_start_iso = datetime.fromtimestamp(mtime_epoch, tz=timezone.utc).astimezone(CST).isoformat(timespec="seconds")  # noqa: UP017
            skill_ver = f"v1@{subtree_sha}"
            histories[sk_name] = [
                {
                    "skill": sk_name,
                    "version_index": 1,
                    "commit_count": 1,
                    "semver": head_semver,
                    "plugin_version": head_semver,
                    "subtree_sha": subtree_sha,
                    "skill_version": skill_ver,
                    "combined_version": f"{head_semver}+{skill_ver}",
                    "commit_sha": subtree_sha,
                    "commit_subject": "initial baseline",
                    "t_start": t_start_iso,
                    "t_end": None,
                    "t_start_epoch": mtime_epoch,
                    "t_end_epoch": None,
                    "_drawer_meta": drawer_meta,
                }
            ]
            continue

        total_commits = len(commits)
        entries: list[dict[str, Any]] = []
        for idx, (c_sha, c_epoch, c_iso, c_subj, sub_sha) in enumerate(commits):
            ver_num = idx + 1
            next_epoch = commits[idx + 1][1] if idx + 1 < total_commits else None
            next_iso = commits[idx + 1][2] if idx + 1 < total_commits else None
            if git_root is not None and idx == total_commits - 2:
                semver_val = _read_plugin_semver_at_commit(git_root, c_sha, sk_name, head_semver)
            else:
                semver_val = head_semver
            skill_ver = f"v{ver_num}@{sub_sha}"
            entries.append(
                {
                    "skill": sk_name,
                    "version_index": ver_num,
                    "commit_count": ver_num,
                    "semver": semver_val,
                    "plugin_version": semver_val,
                    "subtree_sha": sub_sha,
                    "skill_version": skill_ver,
                    "combined_version": f"{semver_val}+{skill_ver}",
                    "commit_sha": c_sha[:7],
                    "commit_subject": c_subj,
                    "t_start": c_iso,
                    "t_end": next_iso,
                    "t_start_epoch": c_epoch,
                    "t_end_epoch": next_epoch,
                    "_drawer_meta": drawer_meta,
                }
            )
        histories[sk_name] = entries
    return histories


def match_skill_version_for_event(
    skill: str,
    version_history: Sequence[Mapping[str, Any]],
    *,
    explicit_skill_version: str | None = None,
    explicit_subtree_sha: str | None = None,
    event_ts: Any = None,
) -> dict[str, Any] | None:
    """Resolve the active version entry for a skill telemetry event (explicit version first, then timestamp window `[t_start, t_end)`)."""
    if not version_history:
        return None
    raw_ver = str(explicit_skill_version or "").strip()
    raw_sub = str(explicit_subtree_sha or "").strip()
    if raw_ver:
        for entry in version_history:
            if raw_ver in {
                str(entry.get("skill_version") or ""),
                str(entry.get("combined_version") or ""),
            }:
                return dict(entry)
        m = _SKILL_Version_FINGERPRINT_RE.match(raw_ver)
        if m:
            sub_q = m.group("subtree_sha").lower()
            cnt_q = int(m.group("commit_count"))
            for entry in version_history:
                if str(entry.get("subtree_sha") or "").lower().startswith(sub_q) or sub_q.startswith(str(entry.get("subtree_sha") or "").lower()):
                    return dict(entry)
            for entry in version_history:
                if int(entry.get("commit_count") or 0) == cnt_q:
                    return dict(entry)
    if raw_sub:
        sub_q = raw_sub.lower()
        for entry in version_history:
            e_sub = str(entry.get("subtree_sha") or "").lower()
            if e_sub and (e_sub.startswith(sub_q) or sub_q.startswith(e_sub)):
                return dict(entry)

    parsed_ts = _parse_iso_timestamp(event_ts)
    if parsed_ts is not None:
        ev_epoch = parsed_ts.timestamp()
        for idx, entry in enumerate(version_history):
            t_start = entry.get("t_start_epoch")
            t_end = entry.get("t_end_epoch")
            if t_start is None:
                continue
            if idx == 0 and ev_epoch < float(t_start):
                return dict(entry)
            if float(t_start) <= ev_epoch and (t_end is None or ev_epoch < float(t_end)):
                return dict(entry)
        return dict(version_history[-1])

    return dict(version_history[-1])


def _new_version_bucket(version_entry: Mapping[str, Any]) -> dict[str, Any]:
    return {
        "meta": dict(version_entry),
        "sessions": set(),
        "invocations": 0,
        "script_calls": 0,
        "graded_script_calls": 0,
        "exit0_count": 0,
        "exit1_count": 0,
        "exit2_count": 0,
        "script_durations_ms": [],
        "hit_drawers": set(),
        "reference_hits": 0,
        "r1_total": 0,
        "r1_pass": 0,
        "uptake_passed": 0,
        "uptake_total": 0,
        "explicit_uptake_rates": [],
        "explicit_broken_drawers": None,
        "observed_stamps": [],
    }


def _collect_telemetry_into_version_buckets(
    histories: Mapping[str, Sequence[Mapping[str, Any]]],
    *,
    usage_jsonl: Path | None = None,
    warehouse_db: Path | None = None,
    clean_dir: Path | None = None,
    raw_dir: Path | None = None,
    report: Mapping[str, Any] | None = None,
    window_start: datetime | None = None,
    window_end: datetime | None = None,
) -> dict[str, dict[str, dict[str, Any]]]:
    buckets: dict[str, dict[str, dict[str, Any]]] = {
        sk: {str(v["skill_version"]): _new_version_bucket(v) for v in ver_list}
        for sk, ver_list in histories.items()
    }
    if not buckets:
        return buckets

    seen_turns: set[tuple[str, str, str]] = set()
    seen_refs: set[tuple[str, str, str]] = set()
    seen_scripts: set[tuple[str, str, str]] = set()
    seen_reviews: set[tuple[str, str]] = set()

    def _in_window(stamp: datetime | None) -> bool:
        if stamp is None:
            return True
        if window_start is not None and stamp < window_start:
            return False
        return not (window_end is not None and stamp >= window_end)

    def _resolve_bucket(
        sk_raw: Any,
        *,
        skill_version: Any = None,
        subtree_sha: Any = None,
        ts: Any = None,
    ) -> tuple[str, dict[str, Any], datetime | None] | None:
        sk = _norm_skill_name(sk_raw)
        if sk not in histories or not histories[sk]:
            return None
        stamp = _parse_iso_timestamp(ts)
        if not _in_window(stamp):
            return None
        matched = match_skill_version_for_event(
            sk,
            histories[sk],
            explicit_skill_version=str(skill_version or "").strip() or None,
            explicit_subtree_sha=str(subtree_sha or "").strip() or None,
            event_ts=stamp or ts,
        )
        if not matched:
            return None
        sv_key = str(matched["skill_version"])
        bucket = buckets[sk].setdefault(sv_key, _new_version_bucket(matched))
        if stamp is not None:
            bucket["observed_stamps"].append(stamp)
        return sk, bucket, stamp

    # 1. Read usage.jsonl
    if usage_jsonl is not None and usage_jsonl.is_file():
        with contextlib.suppress(OSError), usage_jsonl.open("r", encoding="utf-8", errors="ignore") as handle:
            for line in handle:
                line_s = line.strip()
                if not line_s:
                    continue
                with contextlib.suppress(ValueError, TypeError):
                    rec = json.loads(line_s)
                    if not isinstance(rec, Mapping):
                        continue
                    kind = str(rec.get("kind") or "").strip()
                    if kind not in {"skill_turn", "reference_hit", "script_call"}:
                        continue
                    ts_raw = rec.get("ts") or rec.get("timestamp") or rec.get("t")
                    res = _resolve_bucket(
                        rec.get("skill"),
                        skill_version=rec.get("skill_version"),
                        subtree_sha=rec.get("subtree_sha"),
                        ts=ts_raw,
                    )
                    if res is None:
                        continue
                    sk, bkt, _stamp = res
                    sid = str(rec.get("session_id") or rec.get("event_id") or f"u-{bkt['invocations']}")
                    tid = str(rec.get("turn_id") or rec.get("call_uid") or rec.get("hit_uid") or rec.get("event_id") or "")
                    if kind == "skill_turn":
                        sig = (sid, tid, sk)
                        if tid and sig in seen_turns:
                            continue
                        if tid:
                            seen_turns.add(sig)
                        bkt["sessions"].add(sid)
                        bkt["invocations"] += 1
                        if rec.get("uptake_rate") is not None and not isinstance(rec.get("uptake_rate"), bool):
                            with contextlib.suppress(TypeError, ValueError):
                                bkt["explicit_uptake_rates"].append(float(rec["uptake_rate"]))
                    elif kind == "reference_hit":
                        rel_ref = _normalize_rel_drawer(rec.get("reference_path"))
                        sig = (sid, sk, f"{tid}:{rel_ref}")
                        if sig in seen_refs:
                            continue
                        seen_refs.add(sig)
                        bkt["sessions"].add(sid)
                        bkt["reference_hits"] += 1
                        if rel_ref:
                            bkt["hit_drawers"].add(rel_ref)
                    elif kind == "script_call":
                        rel_sc = _normalize_rel_script(rec.get("script_path"))
                        call_id = str(rec.get("call_uid") or tid or f"{ts_raw}:{rel_sc}")
                        sig = (sid, sk, call_id)
                        if sig in seen_scripts:
                            continue
                        seen_scripts.add(sig)
                        bkt["sessions"].add(sid)
                        bkt["script_calls"] += 1
                        ec_raw = rec.get("exit_code")
                        if ec_raw not in (None, "") and not isinstance(ec_raw, bool):
                            with contextlib.suppress(TypeError, ValueError):
                                ec = int(ec_raw)
                                bkt["graded_script_calls"] += 1
                                if ec == 0:
                                    bkt["exit0_count"] += 1
                                elif ec == 2:
                                    bkt["exit2_count"] += 1
                                else:
                                    bkt["exit1_count"] += 1
                        dur_raw = rec.get("duration_ms")
                        if dur_raw not in (None, "") and not isinstance(dur_raw, bool):
                            with contextlib.suppress(TypeError, ValueError):
                                dur = float(dur_raw)
                                if dur >= 0:
                                    bkt["script_durations_ms"].append(dur)

    # 2. Read warehouse.db (fact_turn, reference_hits, script_call, fact_gtt_task_run)
    if warehouse_db is not None and warehouse_db.is_file():
        with contextlib.suppress(sqlite3.Error, OSError), contextlib.closing(
            sqlite3.connect(f"{warehouse_db.resolve().as_uri()}?mode=ro", uri=True)
        ) as conn:
            tables = {r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")}
            if "fact_turn" in tables:
                cols = {r[1] for r in conn.execute("PRAGMA table_info(fact_turn)")}
                sv_col = "skill_version" if "skill_version" in cols else "NULL AS skill_version"
                for turn_uuid, sid, ts_raw, attr_sk, sk_names_json, sv_val in conn.execute(
                    f"SELECT turn_uuid, session_id, COALESCE(ts, cst_day), attribution_skill, skill_names, {sv_col} "
                    "FROM fact_turn WHERE attribution_skill IS NOT NULL OR skill_names IS NOT NULL"
                ):
                    turn_skills: set[str] = set()
                    if attr_sk:
                        turn_skills.add(_norm_skill_name(attr_sk))
                    if sk_names_json:
                        with contextlib.suppress(ValueError, TypeError):
                            parsed_names = json.loads(str(sk_names_json))
                            if isinstance(parsed_names, list):
                                for item in parsed_names:
                                    if item:
                                        turn_skills.add(_norm_skill_name(item))
                    for sk in turn_skills:
                        res = _resolve_bucket(sk, skill_version=sv_val, ts=ts_raw)
                        if res is None:
                            continue
                        _, bkt, _ = res
                        sid_s = str(sid or turn_uuid or "wh-session")
                        tid_s = str(turn_uuid or "")
                        sig = (sid_s, tid_s, sk)
                        if tid_s and sig in seen_turns:
                            continue
                        if tid_s:
                            seen_turns.add(sig)
                        bkt["sessions"].add(sid_s)
                        bkt["invocations"] += 1

            if "reference_hits" in tables:
                cols = {r[1] for r in conn.execute("PRAGMA table_info(reference_hits)")}
                sv_col = "skill_version" if "skill_version" in cols else "NULL AS skill_version"
                for hit_uid, sid, sk_raw, ref_path, ts_raw, sv_val in conn.execute(
                    f"SELECT hit_uid, session_id, skill, reference_path, COALESCE(ts, cst_day), {sv_col} "
                    "FROM reference_hits WHERE skill IS NOT NULL AND reference_path IS NOT NULL"
                ):
                    res = _resolve_bucket(sk_raw, skill_version=sv_val, ts=ts_raw)
                    if res is None:
                        continue
                    sk, bkt, _ = res
                    sid_s = str(sid or hit_uid or "wh-ref")
                    rel_ref = _normalize_rel_drawer(ref_path)
                    sig = (sid_s, sk, f"{hit_uid}:{rel_ref}")
                    if sig in seen_refs:
                        continue
                    seen_refs.add(sig)
                    bkt["sessions"].add(sid_s)
                    bkt["reference_hits"] += 1
                    if rel_ref:
                        bkt["hit_drawers"].add(rel_ref)

            if "script_call" in tables:
                cols = {r[1] for r in conn.execute("PRAGMA table_info(script_call)")}
                sv_col = "skill_version" if "skill_version" in cols else "NULL AS skill_version"
                for call_uid, sid, sk_raw, sc_path, ec_raw, dur_raw, ts_raw, sv_val in conn.execute(
                    f"SELECT call_uid, session_id, skill, script_path, exit_code, duration_ms, COALESCE(ts, cst_day), {sv_col} "
                    "FROM script_call WHERE skill IS NOT NULL AND script_path IS NOT NULL"
                ):
                    res = _resolve_bucket(sk_raw, skill_version=sv_val, ts=ts_raw)
                    if res is None:
                        continue
                    sk, bkt, _ = res
                    sid_s = str(sid or call_uid or "wh-sc")
                    sig = (sid_s, sk, str(call_uid or f"{ts_raw}:{sc_path}"))
                    if sig in seen_scripts:
                        continue
                    seen_scripts.add(sig)
                    bkt["sessions"].add(sid_s)
                    bkt["script_calls"] += 1
                    if ec_raw is not None and not isinstance(ec_raw, bool):
                        with contextlib.suppress(TypeError, ValueError):
                            ec = int(ec_raw)
                            bkt["graded_script_calls"] += 1
                            if ec == 0:
                                bkt["exit0_count"] += 1
                            elif ec == 2:
                                bkt["exit2_count"] += 1
                            else:
                                bkt["exit1_count"] += 1
                    if dur_raw is not None and not isinstance(dur_raw, bool):
                        with contextlib.suppress(TypeError, ValueError):
                            dur = float(dur_raw)
                            if dur >= 0:
                                bkt["script_durations_ms"].append(dur)

            if "fact_gtt_task_run" in tables:
                cols = {r[1] for r in conn.execute("PRAGMA table_info(fact_gtt_task_run)")}
                sv_col = "skill_version" if "skill_version" in cols else "NULL AS skill_version"
                for receipt_uid, goal_id, role_name, round_no, v5_verdict, status, completed_at, cst_day, skills_used, sv_val in conn.execute(
                    f"SELECT receipt_uid, goal_id, role_name, round_no, v5_verdict, status, completed_at, cst_day, skills_used, {sv_col} "
                    "FROM fact_gtt_task_run WHERE role_name IN ('reviewer', 'code_reviewer', 'planner_reviewer')"
                ):
                    ts_use = completed_at if _parse_iso_timestamp(completed_at) is not None else cst_day
                    if _parse_iso_timestamp(ts_use) is None and not sv_val:
                        continue
                    matched_skills: set[str] = set()
                    if skills_used:
                        with contextlib.suppress(ValueError, TypeError):
                            parsed = json.loads(str(skills_used))
                            if isinstance(parsed, list):
                                for item in parsed:
                                    norm_s = _norm_skill_name(item)
                                    if norm_s in histories:
                                        matched_skills.add(norm_s)
                    if not matched_skills and goal_id:
                        gl = str(goal_id).lower()
                        fallback_sk = (
                            "my-designer" if any(k in gl for k in ("design", "ui", "feel", "glass"))
                            else "design-studio" if any(k in gl for k in ("ingest", "palette", "motion"))
                            else "retro-loop" if any(k in gl for k in ("retro", "telemetry", "roi", "aidash"))
                            else "knowledge-digest" if any(k in gl for k in ("learn", "digest", "blog", "vault"))
                            else "skill-contract" if any(k in gl for k in ("skill", "contract"))
                            else "m2-dispatcher" if any(k in gl for k in ("m2", "herdr", "dispatch"))
                            else "team-lead"
                        )
                        if fallback_sk in histories:
                            matched_skills.add(fallback_sk)
                    if int(round_no or 0) == 1:
                        v5_up = str(v5_verdict or "").strip().upper()
                        st_low = str(status or "").strip().lower()
                        passed = v5_up in {"PASS", "CONCERNS", "WAIVED"} and st_low != "failed"
                        for sk in matched_skills:
                            rev_sig = (str(receipt_uid or f"{goal_id}:{ts_use}"), sk)
                            if rev_sig in seen_reviews:
                                continue
                            seen_reviews.add(rev_sig)
                            res = _resolve_bucket(sk, skill_version=sv_val, ts=ts_use)
                            if res is None:
                                continue
                            _, bkt, _ = res
                            bkt["r1_total"] += 1
                            if passed:
                                bkt["r1_pass"] += 1

    # 3. Read L2 clean DBs (copilot_cli.db, gtt_receipt.db) when present
    if clean_dir is not None and clean_dir.is_dir():
        cp_clean = clean_dir / "copilot_cli.db"
        if cp_clean.is_file():
            with contextlib.suppress(sqlite3.Error, OSError), contextlib.closing(
                sqlite3.connect(f"{cp_clean.resolve().as_uri()}?mode=ro", uri=True)
            ) as conn:
                tables = {r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")}
                if "skill_day" in tables:
                    for day_s, sk_raw, n_val in conn.execute("SELECT day, skill, n FROM skill_day WHERE skill IS NOT NULL"):
                        res = _resolve_bucket(sk_raw, ts=day_s)
                        if res is None:
                            continue
                        sk, bkt, _ = res
                        n_int = max(0, int(n_val or 0))
                        sig = (f"cp-day:{day_s}", "skill_day", sk)
                        if sig not in seen_turns and n_int > 0:
                            seen_turns.add(sig)
                            bkt["invocations"] += n_int
                            bkt["sessions"].add(f"copilot:{day_s}:{sk}")
                if "reference_hit" in tables:
                    for hit_uid, sid, sk_raw, ref_path, ts_raw in conn.execute(
                        "SELECT hit_uid, session_id, skill, reference_path, ts FROM reference_hit WHERE skill IS NOT NULL AND reference_path IS NOT NULL"
                    ):
                        res = _resolve_bucket(sk_raw, ts=ts_raw)
                        if res is None:
                            continue
                        sk, bkt, _ = res
                        sid_s = str(sid or hit_uid or "cp-ref")
                        rel_ref = _normalize_rel_drawer(ref_path)
                        sig = (sid_s, sk, f"{hit_uid}:{rel_ref}")
                        if sig not in seen_refs:
                            seen_refs.add(sig)
                            bkt["sessions"].add(sid_s)
                            bkt["reference_hits"] += 1
                            if rel_ref:
                                bkt["hit_drawers"].add(rel_ref)
                if "script_call" in tables:
                    for call_uid, sid, sk_raw, sc_path, ec_raw, dur_raw, ts_raw in conn.execute(
                        "SELECT call_uid, session_id, skill, script_path, exit_code, duration_ms, ts FROM script_call WHERE skill IS NOT NULL AND script_path IS NOT NULL"
                    ):
                        res = _resolve_bucket(sk_raw, ts=ts_raw)
                        if res is None:
                            continue
                        sk, bkt, _ = res
                        sid_s = str(sid or call_uid or "cp-sc")
                        sig = (sid_s, sk, str(call_uid or f"{ts_raw}:{sc_path}"))
                        if sig not in seen_scripts:
                            seen_scripts.add(sig)
                            bkt["sessions"].add(sid_s)
                            bkt["script_calls"] += 1
                            if ec_raw is not None and not isinstance(ec_raw, bool):
                                with contextlib.suppress(TypeError, ValueError):
                                    ec = int(ec_raw)
                                    bkt["graded_script_calls"] += 1
                                    if ec == 0:
                                        bkt["exit0_count"] += 1
                                    elif ec == 2:
                                        bkt["exit2_count"] += 1
                                    else:
                                        bkt["exit1_count"] += 1
                            if dur_raw is not None and not isinstance(dur_raw, bool):
                                with contextlib.suppress(TypeError, ValueError):
                                    dur = float(dur_raw)
                                    if dur >= 0:
                                        bkt["script_durations_ms"].append(dur)

        gtt_clean = clean_dir / "gtt_receipt.db"
        if gtt_clean.is_file():
            with contextlib.suppress(sqlite3.Error, OSError), contextlib.closing(
                sqlite3.connect(f"{gtt_clean.resolve().as_uri()}?mode=ro", uri=True)
            ) as conn:
                tables = {r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")}
                if "task_run" in tables:
                    for receipt_uid, goal_id, role_name, round_no, v5_verdict, status, completed_at, skills_used in conn.execute(
                        "SELECT receipt_uid, goal_id, role_name, round_no, v5_verdict, status, completed_at, skills_used "
                        "FROM task_run WHERE role_name IN ('reviewer', 'code_reviewer', 'planner_reviewer')"
                    ):
                        if int(round_no or 0) != 1:
                            continue
                        if _parse_iso_timestamp(completed_at) is None:
                            continue
                        matched_skills: set[str] = set()
                        if skills_used:
                            with contextlib.suppress(ValueError, TypeError):
                                parsed = json.loads(str(skills_used))
                                if isinstance(parsed, list):
                                    for item in parsed:
                                        norm_s = _norm_skill_name(item)
                                        if norm_s in histories:
                                            matched_skills.add(norm_s)
                        v5_up = str(v5_verdict or "").strip().upper()
                        st_low = str(status or "").strip().lower()
                        passed = v5_up in {"PASS", "CONCERNS", "WAIVED"} and st_low != "failed"
                        for sk in matched_skills:
                            rev_sig = (str(receipt_uid or f"{goal_id}:{completed_at}"), sk)
                            if rev_sig in seen_reviews:
                                continue
                            seen_reviews.add(rev_sig)
                            res = _resolve_bucket(sk, ts=completed_at)
                            if res is None:
                                continue
                            _, bkt, _ = res
                            bkt["r1_total"] += 1
                            if passed:
                                bkt["r1_pass"] += 1

    # 4. Read raw copilot_cli and gtt_receipt JSONL if present
    if raw_dir is not None and raw_dir.is_dir():
        cp_raw_dir = raw_dir / "copilot_cli"
        if cp_raw_dir.is_dir():
            for jf in sorted(cp_raw_dir.glob("*.jsonl"))[-14:]:
                with contextlib.suppress(OSError):
                    for line in jf.read_text(encoding="utf-8", errors="ignore").splitlines():
                        if not line.strip():
                            continue
                        with contextlib.suppress(ValueError, TypeError):
                            rec = json.loads(line)
                            if not isinstance(rec, Mapping):
                                continue
                            kind = str(rec.get("kind") or "skill_turn").strip()
                            ts_raw = rec.get("timestamp") or rec.get("ts")
                            res = _resolve_bucket(
                                rec.get("skill"),
                                skill_version=rec.get("skill_version"),
                                subtree_sha=rec.get("subtree_sha"),
                                ts=ts_raw,
                            )
                            if res is None:
                                continue
                            sk, bkt, _ = res
                            sid_s = str(rec.get("session_id") or rec.get("event_id") or "cp-raw")
                            if kind == "reference_hit":
                                rel_ref = _normalize_rel_drawer(rec.get("reference_path"))
                                uid = str(rec.get("hit_uid") or "")
                                sig = (sid_s, sk, f"{uid}:{rel_ref}")
                                if sig not in seen_refs:
                                    seen_refs.add(sig)
                                    bkt["sessions"].add(sid_s)
                                    bkt["reference_hits"] += 1
                                    if rel_ref:
                                        bkt["hit_drawers"].add(rel_ref)
                            elif kind == "script_call":
                                uid = str(rec.get("call_uid") or "")
                                sig = (sid_s, sk, uid or f"{ts_raw}:{rec.get('script_path')}")
                                if sig not in seen_scripts:
                                    seen_scripts.add(sig)
                                    bkt["sessions"].add(sid_s)
                                    bkt["script_calls"] += 1
                                    ec_raw = rec.get("exit_code")
                                    if ec_raw is not None and not isinstance(ec_raw, bool):
                                        ec = int(ec_raw)
                                        bkt["graded_script_calls"] += 1
                                        if ec == 0:
                                            bkt["exit0_count"] += 1
                                        elif ec == 2:
                                            bkt["exit2_count"] += 1
                                        else:
                                            bkt["exit1_count"] += 1
                                    dur_raw = rec.get("duration_ms")
                                    if dur_raw is not None and not isinstance(dur_raw, bool):
                                        dur = float(dur_raw)
                                        if dur >= 0:
                                            bkt["script_durations_ms"].append(dur)
                            else:
                                tid_s = str(rec.get("event_id") or rec.get("turn_id") or "")
                                sig = (sid_s, tid_s, sk)
                                if tid_s and sig not in seen_turns:
                                    seen_turns.add(sig)
                                    bkt["sessions"].add(sid_s)
                                    bkt["invocations"] += 1

        gtt_raw_dir = raw_dir / "gtt_receipt"
        if gtt_raw_dir.is_dir():
            for jf in sorted(gtt_raw_dir.glob("*.jsonl"))[-14:]:
                with contextlib.suppress(OSError):
                    for line in jf.read_text(encoding="utf-8", errors="ignore").splitlines():
                        if not line.strip():
                            continue
                        with contextlib.suppress(ValueError, TypeError):
                            rec = json.loads(line)
                            if not isinstance(rec, Mapping) or rec.get("record_type") != "receipt":
                                continue
                            rel_p = str(rec.get("rel_path") or "")
                            if not re.search(r"(?:rev|review).*?-r1\.md$", rel_p, re.IGNORECASE):
                                continue
                            content = str(rec.get("content") or "")
                            ts_m = re.search(r"\b20\d{2}-\d{2}-\d{2}(?:T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?)?\b", content)
                            ts_raw = ts_m.group(0) if ts_m else jf.stem
                            passed = bool(re.search(r"\b(?:PASS(?:ED)?|CONCERNS|WAIVED)\b", content.upper())) and not bool(
                                re.search(r"\bV5\s*[:=]\s*FAIL\b", content.upper())
                            )
                            skills_list: list[str] = []
                            if rec.get("skills_used"):
                                parsed_su = json.loads(str(rec["skills_used"])) if isinstance(rec["skills_used"], str) else rec["skills_used"]
                                if isinstance(parsed_su, list):
                                    skills_list = [_norm_skill_name(x) for x in parsed_su if _norm_skill_name(x) in histories]
                            for sk in skills_list:
                                rev_sig = (f"{rec.get('machine_id', 'm')}:{rel_p}", sk)
                                if rev_sig in seen_reviews:
                                    continue
                                seen_reviews.add(rev_sig)
                                res = _resolve_bucket(sk, skill_version=rec.get("skill_version"), ts=ts_raw)
                                if res is None:
                                    continue
                                _, bkt, _ = res
                                bkt["r1_total"] += 1
                                if passed:
                                    bkt["r1_pass"] += 1

    # 5. Enrich current version bucket from producer report (`S10_skill_roi_ranking` / `skill_details`) when telemetry files were not provided
    if isinstance(report, Mapping):
        for s10_row in report.get("S10_skill_roi_ranking") or []:
            if not isinstance(s10_row, Mapping):
                continue
            sk = _norm_skill_name(s10_row.get("skill"))
            if sk not in histories or not histories[sk]:
                continue
            head_ver = str(histories[sk][-1]["skill_version"])
            head_bkt = buckets[sk][head_ver]
            total_inv_across_versions = sum(b["invocations"] for b in buckets[sk].values())
            if total_inv_across_versions == 0:
                loads_val = int(s10_row.get("loads_7d") or s10_row.get("loads_30d") or 0)
                if loads_val > 0:
                    head_bkt["invocations"] = loads_val
                    for i in range(loads_val):
                        head_bkt["sessions"].add(f"report:{sk}:{i}")
            total_r1_across_versions = sum(b["r1_total"] for b in buckets[sk].values())
            if total_r1_across_versions == 0 and int(s10_row.get("r1_total") or 0) > 0:
                r1_t = int(s10_row["r1_total"])
                r1_rate = s10_row.get("r1_pass_rate")
                head_bkt["r1_total"] = r1_t
                if isinstance(r1_rate, (int, float)) and not isinstance(r1_rate, bool):
                    head_bkt["r1_pass"] = round(float(r1_rate) * r1_t)

    return buckets


def _summarize_version_bucket(bucket: Mapping[str, Any]) -> dict[str, Any]:
    meta = bucket["meta"]
    drawer_meta = meta.get("_drawer_meta") or {}
    sessions_cnt = max(len(bucket["sessions"]), int(bucket["invocations"]))
    invocations_cnt = max(int(bucket["invocations"]), len(bucket["sessions"]))
    sc_calls = int(bucket["script_calls"])
    exit2_cnt = int(bucket["exit2_count"])
    exit1_cnt = int(bucket["exit1_count"])
    post_fix_errors = exit2_cnt
    exit2_rate = round(exit2_cnt / sc_calls, 4) if sc_calls > 0 else (0.0 if sessions_cnt > 0 else None)
    p50_ms = _percentile(bucket["script_durations_ms"], 50)

    if bucket.get("explicit_broken_drawers") is not None:
        broken_drawer_cnt = max(0, int(bucket["explicit_broken_drawers"]))
    else:
        broken_links = int(drawer_meta.get("broken_links") or 0)
        static_unreferenced: set[str] = set(drawer_meta.get("static_unreferenced") or set())
        l0_linked: set[str] = set(drawer_meta.get("l0_linked") or set())
        script_linked: set[str] = set(drawer_meta.get("script_linked") or set())
        hit_drawers: set[str] = set(bucket["hit_drawers"])
        unwired_on_fail = set()
        if exit1_cnt > 0:
            unwired_on_fail = {d for d in (l0_linked - script_linked) if d not in hit_drawers}
        unreferenced_active = {d for d in static_unreferenced if d not in hit_drawers} if sessions_cnt > 0 else static_unreferenced
        broken_drawer_cnt = broken_links + len(unwired_on_fail | unreferenced_active)

    r1_tot = int(bucket["r1_total"])
    r1_pass = int(bucket["r1_pass"])
    r1_pass_rate = round(r1_pass / r1_tot, 4) if r1_tot > 0 else None

    if bucket["explicit_uptake_rates"]:
        uptake_rate = round(sum(bucket["explicit_uptake_rates"]) / len(bucket["explicit_uptake_rates"]), 4)
    elif int(bucket.get("uptake_total") or 0) > 0:
        uptake_rate = round(int(bucket["uptake_passed"]) / int(bucket["uptake_total"]), 4)
    elif sessions_cnt > 0:
        practiced = sc_calls + int(bucket["reference_hits"])
        if practiced > 0:
            good_practice = int(bucket["exit0_count"]) + int(bucket["reference_hits"])
            uptake_rate = round(min(1.0, good_practice / max(1, sc_calls + int(bucket["reference_hits"]))), 4)
        else:
            uptake_rate = 0.0
    else:
        uptake_rate = None

    return {
        "skill_version": str(meta["skill_version"]),
        "semver": str(meta.get("semver") or meta.get("plugin_version") or "1.0.0"),
        "plugin_version": str(meta.get("plugin_version") or meta.get("semver") or "1.0.0"),
        "combined_version": str(meta.get("combined_version") or f"{meta.get('semver', '1.0.0')}+{meta['skill_version']}"),
        "commit_count": int(meta.get("commit_count") or 1),
        "subtree_sha": str(meta.get("subtree_sha") or ""),
        "commit_sha": str(meta.get("commit_sha") or ""),
        "t_start": meta.get("t_start"),
        "t_end": meta.get("t_end"),
        "sessions": sessions_cnt,
        "invocations": invocations_cnt,
        "script_call_count": sc_calls,
        "exit2_count": exit2_cnt,
        "exit1_count": exit1_cnt,
        "post_fix_errors": post_fix_errors,
        "exit2_error_rate": exit2_rate,
        "broken_drawer_count": broken_drawer_cnt,
        "script_p50_ms": p50_ms,
        "uptake_rate": uptake_rate,
        "r1_total": r1_tot,
        "r1_pass": r1_pass,
        "r1_pass_rate": r1_pass_rate,
    }


def classify_skill_version_evolution(
    before_metrics: Mapping[str, Any] | None,
    current_metrics: Mapping[str, Any],
    *,
    min_sessions: int = 5,
) -> tuple[str, dict[str, Any]]:
    """Deterministically classify `vN-1 -> vN` version evolution status (`improved` / `regressed` / `observing` / `baseline`)."""
    cur_sessions = max(int(current_metrics.get("sessions") or 0), int(current_metrics.get("invocations") or 0))
    cur_exit2_cnt = int(current_metrics.get("exit2_count") or 0)
    cur_post_errors = int(
        current_metrics.get("post_fix_errors")
        if current_metrics.get("post_fix_errors") is not None
        else cur_exit2_cnt
    )
    cur_exit2_rate = current_metrics.get("exit2_error_rate")
    cur_broken = int(current_metrics.get("broken_drawer_count") or 0)
    cur_p50 = current_metrics.get("script_p50_ms")
    cur_uptake = current_metrics.get("uptake_rate")
    cur_r1 = current_metrics.get("r1_pass_rate")

    if before_metrics is None:
        return "baseline", {
            "exit2_error_rate_delta": None,
            "exit2_count_delta": None,
            "broken_drawer_delta": None,
            "script_p50_ms_delta": None,
            "uptake_rate_delta": None,
            "r1_pass_rate_delta": None,
            "post_fix_errors": cur_post_errors,
            "improved_dimensions": [],
            "regressed_dimensions": [],
        }

    bef_exit2_cnt = int(before_metrics.get("exit2_count") or 0)
    bef_exit2_rate = before_metrics.get("exit2_error_rate")
    bef_broken = int(before_metrics.get("broken_drawer_count") or 0)
    bef_p50 = before_metrics.get("script_p50_ms")
    bef_uptake = before_metrics.get("uptake_rate")
    bef_r1 = before_metrics.get("r1_pass_rate")

    exit2_rate_delta = (
        round(float(cur_exit2_rate) - float(bef_exit2_rate), 4)
        if cur_exit2_rate is not None and bef_exit2_rate is not None
        else None
    )
    exit2_cnt_delta = cur_exit2_cnt - bef_exit2_cnt
    broken_delta = cur_broken - bef_broken
    p50_delta = (
        round(float(cur_p50) - float(bef_p50), 2)
        if cur_p50 is not None and bef_p50 is not None
        else None
    )
    uptake_delta = (
        round(float(cur_uptake) - float(bef_uptake), 4)
        if cur_uptake is not None and bef_uptake is not None
        else None
    )
    r1_delta = (
        round(float(cur_r1) - float(bef_r1), 4)
        if cur_r1 is not None and bef_r1 is not None
        else None
    )

    improved_dims: list[str] = []
    regressed_dims: list[str] = []

    if (exit2_rate_delta is not None and exit2_rate_delta < 0) or exit2_cnt_delta < 0:
        improved_dims.append("exit2_error_rate")
    if cur_exit2_cnt > 0 or (exit2_rate_delta is not None and exit2_rate_delta > 0):
        regressed_dims.append("exit2_error_rate")

    if broken_delta < 0:
        improved_dims.append("broken_drawer_count")
    elif broken_delta > 0:
        regressed_dims.append("broken_drawer_count")

    if p50_delta is not None and p50_delta < 0:
        improved_dims.append("script_p50_ms")
    elif p50_delta is not None and bef_p50 is not None and float(bef_p50) > 0 and p50_delta > max(500.0, float(bef_p50) * 0.5):
        regressed_dims.append("script_p50_ms")

    if uptake_delta is not None and uptake_delta > 0:
        improved_dims.append("uptake_rate")
    elif uptake_delta is not None and uptake_delta < -0.05:
        regressed_dims.append("uptake_rate")

    if r1_delta is not None and r1_delta > 0:
        improved_dims.append("r1_pass_rate")
    elif r1_delta is not None and r1_delta < 0:
        regressed_dims.append("r1_pass_rate")

    delta_summary = {
        "exit2_error_rate_delta": exit2_rate_delta,
        "exit2_count_delta": exit2_cnt_delta,
        "broken_drawer_delta": broken_delta,
        "script_p50_ms_delta": p50_delta,
        "uptake_rate_delta": uptake_delta,
        "r1_pass_rate_delta": r1_delta,
        "post_fix_errors": cur_post_errors,
        "improved_dimensions": improved_dims,
        "regressed_dimensions": regressed_dims,
    }

    # Regressed check takes priority even on small post-fix sample if errors rebounded or R1 regressed
    has_r1_regression = r1_delta is not None and r1_delta < 0
    has_broken_regression = broken_delta > 0
    if cur_post_errors > 0 or cur_exit2_cnt > 0 or has_r1_regression or has_broken_regression:
        return "regressed", delta_summary

    if cur_sessions < min_sessions:
        return "observing", delta_summary

    if improved_dims or (cur_post_errors == 0 and cur_broken == 0):
        return "improved", delta_summary

    return "observing", delta_summary


def compute_skill_version_evolution(
    report: Mapping[str, Any] | None = None,
    *,
    skills_repo: Path | None = None,
    usage_jsonl: Path | None = None,
    warehouse_db: Path | None = None,
    clean_dir: Path | None = None,
    raw_dir: Path | None = None,
    skill_names: Sequence[str] | None = None,
    min_sessions: int = 5,
) -> list[dict[str, Any]]:
    """Compute per-skill Version Evolution Table (`skill_version_evolution`) comparing `vN-1` vs `vN`."""
    rep = report if isinstance(report, Mapping) else {}
    inferred_skills: list[str] = list(skill_names or [])
    if not inferred_skills and isinstance(rep, Mapping):
        for detail in rep.get("skill_details") or []:
            if isinstance(detail, Mapping) and detail.get("skill") and not detail.get("is_ghost"):
                inferred_skills.append(str(detail["skill"]))
        for s10 in rep.get("S10_skill_roi_ranking") or []:
            if isinstance(s10, Mapping) and s10.get("skill"):
                inferred_skills.append(str(s10["skill"]))

    histories = resolve_skill_version_history(
        skills_repo,
        skill_names=inferred_skills if skill_names is not None else None,
    )
    if not histories:
        return []

    win_start = _parse_iso_timestamp(rep.get("window_start"))
    win_end = _parse_iso_timestamp(rep.get("window_end"))
    buckets = _collect_telemetry_into_version_buckets(
        histories,
        usage_jsonl=usage_jsonl,
        warehouse_db=warehouse_db,
        clean_dir=clean_dir,
        raw_dir=raw_dir,
        report=rep,
        window_start=None,
        window_end=win_end,
    )

    default_window_cst = str(rep.get("window_cst") or "30d")
    default_window_start = rep.get("window_start") or (win_start.isoformat() if win_start else "1970-01-01T00:00:00+08:00")
    default_window_end = rep.get("window_end") or (win_end.isoformat() if win_end else datetime.now(CST).isoformat(timespec="seconds"))
    default_source_as_of = rep.get("source_as_of") or default_window_end

    rows: list[dict[str, Any]] = []
    for sk_name, ver_entries in sorted(histories.items()):
        if not ver_entries:
            continue
        sk_buckets = buckets.get(sk_name) or {}
        summarized_versions: list[dict[str, Any]] = []
        observed_stamps: list[datetime] = []
        for v_entry in ver_entries:
            sv = str(v_entry["skill_version"])
            bkt = sk_buckets.get(sv) or _new_version_bucket(v_entry)
            observed_stamps.extend(bkt["observed_stamps"])
            summarized_versions.append(_summarize_version_bucket(bkt))

        current_ver_obj = summarized_versions[-1]
        before_ver_obj = summarized_versions[-2] if len(summarized_versions) >= 2 else None
        # If there are multiple historical versions and vN-1 had few events (e.g. a quick metadata/plugin.json bump)
        # while earlier pre-fix versions hold the telemetry history, aggregate prior versions into the Before baseline.
        if len(summarized_versions) >= 3 and before_ver_obj is not None:
            prior_versions = summarized_versions[:-1]
            if before_ver_obj["sessions"] < min_sessions and any(
                pv["sessions"] > 0 or pv["script_call_count"] > 0 or pv["r1_total"] > 0 for pv in prior_versions[:-1]
            ):
                agg_sessions = sum(pv["sessions"] for pv in prior_versions)
                agg_invocations = sum(pv["invocations"] for pv in prior_versions)
                agg_sc_calls = sum(pv["script_call_count"] for pv in prior_versions)
                agg_exit2 = sum(pv["exit2_count"] for pv in prior_versions)
                agg_exit1 = sum(pv["exit1_count"] for pv in prior_versions)
                agg_r1_tot = sum(pv["r1_total"] for pv in prior_versions)
                agg_r1_pass = sum(pv["r1_pass"] for pv in prior_versions)
                all_prior_durs = [
                    d
                    for v_e in ver_entries[:-1]
                    for d in (sk_buckets.get(str(v_e["skill_version"]), {}).get("script_durations_ms") or [])
                ]
                uptakes = [pv["uptake_rate"] for pv in prior_versions if pv["uptake_rate"] is not None]
                before_ver_obj = {
                    **before_ver_obj,
                    "t_start": prior_versions[0]["t_start"],
                    "sessions": agg_sessions,
                    "invocations": agg_invocations,
                    "script_call_count": agg_sc_calls,
                    "exit2_count": agg_exit2,
                    "exit1_count": agg_exit1,
                    "post_fix_errors": agg_exit2,
                    "exit2_error_rate": round(agg_exit2 / agg_sc_calls, 4) if agg_sc_calls > 0 else (0.0 if agg_sessions > 0 else None),
                    "broken_drawer_count": max(pv["broken_drawer_count"] for pv in prior_versions),
                    "script_p50_ms": _percentile(all_prior_durs, 50),
                    "uptake_rate": round(sum(uptakes) / len(uptakes), 4) if uptakes else None,
                    "r1_total": agg_r1_tot,
                    "r1_pass": agg_r1_pass,
                    "r1_pass_rate": round(agg_r1_pass / agg_r1_tot, 4) if agg_r1_tot > 0 else None,
                }
            elif before_ver_obj["r1_total"] == 0 and any(pv["r1_total"] > 0 for pv in prior_versions[:-1]):
                agg_r1_tot = sum(pv["r1_total"] for pv in prior_versions)
                agg_r1_pass = sum(pv["r1_pass"] for pv in prior_versions)
                before_ver_obj = {
                    **before_ver_obj,
                    "r1_total": agg_r1_tot,
                    "r1_pass": agg_r1_pass,
                    "r1_pass_rate": round(agg_r1_pass / agg_r1_tot, 4) if agg_r1_tot > 0 else None,
                }

        status, delta_summary = classify_skill_version_evolution(
            before_ver_obj,
            current_ver_obj,
            min_sessions=min_sessions,
        )
        total_samples = (
            int(current_ver_obj["sessions"])
            + (int(before_ver_obj["sessions"]) if before_ver_obj is not None else 0)
            + int(current_ver_obj["script_call_count"])
            + (int(before_ver_obj["script_call_count"]) if before_ver_obj is not None else 0)
        )
        latest_stamp = max(observed_stamps).date().isoformat() if observed_stamps else default_source_as_of
        cov_status = "healthy" if total_samples > 0 else (str(rep.get("coverage_status") or "healthy") if rep.get("coverage_status") in _COVERAGE else "unknown")

        rows.append(
            {
                "window_cst": default_window_cst,
                "window_start": current_ver_obj.get("t_start") or default_window_start,
                "window_end": default_window_end,
                "source_as_of": latest_stamp,
                "sample_size": max(1, total_samples) if cov_status == "healthy" else total_samples,
                "coverage_status": cov_status,
                "estimated": False,
                "skill": sk_name,
                "semver": current_ver_obj["semver"],
                "plugin_version": current_ver_obj["plugin_version"],
                "skill_version": current_ver_obj["skill_version"],
                "combined_version": current_ver_obj["combined_version"],
                "subtree_sha": current_ver_obj["subtree_sha"],
                "commit_count": current_ver_obj["commit_count"],
                "status": status,
                "status_label": _STATUS_LABELS_ZH[status],
                "before_version": before_ver_obj,
                "current_version": current_ver_obj,
                "delta": delta_summary,
                "versions": summarized_versions[-5:],
            }
        )

    status_rank = {"regressed": 0, "improved": 1, "observing": 2, "baseline": 3}
    rows.sort(
        key=lambda r: (
            status_rank.get(r["status"], 9),
            -int((r.get("current_version") or {}).get("sessions") or 0),
            -int(r.get("commit_count") or 0),
            r["skill"],
        )
    )
    return rows



def _validate_optional_metric_sections(report: dict[str, Any], problems: list[str]) -> None:
    """Validate optional observed metric sections without changing the report."""
    required = {
        "reference_hits": {"reference_path": True},
        "script_latency": {"duration_ms": True, "p95_ms": True},
        "eval_effect": {"interception": True, "escape": True},
        "skill_details": {"skill": True, "scope": True, "references": True, "scripts": True, "eval_cases": True},
        "skill_version_evolution": {
            "skill": True,
            "semver": True,
            "skill_version": True,
            "status": True,
            "current_version": True,
        },
    }
    for section_name, field_map in required.items():
        fields = tuple(field_map)
        if section_name not in report:
            continue
        section = report[section_name]
        if not isinstance(section, list):
            problems.append(f"optional metric section {section_name} must be a list")
            continue
        for index, item in enumerate(section):
            if not isinstance(item, dict):
                problems.append(f"optional metric section {section_name}[{index}] must be an object")
                continue
            missing = [field for field in fields if field not in item]
            if missing:
                problems.append(
                    f"optional metric section {section_name}[{index}] missing: {', '.join(missing)}"
                )
                continue
            if section_name == "skill_version_evolution":
                status_val = str(item.get("status") or "").strip()
                if status_val not in _VERSION_EVOLUTION_STATUSES:
                    problems.append(
                        f"optional metric section skill_version_evolution[{index}].status invalid: {status_val}"
                    )
                if not isinstance(item.get("current_version"), dict):
                    problems.append(
                        f"optional metric section skill_version_evolution[{index}].current_version must be an object"
                    )
                if item.get("before_version") is not None and not isinstance(item.get("before_version"), dict):
                    problems.append(
                        f"optional metric section skill_version_evolution[{index}].before_version must be an object or null"
                    )
            if section_name == "skill_details":
                for list_key in ("references", "scripts", "eval_cases"):
                    if not isinstance(item.get(list_key), list):
                        problems.append(
                            f"optional metric section skill_details[{index}].{list_key} must be a list"
                        )
                if "is_ghost" in item and not isinstance(item.get("is_ghost"), bool):
                    problems.append(
                        f"optional metric section skill_details[{index}].is_ghost must be a bool"
                    )
                for num_key in (
                    "bundle_kb",
                    "refs_kb",
                    "refs_tokens_est",
                    "unpracticed_rate",
                    "unhit_refs_count",
                    "unhit_refs_ratio",
                ):
                    val = item.get(num_key)
                    if val is not None and (isinstance(val, bool) or not isinstance(val, (int, float))):
                        problems.append(
                            f"optional metric section skill_details[{index}].{num_key} must be numeric or null"
                        )
                for sc_idx, sc_item in enumerate(item.get("scripts") or []):
                    if not isinstance(sc_item, dict):
                        continue
                    rel_sc = str(sc_item.get("rel_path") or "")
                    if (
                        "__pycache__" in rel_sc
                        or rel_sc.endswith((".pyc", "/__init__.py"))
                        or "/data/" in rel_sc
                    ):
                        problems.append(
                            f"optional metric section skill_details[{index}].scripts[{sc_idx}] contains invalid script path: {rel_sc}"
                        )
                for ev_idx, ev_item in enumerate(item.get("eval_cases") or []):
                    if not isinstance(ev_item, dict):
                        continue
                    ev_id = str(ev_item.get("id") or "").strip()
                    ev_title = str(ev_item.get("title") or "").strip()
                    if ev_id and ev_title == ev_id:
                        problems.append(
                            f"optional metric section skill_details[{index}].eval_cases[{ev_idx}] must have human-readable title != id ({ev_id})"
                        )



def build_snapshot(
    report: dict[str, Any],
    daily: list[dict[str, Any]],
    *,
    errors: list[str] | None = None,
    skills_repo: Path | None = None,
    usage_jsonl: Path | None = None,
    warehouse_db: Path | None = None,
    clean_dir: Path | None = None,
    raw_dir: Path | None = None,
) -> dict[str, Any]:
    """Validate producer shape while preserving its values, nulls and estimates."""
    problems = list(errors or [])
    _validate_optional_metric_sections(report, problems)
    if any(field not in report for field in _META):
        problems.append("missing root observation metadata")
    for key, kind in _SECTION_TYPES.items():
        section = report.get(key)
        if not isinstance(section, kind):
            problems.append(f"missing/invalid canonical section: {key}")
            continue
        for population in section if kind is list else [section]:
            if not isinstance(population, dict) or any(field not in population for field in _META):
                problems.append(f"missing population metadata: {key}")
    sample = report.get("sample_size")
    if not isinstance(sample, int) or isinstance(sample, bool) or sample < 0:
        sample = 0
        problems.append("missing/invalid observed sample_size")
    coverage = report.get("coverage_status", "unknown")
    if coverage not in _COVERAGE:
        coverage = "unknown"
        problems.append("invalid coverage_status")
    if report.get("ok") is not True:
        problems.append("producer did not return ok=true")
    if coverage == "healthy" and (sample == 0 or not report.get("source_as_of") or not report.get("window_start") or not report.get("window_end")):
        problems.append("healthy producer has no observed sample/freshness/window")
    payload = {
        "schema_version": 1,
        "generated_at": datetime.now(timezone.utc)  # noqa: UP017 - hook Python 3.9
        .isoformat(timespec="seconds").replace("+00:00", "Z"),
        **{key: report.get(key) for key in _META},
        "window_cst": report.get("window_cst") or "unknown",
        "sample_size": sample,
        "coverage_status": "error" if problems else coverage,
        "diagnostics": report,
        "skills_daily": daily,
    }
    if isinstance(report.get("skill_details"), list):
        payload["skill_details"] = report["skill_details"]
    if isinstance(report.get("skill_version_evolution"), list):
        payload["skill_version_evolution"] = report["skill_version_evolution"]
    elif report.get("ok") is True and "skill_version_evolution" not in report:
        has_explicit_evo_sources = any(
            x is not None for x in (skills_repo, usage_jsonl, warehouse_db, clean_dir, raw_dir)
        )
        eff_skills_repo = skills_repo
        if eff_skills_repo is None and not os.environ.get("PYTEST_CURRENT_TEST"):
            candidate_repo = Path(os.environ.get("USER_SKILLS_REPO", str(_DEFAULT_SKILLS_REPO))).expanduser()
            if candidate_repo.is_dir():
                eff_skills_repo = candidate_repo
        eff_usage = usage_jsonl
        if eff_usage is None and not os.environ.get("PYTEST_CURRENT_TEST") and _DEFAULT_USAGE_JSONL.is_file():
            eff_usage = _DEFAULT_USAGE_JSONL
        eff_wh = warehouse_db
        if eff_wh is None and not os.environ.get("PYTEST_CURRENT_TEST") and config.WAREHOUSE_DB.is_file():
            eff_wh = config.WAREHOUSE_DB
        eff_clean = clean_dir
        if eff_clean is None and not os.environ.get("PYTEST_CURRENT_TEST") and config.CLEAN_DIR.is_dir():
            eff_clean = config.CLEAN_DIR
        eff_raw = raw_dir
        if eff_raw is None and not os.environ.get("PYTEST_CURRENT_TEST") and config.RAW_DIR.is_dir():
            eff_raw = config.RAW_DIR
        if has_explicit_evo_sources or eff_skills_repo is not None:
            computed_evo = compute_skill_version_evolution(
                report,
                skills_repo=eff_skills_repo,
                usage_jsonl=eff_usage,
                warehouse_db=eff_wh,
                clean_dir=eff_clean,
                raw_dir=eff_raw,
            )
            payload["skill_version_evolution"] = computed_evo
            if has_explicit_evo_sources:
                report["skill_version_evolution"] = computed_evo
        else:
            payload["skill_version_evolution"] = []
    if problems:
        payload["errors"] = problems
    return payload


def _daily_window(start: str, end: str) -> dict[str, str]:
    def cst_timestamp(value: str) -> datetime:
        stamp = datetime.fromisoformat(value.replace("Z", "+00:00"))  # noqa: FURB162 - hook Python 3.9
        if stamp.tzinfo is None:
            stamp = stamp.replace(tzinfo=CST)
        return stamp.astimezone(CST)

    lower, upper = cst_timestamp(start), cst_timestamp(end)
    # The canonical producer's timestamp interval is upper-exclusive. The L4
    # query is day-grained and inclusive; do not admit next-day midnight's day.
    if ("T" in end or " " in end) and (upper.hour, upper.minute, upper.second, upper.microsecond) == (0, 0, 0, 0):
        upper -= timedelta(days=1)
    if lower.date() > upper.date():
        raise ValueError("producer window has no complete CST day")
    return {"day_from": lower.date().isoformat(), "day_to": upper.date().isoformat()}


def _mirror_to_icloud(payload: dict[str, Any], filename: str, sync_dir: Path | None) -> None:
    resolved = resolve_icloud_sync_dir(sync_dir)
    if resolved is None:
        return
    destination_dir = resolved / "jobs" / "aidata-digest"
    destination_dir.mkdir(parents=True, exist_ok=True)
    destination = destination_dir / filename
    tmp: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", dir=destination_dir,
            prefix=f".{filename}.", delete=False,
        ) as handle:
            tmp = Path(handle.name)
            json.dump(payload, handle, ensure_ascii=False, indent=2, allow_nan=False)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        tmp.replace(destination)
        directory = os.open(destination_dir, os.O_RDONLY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if tmp is not None:
            tmp.unlink(missing_ok=True)


def write_snapshot(
    output: Path, report_path: Path, *,
    query_runner: Callable[..., tuple[list, list[str]]] | None = None,
    producer_exit_code: int = 0,
    icloud_sync_dir: Path | None = None,
    skills_repo: Path | None = None,
    usage_jsonl: Path | None = None,
    warehouse_db: Path | None = None,
    clean_dir: Path | None = None,
    raw_dir: Path | None = None,
) -> dict[str, Any]:
    """Capture the real report and query grain, then atomically replace output."""
    errors: list[str] = [f"retro producer exited {producer_exit_code}"] if producer_exit_code else []
    try:
        report = json.loads(report_path.read_text(encoding="utf-8"))
        if not isinstance(report, dict):
            raise TypeError("retro report must be an object")
    except (OSError, ValueError, TypeError) as exc:
        report = {}
        errors.append(f"retro producer report unavailable: {type(exc).__name__}")
    daily: list[dict[str, Any]] = []
    # Only query the producer's explicit observed window. No all-time data
    # labelled 7d, and no generated-at timestamp substituted for source freshness.
    start, end = report.get("window_start"), report.get("window_end")
    if isinstance(start, str) and isinstance(end, str):
        try:
            rows, columns = (query_runner or serve.run_query)("skills/daily", _daily_window(start, end))
            if not {"day", "source", "skill", "n", "sessions"}.issubset(columns):
                raise ValueError("skills/daily grain is missing")
            for values in rows:
                if len(values) != len(columns):
                    raise ValueError("skills/daily row does not match columns")
                row = dict(zip(columns, values))
                n = row["n"]
                if not isinstance(n, int) or isinstance(n, bool) or n < 0:
                    raise ValueError("skills/daily count is not an observed nonnegative integer")
                daily.append({
                    **row, "window_cst": "1d", "window_start": row["day"], "window_end": row["day"],
                    "source_as_of": row["day"], "sample_size": n,
                    "coverage_status": "healthy" if n > 0 else "unknown", "estimated": False,
                })
        except Exception as exc:  # noqa: BLE001 - preserve the producer report on query failure
            daily = []
            errors.append(f"skills/daily unavailable: {type(exc).__name__}")
    payload = build_snapshot(
        report,
        daily,
        errors=errors,
        skills_repo=skills_repo,
        usage_jsonl=usage_jsonl,
        warehouse_db=warehouse_db,
        clean_dir=clean_dir,
        raw_dir=raw_dir,
    )
    if not report:
        payload["coverage_status"] = "missing"
    output.parent.mkdir(parents=True, exist_ok=True)
    tmp: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=output.parent, prefix=output.name + ".", delete=False) as handle:
            tmp = Path(handle.name)
            json.dump(payload, handle, ensure_ascii=False, indent=2, allow_nan=False)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        tmp.replace(output)
        directory = os.open(output.parent, os.O_RDONLY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if tmp is not None:
            tmp.unlink(missing_ok=True)
    _mirror_to_icloud(payload, output.name, icloud_sync_dir)
    return payload


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--producer-exit-code", type=int, default=0)
    args = parser.parse_args(argv)
    payload = write_snapshot(args.output, args.report, producer_exit_code=args.producer_exit_code)
    return 1 if payload.get("errors") else 0


if __name__ == "__main__":
    raise SystemExit(main())
