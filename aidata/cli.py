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
import json
import re
import sys
import uuid
from urllib.parse import urlsplit

from config import (
    MANUAL_SOURCES,
    MERGE_SOURCES,
    PRODUCT_BLOB_CONTAINER_URL,
    PRODUCT_BLOB_PREFIX,
    SOURCES,
)

ALL_SOURCES = tuple(SOURCES) + tuple(MANUAL_SOURCES)
_PRODUCT_BLOB_ERROR_CODE = "product_blob.collection_failed"
_PRODUCT_BLOB_ERROR_MESSAGE = "product blob collection failed"
_AZURE_ACCOUNT_RE = re.compile(r"[a-z0-9]{3,24}")
_AZURE_CONTAINER_RE = re.compile(r"[a-z0-9](?:[a-z0-9-]{1,61}[a-z0-9])?")
_PRODUCT_PREFIX_SEGMENT_RE = re.compile(r"[A-Za-z0-9._-]+", re.ASCII)


def _load_adapter(source: str):
    return importlib.import_module(f"adapters.{source}")


def _write_json(value: dict, stream) -> None:
    print(json.dumps(value, separators=(",", ":")), file=stream)


def _valid_product_blob_selectors(container_url: str, prefix: str) -> bool:
    if not isinstance(container_url, str) or not isinstance(prefix, str):
        return False
    if not container_url and not prefix:
        return True
    if (
        not container_url
        or not prefix
        or "%" in container_url
        or "?" in container_url
        or "#" in container_url
    ):
        return False
    try:
        parsed = urlsplit(container_url)
        port = parsed.port
    except ValueError:
        return False
    if (
        parsed.scheme != "https"
        or parsed.username is not None
        or parsed.password is not None
        or port is not None
        or parsed.query
        or parsed.fragment
    ):
        return False
    host_suffix = ".blob.core.windows.net"
    if not parsed.hostname or not parsed.hostname.endswith(host_suffix):
        return False
    account = parsed.hostname[: -len(host_suffix)]
    if not _AZURE_ACCOUNT_RE.fullmatch(account):
        return False
    if parsed.netloc != parsed.hostname:
        return False
    if not parsed.path.startswith("/") or parsed.path.count("/") != 1:
        return False
    container = parsed.path[1:]
    if (
        not (3 <= len(container) <= 63)
        or "--" in container
        or not _AZURE_CONTAINER_RE.fullmatch(container)
    ):
        return False
    segments = prefix.split("/")
    return bool(
        segments
        and all(
            segment not in {".", ".."}
            and _PRODUCT_PREFIX_SEGMENT_RE.fullmatch(segment)
            for segment in segments
        )
    )


def _validated_product_blob_result(value: object) -> dict:
    if not isinstance(value, dict):
        raise ValueError("invalid adapter result")
    status = value.get("status")
    object_count = value.get("objectCount")
    if type(object_count) is not int:
        raise ValueError("invalid object count")
    if status == "empty":
        if set(value) != {"status", "objectCount"} or object_count != 0:
            raise ValueError("invalid empty result")
        return value
    if status == "completed":
        if (
            set(value) != {"status", "batchId", "objectCount"}
            or object_count <= 0
            or not isinstance(value.get("batchId"), str)
        ):
            raise ValueError("invalid completed result")
        batch_id = value["batchId"]
        if str(uuid.UUID(batch_id)) != batch_id:
            raise ValueError("invalid batch id")
        return value
    raise ValueError("invalid adapter status")


def _product_blob_failure() -> int:
    _write_json(
        {
            "ok": False,
            "error": {
                "code": _PRODUCT_BLOB_ERROR_CODE,
                "message": _PRODUCT_BLOB_ERROR_MESSAGE,
                "field": None,
                "requestId": str(uuid.uuid4()),
            },
        },
        sys.stderr,
    )
    return 1


def cmd_product_blob(extra_args: list[str]) -> int:
    if extra_args or not _valid_product_blob_selectors(
        PRODUCT_BLOB_CONTAINER_URL,
        PRODUCT_BLOB_PREFIX,
    ):
        return _product_blob_failure()
    if not PRODUCT_BLOB_CONTAINER_URL:
        result = {"status": "empty", "objectCount": 0}
    else:
        try:
            adapter = _load_adapter("product_blob")
            result = _validated_product_blob_result(
                adapter.collect(
                    PRODUCT_BLOB_CONTAINER_URL,
                    PRODUCT_BLOB_PREFIX,
                )
            )
        except Exception:
            return _product_blob_failure()
    _write_json(
        {
            "ok": True,
            "data": result,
            "requestId": str(uuid.uuid4()),
        },
        sys.stdout,
    )
    return 0


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
    if len(sys.argv) > 1 and sys.argv[1] == "product-blob":
        return cmd_product_blob(sys.argv[2:])

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
