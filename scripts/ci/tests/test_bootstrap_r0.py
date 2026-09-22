"""Synthetic consistency contract tests; no candidate execution or services.

Expected/current are independently constructed trusted inputs, not extracted
from receipt claims. The small schema interpreter below exercises only this
schema's explicit vocabulary without installing a JSON Schema dependency.
"""

from __future__ import annotations

import ast
import copy
import json
import pathlib
import re
import sys
from types import MappingProxyType

import pytest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))

from bootstrap_r0 import supervisor  # noqa: E402


def oid(character):
    return character * 40


def source(repository_id, sha, tree):
    return {"repository_id": repository_id, "source_sha": oid(sha),
            "source_tree": oid(tree)}


def trusted(mode="head", fork=False):
    expected = {
        "schema_version": 1,
        "roles": {"r0": source(11, "1", "2"), "c1": source(22, "3", "4"),
                  "p1": source(44 if fork else 33, "5", "6")},
        "candidates": {
            "c1": {"tested_sha": oid("3" if mode == "head" else "8"),
                   "tested_tree": oid("4" if mode == "head" else "9"),
                   "mode": mode, "merge_parents": [] if mode == "head"
                   else [oid("7"), oid("5")]},
            "p1": {"tested_sha": oid("5" if mode == "head" else "a"),
                   "tested_tree": oid("6" if mode == "head" else "b"),
                   "mode": mode, "merge_parents": [] if mode == "head"
                   else [oid("7"), oid("5")]},
        },
        "pr": {"base_repository_id": 33, "head_repository_id": 44 if fork else 33,
               "number": 101, "head_sha": oid("5"), "base_sha": oid("7")},
        "execution": {"repository_id": 55, "run_id": 202, "run_attempt": 1},
        "policy": source(66, "c", "d"),
        "expectation_source": source(77, "e", "f"),
        "required_checks": ["build", "unit-tests"],
    }
    current = {
        "pr": {"base_repository_id": 33, "head_repository_id": 44 if fork else 33,
               "number": 101, "head_sha": oid("5"), "base_sha": oid("7")},
        "execution": {"repository_id": 55, "run_id": 202, "run_attempt": 1},
    }
    return expected, current


def receipt(mode="head", fork=False):
    # Build separately from trusted(), including independently pinned merge
    # trees. Never derive the authority from a receipt under test.
    return {
        "schema_version": 1,
        "roles": {
            "r0": {"repository_id": 11, "source_sha": oid("1"), "source_tree": oid("2")},
            "c1": {"repository_id": 22, "source_sha": oid("3"), "source_tree": oid("4")},
            "p1": {"repository_id": 44 if fork else 33,
                   "source_sha": oid("5"), "source_tree": oid("6")},
        },
        "candidates": {
            "c1": {"tested_sha": oid("3") if mode == "head" else oid("8"),
                   "tested_tree": oid("4") if mode == "head" else oid("9"),
                   "mode": mode, "merge_parents": [] if mode == "head"
                   else [oid("7"), oid("5")]},
            "p1": {"tested_sha": oid("5") if mode == "head" else oid("a"),
                   "tested_tree": oid("6") if mode == "head" else oid("b"),
                   "mode": mode, "merge_parents": [] if mode == "head"
                   else [oid("7"), oid("5")]},
        },
        "pr": {"number": 101, "base_sha": oid("7"), "head_sha": oid("5"),
               "base_repository_id": 33, "head_repository_id": 44 if fork else 33},
        "execution": {"run_id": 202, "run_attempt": 1, "repository_id": 55},
        "policy": {"repository_id": 66, "source_sha": oid("c"), "source_tree": oid("d")},
        "expectation_source": {
            "repository_id": 77, "source_sha": oid("e"), "source_tree": oid("f")},
        "checks": [{"id": name, "status": "completed", "conclusion": "success"}
                   for name in ("build", "unit-tests")],
        "exceptions": [],
    }


def evaluate(value, expected=None, current=None, mode="head", fork=False):
    default_expected, default_current = trusted(mode, fork)
    return supervisor.validate_receipt(
        json.dumps(value), expected=default_expected if expected is None else expected,
        current=default_current if current is None else current,
    )


def rejected(result, code=None, path=None):
    assert result.matches is False
    assert len(result.issues) == 1
    if code is not None:
        assert result.issues[0].code == code
    if path is not None:
        assert result.issues[0].path == path


def nodes(value, path=()):
    yield path, value
    if isinstance(value, dict):
        for key, child in value.items():
            yield from nodes(child, path + (key,))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            yield from nodes(child, path + (index,))


def at(value, path):
    for part in path:
        value = value[part]
    return value


def replace(value, path, replacement):
    value = copy.deepcopy(value)
    if not path:
        return replacement
    at(value, path[:-1])[path[-1]] = replacement
    return value


def field_path(root, path):
    return root + "".join(f"[{part}]" if isinstance(part, int) else f".{part}"
                         for part in path)


@pytest.mark.parametrize("mode", ["head", "merge"])
@pytest.mark.parametrize("fork", [False, True])
def test_complete_receipts_match_only_as_consistency(mode, fork):
    value = receipt(mode, fork)
    expected, current = trusted(mode, fork)
    before = copy.deepcopy((value, expected, current))
    result = evaluate(value, expected, current)
    assert result.matches is True
    assert result.issues == ()
    assert (value, expected, current) == before
    # A byte-for-byte fabricated copy matches too; this is NOT authentication.
    assert evaluate(copy.deepcopy(value), expected, current) == result
    if mode == "merge":
        for role in ("c1", "p1"):
            assert value["candidates"][role]["tested_sha"] != value["pr"]["head_sha"]
            assert (value["candidates"][role]["tested_tree"]
                    != value["roles"][role]["source_tree"])


def test_json_key_and_unique_check_order_do_not_matter():
    value = receipt()
    value["checks"].reverse()
    expected, current = trusted()
    expected["required_checks"].reverse()
    assert supervisor.validate_receipt(
        json.dumps(value, sort_keys=True), expected=expected, current=current).matches
    assert evaluate(value, MappingProxyType(expected), MappingProxyType(current)).matches


BINDING_PATHS = [path for path, value in nodes(receipt())
                 if path and path[0] not in ("schema_version", "checks", "exceptions")
                 and type(value) in (int, str) and path[-1] != "mode"]


@pytest.mark.parametrize("mode", ["head", "merge"])
@pytest.mark.parametrize("path", BINDING_PATHS)
def test_each_binding_is_compared_independently(path, mode):
    value = receipt(mode, fork=True)
    old = at(value, path)
    changed = old + 1 if type(old) is int else oid("0")
    rejected(evaluate(replace(value, path, changed), mode=mode, fork=True),
             "binding_mismatch", field_path("receipt", path))


@pytest.mark.parametrize("path", [path for path, value in nodes(trusted()[1])
                                  if type(value) in (int, str)])
def test_every_current_binding_drift_rejects_old_receipt(path):
    expected, current = trusted()
    old = at(current, path)
    changed = old + 1 if type(old) is int else oid("0")
    rejected(evaluate(receipt(), expected, replace(current, path, changed)),
             "current_drift", field_path("current", path))


@pytest.mark.parametrize("left,right", [("r0", "c1"), ("r0", "p1"), ("c1", "p1")])
def test_role_swaps_reject(left, right):
    value = receipt()
    value["roles"][left], value["roles"][right] = value["roles"][right], value["roles"][left]
    rejected(evaluate(value), "binding_mismatch")


@pytest.mark.parametrize("role", ["c1", "p1"])
@pytest.mark.parametrize("parents,code", [
    ([], "invalid_merge_parents"), ([oid("7")], "invalid_merge_parents"),
    ([oid("7"), oid("5"), oid("3")], "invalid_merge_parents"),
    ([oid("5"), oid("7")], "binding_mismatch"),
    ([oid("7"), oid("7")], "binding_mismatch"),
    ([oid("0"), oid("5")], "binding_mismatch"),
])
def test_merge_parents_exact_order_and_membership(role, parents, code):
    value = receipt("merge")
    value["candidates"][role]["merge_parents"] = parents
    rejected(evaluate(value, mode="merge"), code,
             f"receipt.candidates.{role}.merge_parents")


@pytest.mark.parametrize("role", ["c1", "p1"])
@pytest.mark.parametrize("mode", ["head", "merge"])
def test_head_merge_mode_confusion_rejects_even_with_valid_other_shape(role, mode):
    other_mode = "merge" if mode == "head" else "head"
    value = receipt(mode)
    value["candidates"][role] = receipt(other_mode)["candidates"][role]
    rejected(evaluate(value, mode=mode), "binding_mismatch")


@pytest.mark.parametrize("role", ["c1", "p1"])
def test_head_mode_forbids_any_parents(role):
    value = receipt()
    value["candidates"][role]["merge_parents"] = [oid("7"), oid("5")]
    rejected(evaluate(value), "invalid_merge_parents",
             f"receipt.candidates.{role}.merge_parents")


@pytest.mark.parametrize("role", ["c1", "p1"])
@pytest.mark.parametrize("field", ["tested_sha", "tested_tree"])
def test_inconsistent_trusted_head_candidate_cannot_authorize_itself(role, field):
    expected, current = trusted()
    expected["candidates"][role][field] = oid("0")
    value = receipt()
    value["candidates"][role][field] = oid("0")
    rejected(evaluate(value, expected, current), "inconsistent_head",
             f"expected.candidates.{role}.{field}")


@pytest.mark.parametrize("role", ["c1", "p1"])
def test_inconsistent_trusted_merge_parents_reject(role):
    expected, current = trusted("merge")
    expected["candidates"][role]["merge_parents"].reverse()
    rejected(evaluate(receipt("merge"), expected, current),
             "inconsistent_merge_parents", f"expected.candidates.{role}.merge_parents")


@pytest.mark.parametrize("field,bad,code", [
    ("status", value, "check_not_completed")
    for value in ("pending", "queued", "in_progress", "failed", "cancelled", "skipped",
                  "unknown", "timed_out", "neutral", "success", "PASS", "", None, True, 1)
] + [
    ("conclusion", value, "check_not_successful")
    for value in ("failure", "failed", "cancelled", "skipped", "unknown", "pending",
                  "timed_out", "neutral", "action_required", "stale", "PASS", "", None, True, 1)
])
def test_only_completed_success_qualifies(field, bad, code):
    value = receipt()
    value["checks"][1][field] = bad
    rejected(evaluate(value), code, f"receipt.checks[1].{field}")


@pytest.mark.parametrize("kind,code", [
    ("missing", "check_membership_mismatch"), ("extra", "check_membership_mismatch"),
    ("duplicate", "duplicate_check"), ("empty", "empty_checks"),
])
def test_exact_required_check_membership(kind, code):
    value = receipt()
    if kind == "missing":
        value["checks"].pop()
    elif kind == "extra":
        value["checks"].append({"id": "unrequired", "status": "completed", "conclusion": "success"})
    elif kind == "duplicate":
        value["checks"].append(copy.deepcopy(value["checks"][0]))
    else:
        value["checks"] = []
    rejected(evaluate(value), code)


def test_aggregate_pass_cannot_mask_bad_check():
    value = receipt()
    value["checks"][0]["conclusion"] = "failure"
    value["result"] = "PASS"
    rejected(evaluate(value), "unknown_field", "receipt")
    del value["result"]
    rejected(evaluate(value), "check_not_successful", "receipt.checks[0].conclusion")


@pytest.mark.parametrize("required,code", [
    ([], "empty_required_checks"), (["build", "build"], "duplicate_check"),
    ([""], "invalid_check_id"), ([" build"], "invalid_check_id"),
    (["build\n"], "invalid_check_id"), ([True], "invalid_type"),
    (None, "invalid_type"), ("build", "invalid_type"),
])
def test_malformed_required_expectations_never_disable_comparisons(required, code):
    expected, current = trusted()
    expected["required_checks"] = required
    rejected(evaluate(receipt(), expected, current), code)


@pytest.mark.parametrize("exception", [
    {}, "approved", None, True,
    {"approved": True, "signed": True, "expires_at": "2999-01-01T00:00:00Z"},
    {"signature": "apparently-valid", "approver": "owner", "reason": "waiver"},
])
def test_every_exception_rejects(exception):
    value = receipt()
    value["exceptions"] = [exception]
    rejected(evaluate(value), "exceptions_forbidden", "receipt.exceptions")


INPUTS = {"receipt": receipt("merge"), "expected": trusted("merge")[0],
          "current": trusted("merge")[1]}
ALL_NODES = [(root, path) for root, value in INPUTS.items() for path, _ in nodes(value)]
OBJECTS = [(root, path) for root, path in ALL_NODES
           if isinstance(at(INPUTS[root], path), dict)]
REQUIRED_FIELDS = [(root, path, key) for root, path in OBJECTS
                   for key in at(INPUTS[root], path)]


def evaluate_mutated_input(root, value):
    inputs = copy.deepcopy(INPUTS)
    inputs[root] = value
    return supervisor.validate_receipt(json.dumps(inputs["receipt"]),
                                       expected=inputs["expected"], current=inputs["current"])


@pytest.mark.parametrize("root,path,key", REQUIRED_FIELDS)
def test_every_required_field_rejects_when_missing(root, path, key):
    value = copy.deepcopy(INPUTS[root])
    del at(value, path)[key]
    rejected(evaluate_mutated_input(root, value), "missing_field",
             field_path(root, path + (key,)))


@pytest.mark.parametrize("root,path", ALL_NODES)
def test_no_null_at_any_required_node(root, path):
    rejected(evaluate_mutated_input(root, replace(INPUTS[root], path, None)))


@pytest.mark.parametrize("root,path", OBJECTS)
def test_every_object_is_closed_without_leaking_unknown_key(root, path):
    value = copy.deepcopy(INPUTS[root])
    at(value, path)["secret-untrusted-field"] = "secret-untrusted-value"
    result = evaluate_mutated_input(root, value)
    rejected(result, "unknown_field", field_path(root, path))
    assert "secret-untrusted" not in repr(result)


@pytest.mark.parametrize("root,path,bad", [
    (root, path, bad) for root, path in ALL_NODES
    if type(at(INPUTS[root], path)) in (dict, list)
    for bad in ("", 1, True, [], {})
    if type(bad) is not type(at(INPUTS[root], path))
])
def test_invalid_containers(root, path, bad):
    rejected(evaluate_mutated_input(root, replace(INPUTS[root], path, bad)), "invalid_type")


@pytest.mark.parametrize("root,path", [
    (root, path) for root, path in ALL_NODES
    if type(at(INPUTS[root], path)) is int and path[-1] != "schema_version"
])
@pytest.mark.parametrize("bad", [True, False, 0, -1, 1.0, "1", [], {}])
def test_strict_positive_ids_and_attempts(root, path, bad):
    rejected(evaluate_mutated_input(root, replace(INPUTS[root], path, bad)),
             "invalid_integer" if type(bad) is int else "invalid_type", field_path(root, path))


@pytest.mark.parametrize("root,path", [
    (root, path) for root, path in ALL_NODES
    if type(at(INPUTS[root], path)) is str and len(at(INPUTS[root], path)) == 40
])
@pytest.mark.parametrize("bad", ["abc123", "main", "refs/heads/main", "A" * 40,
                                  "g" * 40, "a" * 39, "a" * 64, "a" * 40 + "\n",
                                  " " + "a" * 40, True, 1, [], {}])
def test_canonical_full_oid_at_every_source_tested_and_parent_field(root, path, bad):
    rejected(evaluate_mutated_input(root, replace(INPUTS[root], path, bad)),
             "invalid_oid" if type(bad) is str else "invalid_type", field_path(root, path))


@pytest.mark.parametrize("root", ["receipt", "expected"])
@pytest.mark.parametrize("version", [0, 2, True, 1.0, "1", None])
def test_unknown_or_type_confused_version(root, version):
    rejected(evaluate_mutated_input(root, replace(INPUTS[root], ("schema_version",), version)),
             "unsupported_version", f"{root}.schema_version")


@pytest.mark.parametrize("raw,code", [
    ("", "invalid_json"), ("{", "invalid_json"), ("{} {}", "invalid_json"),
    ('{"x": 1, "x": 2}', "duplicate_json_key"),
    ('{"roles": {"r0": 1, "r0": 2}}', "duplicate_json_key"),
    ('{"x": 1, "\\u0078": 2}', "duplicate_json_key"),
    ('{"x": NaN}', "nonstandard_number"), ('{"x": Infinity}', "nonstandard_number"),
    ('{"x": -Infinity}', "nonstandard_number"),
    ("[" * 2000 + "]" * 2000, "invalid_json"),
    (b"{}", "invalid_type"), ({}, "invalid_type"), (None, "invalid_type"),
])
def test_json_boundary(raw, code):
    expected, current = trusted()
    rejected(supervisor.validate_receipt(raw, expected=expected, current=current), code, "receipt")


@pytest.mark.parametrize("token", ["true", "1.0", "1e0", "1e400"])
def test_integer_wire_tokens_are_not_coerced(token):
    raw = json.dumps(receipt()).replace('"run_attempt": 1', '"run_attempt": ' + token)
    expected, current = trusted()
    rejected(supervisor.validate_receipt(raw, expected=expected, current=current),
             "invalid_type", "receipt.execution.run_attempt")


def test_duplicate_keys_in_otherwise_valid_receipt_reject():
    raw = json.dumps(receipt()).replace('"run_attempt": 1', '"run_attempt": 1, "run_attempt": 1')
    expected, current = trusted()
    rejected(supervisor.validate_receipt(raw, expected=expected, current=current),
             "duplicate_json_key", "receipt")


def test_failure_determinism_and_input_preservation():
    value = receipt()
    value["roles"]["r0"]["source_sha"] = "sensitive-payload"
    value["execution"]["run_id"] = 999
    expected, current = trusted()
    before = copy.deepcopy((value, expected, current))
    first = evaluate(value, expected, current)
    second = supervisor.validate_receipt(json.dumps(value, sort_keys=True),
                                         expected=expected, current=current)
    rejected(first, "invalid_oid", "receipt.roles.r0.source_sha")
    assert first == second
    assert "sensitive-payload" not in repr(first)
    assert (value, expected, current) == before


def test_unexpected_internal_failure_never_becomes_a_match(monkeypatch):
    def fail(*_args):
        raise RuntimeError("synthetic internal failure")

    monkeypatch.setattr(supervisor, "_bindings", fail)
    with pytest.raises(RuntimeError, match="synthetic internal failure"):
        evaluate(receipt())


def test_module_has_no_io_or_import_time_work():
    tree = ast.parse(pathlib.Path(supervisor.__file__).read_text())
    imports = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imports.update(alias.name for alias in node.names)
        elif isinstance(node, ast.ImportFrom):
            imports.add(node.module)
    assert imports == {"__future__", "json", "re", "collections.abc", "typing"}
    # No module-level statements that could launch candidate work or read state.
    assert all(isinstance(node, (ast.Import, ast.ImportFrom, ast.FunctionDef, ast.ClassDef))
               or (isinstance(node, ast.Expr) and isinstance(node.value, ast.Constant)
                   and isinstance(node.value.value, str)) for node in tree.body)


@pytest.fixture(scope="module")
def schema():
    return json.loads(pathlib.Path(supervisor.__file__).with_name("receipt.schema.json").read_text())


def schema_accepts(value, rule, document):
    """Interpret this schema's vocabulary, including its strict-token contract.

    Not a general JSON Schema engine. Unsupported keywords fail the test instead
    of silently accepting a newly added constraint that this oracle cannot test.
    Cross-input equalities deliberately remain the production validator's job.
    """
    supported = {"$schema", "$defs", "$ref", "$comment", "title", "description", "type",
                 "const", "enum", "minimum", "minLength", "maxLength", "pattern",
                 "required", "properties", "additionalProperties", "items", "minItems",
                 "maxItems", "uniqueItems", "oneOf"}
    assert not set(rule) - supported
    if "$ref" in rule:
        assert rule["$ref"].startswith("#/$defs/")
        return schema_accepts(value, document["$defs"][rule["$ref"].split("/")[-1]], document)
    types = {"object": dict, "array": list, "string": str, "integer": int}
    if "type" in rule and type(value) is not types[rule["type"]]:
        return False
    if "const" in rule and (type(value) is not type(rule["const"]) or value != rule["const"]):
        return False
    if "enum" in rule and value not in rule["enum"]:
        return False
    if "minimum" in rule and value < rule["minimum"]:
        return False
    if isinstance(value, str):
        if not rule.get("minLength", 0) <= len(value) <= rule.get("maxLength", float("inf")):
            return False
        if "pattern" in rule and re.search(rule["pattern"], value) is None:
            return False
    if isinstance(value, dict):
        if not set(rule.get("required", [])) <= set(value):
            return False
        properties = rule.get("properties", {})
        if rule.get("additionalProperties") is False and not set(value) <= set(properties):
            return False
        if any(not schema_accepts(child, properties[key], document)
               for key, child in value.items() if key in properties):
            return False
    if isinstance(value, list):
        if not rule.get("minItems", 0) <= len(value) <= rule.get("maxItems", float("inf")):
            return False
        if rule.get("uniqueItems") and any(item in value[:index] for index, item in enumerate(value)):
            return False
        if "items" in rule and any(not schema_accepts(item, rule["items"], document) for item in value):
            return False
    if "oneOf" in rule:
        return sum(schema_accepts(value, option, document) for option in rule["oneOf"]) == 1
    return True


@pytest.mark.parametrize("mode", ["head", "merge"])
def test_schema_and_code_accept_complete_inputs(schema, mode):
    expected, current = trusted(mode, fork=True)
    assert schema_accepts(receipt(mode, fork=True), schema, schema)
    assert schema_accepts(expected, schema["$defs"]["expected"], schema)
    assert schema_accepts(current, schema["$defs"]["current"], schema)
    assert evaluate(receipt(mode, fork=True), expected, current).matches


@pytest.mark.parametrize("root,path,key", REQUIRED_FIELDS)
def test_schema_and_code_reject_every_missing_field(schema, root, path, key):
    value = copy.deepcopy(INPUTS[root])
    del at(value, path)[key]
    rule = schema if root == "receipt" else schema["$defs"][root]
    assert not schema_accepts(value, rule, schema)
    rejected(evaluate_mutated_input(root, value), "missing_field")


@pytest.mark.parametrize("root,path", ALL_NODES)
def test_schema_and_code_reject_nulls(schema, root, path):
    value = replace(INPUTS[root], path, None)
    rule = schema if root == "receipt" else schema["$defs"][root]
    assert not schema_accepts(value, rule, schema)
    rejected(evaluate_mutated_input(root, value))


@pytest.mark.parametrize("root,path", OBJECTS)
def test_schema_and_code_reject_unknown_fields(schema, root, path):
    value = copy.deepcopy(INPUTS[root])
    at(value, path)["unknown"] = True
    rule = schema if root == "receipt" else schema["$defs"][root]
    assert not schema_accepts(value, rule, schema)
    rejected(evaluate_mutated_input(root, value), "unknown_field")


@pytest.mark.parametrize("path,bad", [
    (("schema_version",), 2), (("schema_version",), True),
    (("execution", "run_attempt"), 1.0), (("execution", "run_id"), False),
    (("roles", "r0", "source_sha"), "a" * 40 + "\n"),
    (("candidates", "c1", "mode"), "HEAD"),
    (("candidates", "p1", "merge_parents"), [oid("7")]),
    (("checks", 0, "id"), "build\n"), (("checks", 0, "id"), " build"),
    (("checks", 0, "id"), "x" * 129), (("checks", 0, "status"), "pending"),
    (("checks", 0, "conclusion"), "neutral"), (("exceptions",), [{}]),
    (("checks",), []), (("checks",), [receipt()["checks"][0]] * 2),
])
def test_schema_and_code_agree_on_invalid_values(schema, path, bad):
    value = replace(receipt("merge"), path, bad)
    assert not schema_accepts(value, schema, schema)
    rejected(evaluate(value, mode="merge"))
