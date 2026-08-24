#!/usr/bin/env python3
"""Recursive layer-context resolver and anti-drift audit for AIDash."""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import re
import subprocess
import sys
from dataclasses import dataclass
from typing import Any


ROOT_CONTEXT = "CONTEXT.md"
VALID_GATE_KINDS = {"build", "check", "lint", "test"}
VALID_GATE_MODES = {"both", "ci", "local"}


class ContextError(Exception):
    """A context document is malformed or cannot be resolved."""


@dataclass(frozen=True)
class Finding:
    layer: str
    path: str
    kind: str
    detail: str
    red_lines: tuple[str, ...] = ()

    def emit(self) -> None:
        print(json.dumps({
            "layer": self.layer,
            "path": self.path,
            "kind": self.kind,
            "detail": self.detail,
            "red_lines": list(self.red_lines),
        }, ensure_ascii=False), file=sys.stderr)


@dataclass(frozen=True)
class Resolution:
    path: str
    classification: str
    context: str
    chain: tuple[str, ...]
    layer: str = ""
    reason: str = ""

    def as_dict(self) -> dict[str, Any]:
        return {
            "path": self.path,
            "classification": self.classification,
            "layer": self.layer,
            "context": self.context,
            "chain": list(self.chain),
            "reason": self.reason,
        }


def repo_root(start: pathlib.Path | None = None) -> pathlib.Path:
    command = ["git", "rev-parse", "--show-toplevel"]
    result = subprocess.run(command, cwd=start, text=True, capture_output=True, check=False)
    if result.returncode != 0:
        raise ContextError("not inside a git worktree")
    return pathlib.Path(result.stdout.strip()).resolve()


def normalize_path(root: pathlib.Path, raw: str) -> str:
    candidate = pathlib.Path(raw)
    if candidate.is_absolute():
        try:
            candidate = candidate.resolve().relative_to(root)
        except ValueError as error:
            raise ContextError(f"path is outside repository: {raw}") from error
    normalized = candidate.as_posix()
    while normalized.startswith("./"):
        normalized = normalized[2:]
    if not normalized or normalized == ".":
        raise ContextError("path must name a repository file")
    if normalized == ".." or normalized.startswith("../"):
        raise ContextError(f"path is outside repository: {raw}")
    return normalized


def parse_context(root: pathlib.Path, relative: str) -> dict[str, Any]:
    path = root / relative
    if not path.is_file():
        raise ContextError(f"missing context: {relative}")
    text = path.read_text(encoding="utf-8")
    match = re.match(r"\A---\s*\n(.*?)\n---(?:\s*\n|\Z)", text, re.DOTALL)
    if match is None:
        raise ContextError(f"missing JSON frontmatter: {relative}")
    try:
        data = json.loads(match.group(1))
    except json.JSONDecodeError as error:
        raise ContextError(f"invalid JSON frontmatter in {relative}: {error}") from error
    if not isinstance(data, dict):
        raise ContextError(f"frontmatter must be an object: {relative}")
    data["_context_path"] = relative
    return data


def match_pattern(path: str, pattern: str) -> bool:
    """Match POSIX paths; ** crosses directories and * does not."""
    pieces: list[str] = []
    index = 0
    while index < len(pattern):
        char = pattern[index]
        if char == "*":
            if index + 1 < len(pattern) and pattern[index + 1] == "*":
                if index + 2 < len(pattern) and pattern[index + 2] == "/":
                    pieces.append("(?:.*/)?")
                    index += 3
                else:
                    pieces.append(".*")
                    index += 2
            else:
                pieces.append("[^/]*")
                index += 1
        elif char == "?":
            pieces.append("[^/]")
            index += 1
        else:
            pieces.append(re.escape(char))
            index += 1
    return re.fullmatch("".join(pieces), path) is not None


def relative_to_context(context_path: str, repo_path: str) -> str:
    parent = pathlib.PurePosixPath(context_path).parent
    if str(parent) == ".":
        return repo_path
    prefix = f"{parent.as_posix()}/"
    if not repo_path.startswith(prefix):
        return repo_path
    return repo_path[len(prefix):]


def _matching_entries(data: dict[str, Any], path: str, key: str) -> list[dict[str, Any]]:
    relative = relative_to_context(data["_context_path"], path)
    matched: list[dict[str, Any]] = []
    entries = data.get(key, [])
    if not isinstance(entries, list):
        raise ContextError(f"{key} must be a list: {data['_context_path']}")
    for entry in entries:
        if not isinstance(entry, dict) or not isinstance(entry.get("patterns"), list):
            raise ContextError(f"invalid {key} entry: {data['_context_path']}")
        pattern_fields = ("patterns", "test_paths") if key == "routes" else ("patterns",)
        patterns: list[Any] = []
        for field in pattern_fields:
            value = entry.get(field, [])
            if not isinstance(value, list):
                raise ContextError(f"{field} must be a list: {data['_context_path']}")
            patterns.extend(value)
        if any(isinstance(pattern, str) and match_pattern(relative, pattern)
               for pattern in patterns):
            matched.append(entry)
    return matched


def resolve(root: pathlib.Path, raw_path: str) -> Resolution:
    path = normalize_path(root, raw_path)
    current = ROOT_CONTEXT
    chain: list[str] = []
    visited: set[str] = set()
    while True:
        if current in visited:
            raise ContextError(f"context cycle while resolving {path}: {current}")
        visited.add(current)
        chain.append(current)
        data = parse_context(root, current)
        kind = data.get("kind")
        if kind == "leaf":
            layer = data.get("layer")
            if not isinstance(layer, str) or not layer:
                raise ContextError(f"leaf has no layer: {current}")
            parent = data.get("parent")
            if not isinstance(parent, str) or not parent:
                raise ContextError(f"leaf has no parent: {current}")
            relative = relative_to_context(parent, path)
            ownership = _list_of_strings(data, "scope") + _list_of_strings(data, "test_paths")
            if not any(match_pattern(relative, pattern) for pattern in ownership):
                raise ContextError(f"parent/leaf ownership mismatch at {current}: {path}")
            return Resolution(path, "leaf", current, tuple(chain), layer=layer)
        if kind != "index":
            raise ContextError(f"invalid context kind in {current}: {kind!r}")
        routes = _matching_entries(data, path, "routes")
        exclusions = _matching_entries(data, path, "exclusions")
        if len(routes) + len(exclusions) == 0:
            raise ContextError(f"unmapped path at {current}: {path}")
        if len(routes) + len(exclusions) > 1:
            raise ContextError(f"sibling overlap at {current}: {path}")
        if exclusions:
            reason = exclusions[0].get("reason")
            if not isinstance(reason, str) or not reason.strip():
                raise ContextError(f"exclusion has no reason at {current}: {path}")
            return Resolution(path, "excluded", current, tuple(chain), reason=reason)
        target = routes[0].get("context")
        if not isinstance(target, str) or not target:
            raise ContextError(f"route has no context at {current}: {path}")
        target_path = pathlib.PurePosixPath(current).parent / target
        current = pathlib.PurePosixPath(os.path.normpath(target_path.as_posix())).as_posix()


def discover_contexts(root: pathlib.Path) -> tuple[dict[str, dict[str, Any]], list[Finding]]:
    discovered: dict[str, dict[str, Any]] = {}
    findings: list[Finding] = []
    pending = [ROOT_CONTEXT]
    active: set[str] = set()
    completed: set[str] = set()

    def visit(context_path: str) -> None:
        if context_path in active:
            findings.append(Finding("context", context_path, "cycle", "context route cycle"))
            return
        if context_path in completed:
            return
        active.add(context_path)
        try:
            data = parse_context(root, context_path)
        except ContextError as error:
            findings.append(Finding("context", context_path, "missing_context", str(error)))
            active.remove(context_path)
            completed.add(context_path)
            return
        discovered[context_path] = data
        if data.get("kind") == "index":
            for route in data.get("routes", []):
                if not isinstance(route, dict) or not isinstance(route.get("context"), str):
                    continue
                target = pathlib.PurePosixPath(context_path).parent / route["context"]
                visit(pathlib.PurePosixPath(os.path.normpath(target.as_posix())).as_posix())
        active.remove(context_path)
        completed.add(context_path)

    while pending:
        visit(pending.pop())
    return discovered, findings


def tracked_files(root: pathlib.Path) -> list[str]:
    result = subprocess.run(
        ["git", "ls-files", "--cached", "-z"],
        cwd=root, capture_output=True, check=False,
    )
    if result.returncode != 0:
        raise ContextError(result.stderr.decode("utf-8", errors="replace").strip())
    return sorted(item.decode("utf-8", errors="surrogateescape")
                  for item in result.stdout.split(b"\0") if item)


def _list_of_strings(data: dict[str, Any], field: str) -> list[str]:
    value = data.get(field, [])
    if not isinstance(value, list) or any(not isinstance(item, str) or not item for item in value):
        raise ContextError(f"{field} must be a string list: {data['_context_path']}")
    return value


def _swift_package_dependencies(root: pathlib.Path, manifest: str) -> set[str]:
    text = (root / manifest).read_text(encoding="utf-8")
    return set(re.findall(r'\.package\(path:\s*"\.\./([^"/]+)"', text))


def _project_target_dependencies(root: pathlib.Path, manifest: str, target: str) -> set[str]:
    lines = (root / manifest).read_text(encoding="utf-8").splitlines()
    in_targets = False
    in_target = False
    in_dependencies = False
    dependencies: set[str] = set()
    for line in lines:
        if line == "targets:":
            in_targets = True
            continue
        if not in_targets:
            continue
        target_match = re.match(r"^  ([A-Za-z0-9_-]+):\s*$", line)
        if target_match:
            if in_target:
                break
            in_target = target_match.group(1) == target
            in_dependencies = False
            continue
        if not in_target:
            continue
        if re.match(r"^    dependencies:\s*$", line):
            in_dependencies = True
            continue
        if in_dependencies and re.match(r"^    [A-Za-z]", line):
            in_dependencies = False
        if in_dependencies:
            match = re.match(r"^      - package:\s*([A-Za-z0-9_-]+)\s*$", line)
            if match and match.group(1) != "swift-argument-parser":
                dependencies.add(match.group(1))
    return dependencies


def audit(root: pathlib.Path) -> tuple[list[Finding], dict[str, int]]:
    contexts, findings = discover_contexts(root)
    leaves: dict[str, dict[str, Any]] = {}
    context_to_layer: dict[str, str] = {}

    for path, data in contexts.items():
        kind = data.get("kind")
        if kind not in {"index", "leaf"}:
            findings.append(Finding("context", path, "invalid_context", f"invalid kind: {kind!r}"))
            continue
        if kind == "leaf":
            layer = data.get("layer")
            if not isinstance(layer, str) or not layer:
                findings.append(Finding("context", path, "invalid_leaf", "missing layer ID"))
                continue
            if layer in leaves:
                findings.append(Finding(layer, path, "duplicate_layer_id",
                                        f"also declared by {leaves[layer]['_context_path']}"))
            else:
                leaves[layer] = data
                context_to_layer[path] = layer
        elif any(key in data for key in ("layer", "group", "dependencies", "gates", "red_lines")):
            findings.append(Finding("context", path, "index_contains_leaf_fields",
                                    "index contexts may contain routes and exclusions only"))

    for parent_path, parent in contexts.items():
        if parent.get("kind") != "index":
            continue
        for route in parent.get("routes", []):
            if not isinstance(route, dict) or not isinstance(route.get("context"), str):
                findings.append(Finding("context", parent_path, "invalid_route", "route is malformed"))
                continue
            target = pathlib.PurePosixPath(parent_path).parent / route["context"]
            target_path = pathlib.PurePosixPath(os.path.normpath(target.as_posix())).as_posix()
            child = contexts.get(target_path)
            if child and child.get("kind") == "leaf":
                expected_parent = child.get("parent")
                if expected_parent != parent_path:
                    findings.append(Finding(str(child.get("layer", "context")), target_path,
                                            "parent_leaf_mismatch",
                                            f"parent={expected_parent!r}; routed by {parent_path!r}"))
                if child.get("scope") != route.get("patterns"):
                    findings.append(Finding(str(child.get("layer", "context")), target_path,
                                            "parent_leaf_mismatch",
                                            "leaf scope differs from parent route patterns"))
                if child.get("test_paths", []) != route.get("test_paths", []):
                    findings.append(Finding(str(child.get("layer", "context")), target_path,
                                            "parent_leaf_mismatch",
                                            "leaf test_paths differ from parent route test_paths"))

    for layer, data in leaves.items():
        path = data["_context_path"]
        red_lines: tuple[str, ...] = ()
        try:
            red_lines = tuple(_list_of_strings(data, "red_lines"))
            _list_of_strings(data, "scope")
            _list_of_strings(data, "test_paths")
            dependencies = _list_of_strings(data, "dependencies")
            dependents = _list_of_strings(data, "dependents")
        except ContextError as error:
            findings.append(Finding(layer, path, "invalid_leaf", str(error)))
            continue
        group = data.get("group")
        if group is not None and (not isinstance(group, str) or not group):
            findings.append(Finding(layer, path, "invalid_leaf",
                                    "group must be a non-empty string", red_lines))
        gates = data.get("gates")
        if not isinstance(gates, list):
            findings.append(Finding(layer, path, "invalid_gate", "gates must be a list", red_lines))
            gates = []
        gate_ids: set[str] = set()
        for gate in gates:
            valid = isinstance(gate, dict)
            gate_id = gate.get("id") if valid else None
            gate_kind = gate.get("kind") if valid else None
            command = gate.get("command") if valid else None
            mode = gate.get("mode") if valid else None
            if (not valid or not isinstance(gate_id, str) or not gate_id
                    or gate_id in gate_ids or gate_kind not in VALID_GATE_KINDS
                    or not isinstance(command, list) or not command
                    or any(not isinstance(token, str) or not token for token in command)
                    or mode not in VALID_GATE_MODES):
                findings.append(Finding(layer, path, "invalid_gate", f"invalid gate: {gate!r}", red_lines))
            else:
                gate_ids.add(gate_id)
                placeholders = {token for token in command if token.startswith("{")}
                if placeholders - {"{test_paths}", "{owned_python_paths}"}:
                    findings.append(Finding(layer, path, "invalid_gate",
                                            f"unknown path placeholder: {sorted(placeholders)!r}",
                                            red_lines))
        for dependency in dependencies:
            if dependency not in leaves:
                findings.append(Finding(layer, path, "missing_dependency", dependency, red_lines))
            elif layer not in leaves[dependency].get("dependents", []):
                findings.append(Finding(layer, path, "reciprocal_dependency_drift",
                                        f"{dependency}.dependents omits {layer}", red_lines))
        for dependent in dependents:
            if dependent not in leaves:
                findings.append(Finding(layer, path, "missing_dependency", dependent, red_lines))
            elif layer not in leaves[dependent].get("dependencies", []):
                findings.append(Finding(layer, path, "reciprocal_dependency_drift",
                                        f"{dependent}.dependencies omits {layer}", red_lines))

        manifest = data.get("manifest")
        if manifest is not None:
            if not isinstance(manifest, dict) or manifest.get("kind") not in {
                    "swift-package", "xcodegen-target"} or not isinstance(manifest.get("path"), str):
                findings.append(Finding(layer, path, "invalid_manifest", repr(manifest), red_lines))
            else:
                manifest_path = manifest["path"]
                if not (root / manifest_path).is_file():
                    findings.append(Finding(layer, manifest_path, "missing_manifest", "file does not exist", red_lines))
                else:
                    if manifest["kind"] == "swift-package":
                        actual = _swift_package_dependencies(root, manifest_path)
                    else:
                        target = manifest.get("target")
                        if not isinstance(target, str) or not target:
                            findings.append(Finding(layer, path, "invalid_manifest", "missing target", red_lines))
                            actual = set()
                        else:
                            actual = _project_target_dependencies(root, manifest_path, target)
                    expected = set(manifest.get("local_dependencies", []))
                    if actual != expected:
                        findings.append(Finding(layer, manifest_path, "manifest_dependency_drift",
                                                f"expected={sorted(expected)} actual={sorted(actual)}", red_lines))

    dependency_state: dict[str, int] = {}
    dependency_stack: list[str] = []

    def visit_dependency(layer: str) -> None:
        state = dependency_state.get(layer, 0)
        if state == 2:
            return
        if state == 1:
            start = dependency_stack.index(layer)
            cycle = dependency_stack[start:] + [layer]
            findings.append(Finding(layer, leaves[layer]["_context_path"], "dependency_cycle",
                                    " -> ".join(cycle),
                                    tuple(leaves[layer].get("red_lines", []))))
            return
        dependency_state[layer] = 1
        dependency_stack.append(layer)
        for dependency in leaves[layer].get("dependencies", []):
            if dependency in leaves:
                visit_dependency(dependency)
        dependency_stack.pop()
        dependency_state[layer] = 2

    for layer in leaves:
        visit_dependency(layer)

    counts = {"leaf": 0, "excluded": 0, "total": 0}
    for path in tracked_files(root):
        counts["total"] += 1
        try:
            result = resolve(root, path)
        except ContextError as error:
            kind = "sibling_overlap" if "sibling overlap" in str(error) else "unmapped_path"
            findings.append(Finding("context", path, kind, str(error)))
            continue
        counts[result.classification] += 1
    return findings, counts


def layer_map(root: pathlib.Path) -> dict[str, dict[str, Any]]:
    contexts, findings = discover_contexts(root)
    if findings:
        raise ContextError(findings[0].detail)
    return {data["layer"]: data for data in contexts.values()
            if data.get("kind") == "leaf" and isinstance(data.get("layer"), str)}


def command_audit(args: argparse.Namespace, root: pathlib.Path) -> int:
    findings, counts = audit(root)
    for finding in findings:
        finding.emit()
    summary = {"ok": not findings, "classifications": counts, "findings": len(findings)}
    print(json.dumps(summary, ensure_ascii=False))
    return 0 if not findings else 1


def command_resolve(args: argparse.Namespace, root: pathlib.Path) -> int:
    status = 0
    for raw in args.paths:
        try:
            result = resolve(root, raw)
        except ContextError as error:
            Finding("context", raw, "resolve_failed", str(error)).emit()
            status = 1
            continue
        if args.format == "layer":
            print(result.layer if result.classification == "leaf" else "")
        elif args.format == "context":
            print(result.context)
        else:
            print(json.dumps(result.as_dict(), ensure_ascii=False))
    return status


def command_layers(args: argparse.Namespace, root: pathlib.Path) -> int:
    layers = layer_map(root)
    if getattr(args, "group", None) is not None:
        if args.paths or args.stdin or args.all:
            raise ContextError("--group cannot be combined with paths, --stdin, or --all")
        selected = sorted(name for name, data in layers.items() if data.get("group") == args.group)
        if not selected:
            raise ContextError(f"unknown or empty layer group: {args.group}")
        if args.json:
            print(json.dumps(selected, ensure_ascii=False))
        else:
            for name in selected:
                print(name)
        return 0
    if args.all:
        if args.paths or args.stdin:
            raise ContextError("--all cannot be combined with paths or --stdin")
        if args.json:
            print(json.dumps({name: data["_context_path"] for name, data in sorted(layers.items())},
                             ensure_ascii=False, indent=2))
        else:
            for name in sorted(layers):
                print(name)
        return 0

    raw_paths = list(args.paths)
    if args.stdin:
        raw_paths.extend(line for line in sys.stdin.read().splitlines() if line)
    if not raw_paths:
        raise ContextError("provide one or more paths, --stdin, or --all")

    touched: set[str] = set()
    status = 0
    for raw in raw_paths:
        try:
            result = resolve(root, raw)
        except ContextError as error:
            Finding("context", raw, "resolve_failed", str(error)).emit()
            status = 1
            continue
        if result.classification == "leaf":
            touched.add(result.layer)
    if args.json:
        print(json.dumps(sorted(touched), ensure_ascii=False))
    else:
        for name in sorted(touched):
            print(name)
    return status


def nested_field(data: dict[str, Any], field: str) -> Any:
    value: Any = data
    for part in field.split("."):
        if not isinstance(value, dict) or part not in value:
            raise ContextError(f"unknown field: {field}")
        value = value[part]
    return value


def command_field(args: argparse.Namespace, root: pathlib.Path) -> int:
    layers = layer_map(root)
    if args.layer not in layers:
        raise ContextError(f"unknown layer: {args.layer}")
    value = nested_field(layers[args.layer], args.field)
    if isinstance(value, str):
        print(value)
    else:
        print(json.dumps(value, ensure_ascii=False, indent=2))
    return 0


def command_contexts(args: argparse.Namespace, root: pathlib.Path) -> int:
    for raw in args.paths:
        result = resolve(root, raw)
        if len(args.paths) > 1:
            print(f"{result.path}:")
        for context in result.chain:
            print(context)
    return 0


def command_run(args: argparse.Namespace, root: pathlib.Path) -> int:
    layers = layer_map(root)
    if args.layer not in layers:
        raise ContextError(f"unknown layer: {args.layer}")
    data = layers[args.layer]
    red_lines = tuple(_list_of_strings(data, "red_lines"))
    gates = data.get("gates", [])
    selected = [gate for gate in gates
                if (args.gate is None or gate.get("id") == args.gate)
                and gate.get("mode") in {"both", args.mode}]
    if args.gate is not None and not selected:
        raise ContextError(f"unknown or unavailable {args.mode} gate for {args.layer}: {args.gate}")
    owned_files: list[str] | None = None

    def resolved_owned_files() -> list[str]:
        nonlocal owned_files
        if owned_files is None:
            owned_files = []
            for path in tracked_files(root):
                try:
                    resolution = resolve(root, path)
                except ContextError:
                    continue
                if resolution.classification == "leaf" and resolution.layer == args.layer:
                    owned_files.append(path)
        return owned_files

    def expand_command(command: list[str]) -> list[str]:
        expanded: list[str] = []
        parent = data.get("parent", ROOT_CONTEXT)
        test_patterns = _list_of_strings(data, "test_paths")
        for token in command:
            if token == "{test_paths}":
                expanded.extend(
                    path for path in resolved_owned_files()
                    if path.endswith(".py")
                    and any(match_pattern(relative_to_context(parent, path), pattern)
                            for pattern in test_patterns)
                )
            elif token == "{owned_python_paths}":
                expanded.extend(path for path in resolved_owned_files() if path.endswith(".py"))
            else:
                expanded.append(token)
        return expanded

    for gate in selected:
        command = expand_command(gate["command"])
        print(f"[context/run] {args.layer}:{gate['id']} — {' '.join(command)}", flush=True)
        try:
            result = subprocess.run(command, cwd=root, check=False)
        except OSError as error:
            Finding(args.layer, args.path or data["_context_path"], "gate_execution_failed",
                    f"gate={gate['id']} error={error}", red_lines).emit()
            return 1
        if result.returncode != 0:
            Finding(args.layer, args.path or data["_context_path"], "gate_failed",
                    f"gate={gate['id']} exit={result.returncode}", red_lines).emit()
            return result.returncode or 1
    return 0


def parser_for(command_name: str) -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog=f"scripts/context/{command_name}")
    if command_name == "audit":
        parser.set_defaults(handler=command_audit)
    elif command_name == "resolve":
        parser.add_argument("paths", nargs="+")
        parser.add_argument("--format", choices=("json", "layer", "context"), default="json")
        parser.set_defaults(handler=command_resolve)
    elif command_name == "layers":
        parser.add_argument("paths", nargs="*")
        parser.add_argument("--stdin", action="store_true")
        parser.add_argument("--all", action="store_true")
        parser.add_argument("--group")
        parser.add_argument("--json", action="store_true")
        parser.set_defaults(handler=command_layers)
    elif command_name == "field":
        parser.add_argument("layer")
        parser.add_argument("field")
        parser.set_defaults(handler=command_field)
    elif command_name == "contexts":
        parser.add_argument("paths", nargs="+")
        parser.set_defaults(handler=command_contexts)
    elif command_name == "run":
        parser.add_argument("layer")
        parser.add_argument("--gate")
        parser.add_argument("--mode", choices=("local", "ci"), default="local")
        parser.add_argument("--path")
        parser.set_defaults(handler=command_run)
    else:
        raise ContextError(f"unknown context command: {command_name}")
    return parser


def main() -> int:
    command_name = pathlib.Path(sys.argv[0]).name
    try:
        if command_name == "_context.py":
            if len(sys.argv) < 2:
                raise ContextError("missing context command")
            command_name = sys.argv.pop(1)
        root = repo_root()
        parser = parser_for(command_name)
        args = parser.parse_args()
        return args.handler(args, root)
    except ContextError as error:
        Finding("context", ROOT_CONTEXT, "context_error", str(error)).emit()
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
