#!/usr/bin/env python3
"""aidata — layered AI-usage telemetry platform.

Five subcommands, one per layer, strictly ordered:
    collect    L1  fetch raw data from all sources (read-only), redact, append
    normalize  L2  clean each source independently into clean/<source>.db
    merge      L3  build warehouse.db (fact_*/dim_*) from mergeable sources
    query      L4  run a named query from L4_serve/queries/
    digest     L5  build the AI-usage daily digest (md archive + AIDash push)

Usage:
    ./cli.py collect [--source NAME]
    ./cli.py normalize [--source NAME]
    ./cli.py merge
    ./cli.py query <name> [--param KEY=VALUE ...]
    ./cli.py query --list
    ./cli.py digest [--date YYYY-MM-DD] [--llm] [--aidash]
"""

from __future__ import annotations

import argparse
import importlib
import sys

from config import SOURCES, MANUAL_SOURCES, MERGE_SOURCES

ALL_SOURCES = tuple(SOURCES) + tuple(MANUAL_SOURCES)


def _load_adapter(source: str):
    return importlib.import_module(f"adapters.{source}")


def cmd_collect(args: argparse.Namespace) -> int:
    sources = [args.source] if args.source else list(SOURCES)
    total = 0
    for src in sources:
        try:
            mod = _load_adapter(src)
            n = mod.collect()
            print(f"  [collect] {src:18s} +{n}")
            total += n
        except Exception as exc:  # per-source isolation: one failure ≠ total failure
            print(f"  [collect] {src:18s} ERROR: {exc}", file=sys.stderr)
    print(f"collect: {total} new records across {len(sources)} source(s)")
    return 0


def cmd_normalize(args: argparse.Namespace) -> int:
    sources = [args.source] if args.source else list(SOURCES)
    total = 0
    for src in sources:
        try:
            mod = _load_adapter(src)
            n = mod.normalize()
            print(f"  [normalize] {src:18s} {n} rows")
            total += n
        except Exception as exc:
            print(f"  [normalize] {src:18s} ERROR: {exc}", file=sys.stderr)
    print(f"normalize: {total} rows across {len(sources)} source(s)")
    return 0


def cmd_merge(args: argparse.Namespace) -> int:
    from merge import run_merge

    counts = run_merge()
    for table, n in counts.items():
        print(f"  [merge] {table:16s} {n} rows")
    print(f"merge: warehouse built from {len(MERGE_SOURCES)} source(s)")
    return 0


def cmd_query(args: argparse.Namespace) -> int:
    from serve import list_queries, run_query

    if args.list or not args.name:
        for name in list_queries():
            print(f"  {name}")
        return 0
    params = dict(p.split("=", 1) for p in (args.param or []))
    rows, cols = run_query(args.name, params)
    print(" | ".join(cols))
    print("-" * 60)
    for row in rows:
        print(" | ".join("" if v is None else str(v) for v in row))
    print(f"\n({len(rows)} rows)")
    return 0


def cmd_digest(args: argparse.Namespace) -> int:
    from L5_apps.digest.app import write_digest, default_report_date

    date = args.date or default_report_date()
    path = write_digest(date, use_llm=args.llm, push_aidash=args.aidash)
    mode = "LLM-polished" if args.llm else "template-only"
    sink = " +AIDash(best-effort)" if args.aidash else ""
    print(f"digest written ({mode}){sink}: {path}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(prog="aidata", description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_collect = sub.add_parser("collect", help="L1: fetch raw data")
    p_collect.add_argument("--source", choices=ALL_SOURCES)
    p_collect.set_defaults(func=cmd_collect)

    p_norm = sub.add_parser("normalize", help="L2: clean each source")
    p_norm.add_argument("--source", choices=ALL_SOURCES)
    p_norm.set_defaults(func=cmd_normalize)

    p_merge = sub.add_parser("merge", help="L3: build warehouse")
    p_merge.set_defaults(func=cmd_merge)

    p_query = sub.add_parser("query", help="L4: run a named query")
    p_query.add_argument("name", nargs="?", help="query name, e.g. issues/trend")
    p_query.add_argument("--param", action="append", help="KEY=VALUE bind param")
    p_query.add_argument("--list", action="store_true", help="list available queries")
    p_query.set_defaults(func=cmd_query)

    p_digest = sub.add_parser("digest", help="L5: build AI-usage daily digest")
    p_digest.add_argument("--date", help="report date YYYY-MM-DD (CST); "
                                         "reports on the day before. Default: today CST")
    p_digest.add_argument("--llm", action="store_true",
                          help="opt into LLM polish (bounded text slots only; "
                               "falls back to template on any failure). "
                               "Default: template-only.")
    p_digest.add_argument("--aidash", action="store_true",
                          help="also push the digest to AIDash (best-effort, "
                               "non-fatal: any failure logs a warning and the "
                               "local archive is still written). Default: off.")
    p_digest.set_defaults(func=cmd_digest)

    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
