"""Pure receipt consistency checks; this module is not an R0 supervisor runtime.

Version 1 uses lowercase, full 40-character Git SHA-1 object IDs. Source,
policy and expectation-source identities pin whole repository snapshots using
repository_id/source_sha/source_tree; no moving refs or authority lookup exist.
The companion schema describes the closed receipt and trusted-input shapes.
JSON integer tokens (not floats/bools), unique object keys and standard numeric
tokens are additionally required at the decoding boundary.

Callers must independently supply trusted ``expected`` and ``current`` mappings;
neither may be derived from receipt claims, candidate artifacts or environment.
``expected`` has the receipt's binding fields plus nonempty ``required_checks``;
``current`` has freshly observed ``pr`` and ``execution`` bindings. This helper
cannot establish that a snapshot is fresh: a future trusted publisher must
re-observe immediately before publication.

A copied or fabricated receipt can match perfectly. ``matches`` means structural
and binding consistency ONLY, not authenticated provenance, authorization to
publish, successful real execution, or certification. There is no I/O, candidate
loading/execution, exception authority or check publication here.
"""

from __future__ import annotations

import json
import re
from collections.abc import Mapping
from typing import NamedTuple


class ValidationIssue(NamedTuple):
    code: str
    path: str


class ValidationResult(NamedTuple):
    """Consistency-only result, with the first deterministic, payload-free issue."""

    issues: tuple[ValidationIssue, ...] = ()

    @property
    def matches(self) -> bool:
        return not self.issues


class _Rejected(Exception):
    def __init__(self, code: str, path: str):
        self.issue = ValidationIssue(code, path)


class _DuplicateKey(ValueError):
    pass


class _NonstandardNumber(ValueError):
    pass


def _object(value, fields, path):
    if not isinstance(value, Mapping):
        raise _Rejected("invalid_type", path)
    for field in fields:
        if field not in value:
            raise _Rejected("missing_field", f"{path}.{field}")
    if set(value) != set(fields):
        # Do not return an untrusted key as part of a diagnostic.
        raise _Rejected("unknown_field", path)


def _positive_integer(value, path):
    if type(value) is not int:
        raise _Rejected("invalid_type", path)
    if value <= 0:
        raise _Rejected("invalid_integer", path)


def _oid(value, path):
    if type(value) is not str:
        raise _Rejected("invalid_type", path)
    if re.fullmatch(r"[0-9a-f]{40}", value) is None:
        raise _Rejected("invalid_oid", path)


def _literal(value, allowed, path, code="invalid_value"):
    if type(value) is not type(allowed[0]) or value not in allowed:
        raise _Rejected(code, path)


def _list(value, path):
    if type(value) is not list:
        raise _Rejected("invalid_type", path)


def _check_id(value, path):
    if type(value) is not str:
        raise _Rejected("invalid_type", path)
    if re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,127}", value) is None:
        raise _Rejected("invalid_check_id", path)


def _source(value, path):
    _object(value, ("repository_id", "source_sha", "source_tree"), path)
    _positive_integer(value["repository_id"], f"{path}.repository_id")
    _oid(value["source_sha"], f"{path}.source_sha")
    _oid(value["source_tree"], f"{path}.source_tree")


def _pr(value, path):
    ids = ("base_repository_id", "head_repository_id", "number")
    oids = ("head_sha", "base_sha")
    _object(value, ids + oids, path)
    for field in ids:
        _positive_integer(value[field], f"{path}.{field}")
    for field in oids:
        _oid(value[field], f"{path}.{field}")


def _execution(value, path):
    fields = ("repository_id", "run_id", "run_attempt")
    _object(value, fields, path)
    for field in fields:
        _positive_integer(value[field], f"{path}.{field}")


def _candidate(value, path):
    _object(value, ("tested_sha", "tested_tree", "mode", "merge_parents"), path)
    _oid(value["tested_sha"], f"{path}.tested_sha")
    _oid(value["tested_tree"], f"{path}.tested_tree")
    _literal(value["mode"], ("head", "merge"), f"{path}.mode")
    parents = value["merge_parents"]
    _list(parents, f"{path}.merge_parents")
    if len(parents) != (0 if value["mode"] == "head" else 2):
        raise _Rejected("invalid_merge_parents", f"{path}.merge_parents")
    for index, parent in enumerate(parents):
        _oid(parent, f"{path}.merge_parents[{index}]")


def _bindings(value, path, extra_fields):
    fields = ("schema_version", "roles", "candidates", "pr", "execution",
              "policy", "expectation_source")
    _object(value, fields + extra_fields, path)
    _literal(value["schema_version"], (1,), f"{path}.schema_version",
             "unsupported_version")
    _object(value["roles"], ("r0", "c1", "p1"), f"{path}.roles")
    for role in ("r0", "c1", "p1"):
        _source(value["roles"][role], f"{path}.roles.{role}")
    _object(value["candidates"], ("c1", "p1"), f"{path}.candidates")
    for role in ("c1", "p1"):
        _candidate(value["candidates"][role], f"{path}.candidates.{role}")
    _pr(value["pr"], f"{path}.pr")
    _execution(value["execution"], f"{path}.execution")
    _source(value["policy"], f"{path}.policy")
    _source(value["expectation_source"], f"{path}.expectation_source")


def _candidate_consistency(value, path):
    for role in ("c1", "p1"):
        candidate = value["candidates"][role]
        prefix = f"{path}.candidates.{role}"
        if candidate["mode"] == "head":
            for tested, source in (("tested_sha", "source_sha"),
                                   ("tested_tree", "source_tree")):
                if candidate[tested] != value["roles"][role][source]:
                    raise _Rejected("inconsistent_head", f"{prefix}.{tested}")
        elif candidate["merge_parents"] != [value["pr"]["base_sha"],
                                             value["pr"]["head_sha"]]:
            raise _Rejected("inconsistent_merge_parents", f"{prefix}.merge_parents")


def _required_checks(value, path):
    _list(value, path)
    if not value:
        raise _Rejected("empty_required_checks", path)
    seen = set()
    for index, check_id in enumerate(value):
        item_path = f"{path}[{index}]"
        _check_id(check_id, item_path)
        if check_id in seen:
            raise _Rejected("duplicate_check", item_path)
        seen.add(check_id)


def _checks(value, path):
    _list(value, path)
    if not value:
        raise _Rejected("empty_checks", path)
    seen = set()
    for index, check in enumerate(value):
        prefix = f"{path}[{index}]"
        _object(check, ("id", "status", "conclusion"), prefix)
        _check_id(check["id"], f"{prefix}.id")
        if check["id"] in seen:
            raise _Rejected("duplicate_check", f"{prefix}.id")
        seen.add(check["id"])
        _literal(check["status"], ("completed",), f"{prefix}.status",
                 "check_not_completed")
        _literal(check["conclusion"], ("success",), f"{prefix}.conclusion",
                 "check_not_successful")
    return seen


def _equal(actual, expected, path, code):
    """Compare already validated shapes in fixed field order, never echo values."""
    if isinstance(expected, Mapping):
        for field in sorted(expected):
            _equal(actual[field], expected[field], f"{path}.{field}", code)
    elif actual != expected:
        raise _Rejected(code, path)


def _unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise _DuplicateKey()
        result[key] = value
    return result


def _nonstandard_number(_value):
    raise _NonstandardNumber()


def validate_receipt(
    receipt_json: str, *, expected: Mapping, current: Mapping
) -> ValidationResult:
    """Return consistency only; no authentication or publication permission.

    Malformed data returns one deterministic reason code and field path without
    raw payloads. Unexpected internal exceptions propagate (never a match).
    Inputs are inspected, not mutated. All three inputs are mandatory; current
    must contain the complete observed PR identity and execution bindings.
    """
    try:
        _bindings(expected, "expected", ("required_checks",))
        _required_checks(expected["required_checks"], "expected.required_checks")
        _candidate_consistency(expected, "expected")
        _object(current, ("pr", "execution"), "current")
        _pr(current["pr"], "current.pr")
        _execution(current["execution"], "current.execution")
        for field in ("pr", "execution"):
            _equal(current[field], expected[field], f"current.{field}", "current_drift")

        if type(receipt_json) is not str:
            raise _Rejected("invalid_type", "receipt")
        try:
            receipt = json.loads(receipt_json, object_pairs_hook=_unique_object,
                                 parse_constant=_nonstandard_number)
        except _DuplicateKey:
            raise _Rejected("duplicate_json_key", "receipt") from None
        except _NonstandardNumber:
            raise _Rejected("nonstandard_number", "receipt") from None
        except (ValueError, RecursionError):
            raise _Rejected("invalid_json", "receipt") from None

        _bindings(receipt, "receipt", ("checks", "exceptions"))
        _list(receipt["exceptions"], "receipt.exceptions")
        if receipt["exceptions"]:
            raise _Rejected("exceptions_forbidden", "receipt.exceptions")
        check_ids = _checks(receipt["checks"], "receipt.checks")
        if check_ids != set(expected["required_checks"]):
            raise _Rejected("check_membership_mismatch", "receipt.checks")
        for field in ("schema_version", "roles", "candidates", "pr", "execution",
                      "policy", "expectation_source"):
            _equal(receipt[field], expected[field], f"receipt.{field}", "binding_mismatch")
        # The matching expected bindings already passed candidate consistency.
    except _Rejected as rejection:
        return ValidationResult((rejection.issue,))
    return ValidationResult()
