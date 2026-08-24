"""Focused positive and negative tests for recursive layer context."""

from __future__ import annotations

import importlib.util
import json
import io
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from types import SimpleNamespace
from unittest import mock


MODULE_PATH = pathlib.Path(__file__).resolve().parents[1] / "_context.py"
SPEC = importlib.util.spec_from_file_location("layer_context", MODULE_PATH)
assert SPEC and SPEC.loader
layer_context = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = layer_context
SPEC.loader.exec_module(layer_context)

GIT_REPOSITORY_ENVIRONMENT_VARIABLES = {
    "GIT_ALTERNATE_OBJECT_DIRECTORIES",
    "GIT_COMMON_DIR",
    "GIT_CONFIG",
    "GIT_CONFIG_COUNT",
    "GIT_CONFIG_PARAMETERS",
    "GIT_DIR",
    "GIT_GRAFT_FILE",
    "GIT_IMPLICIT_WORK_TREE",
    "GIT_INDEX_FILE",
    "GIT_INTERNAL_SUPER_PREFIX",
    "GIT_NO_REPLACE_OBJECTS",
    "GIT_OBJECT_DIRECTORY",
    "GIT_PREFIX",
    "GIT_REPLACE_REF_BASE",
    "GIT_SHALLOW_FILE",
    "GIT_WORK_TREE",
}


def isolated_git_environment() -> dict[str, str]:
    environment = os.environ.copy()
    for name in GIT_REPOSITORY_ENVIRONMENT_VARIABLES:
        environment.pop(name, None)
    for name in tuple(environment):
        if name.startswith(("GIT_CONFIG_KEY_", "GIT_CONFIG_VALUE_")):
            environment.pop(name)
    return environment


def context_text(data: dict) -> str:
    return f"---\n{json.dumps(data, indent=2)}\n---\n\n# Test context\n"


class Fixture:
    def __init__(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temp.name)
        self.git("init", "-q")

    def close(self) -> None:
        self.temp.cleanup()

    def write(self, path: str, content: str = "fixture\n") -> None:
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding="utf-8")

    def git(self, *arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["git", *arguments],
            cwd=self.root,
            env=isolated_git_environment(),
            check=True,
            text=True,
            capture_output=True,
        )

    def context(self, path: str, data: dict) -> None:
        self.write(path, context_text(data))

    def leaf(self, *, path: str = "src/CONTEXT.md", layer: str = "Source",
             parent: str = "CONTEXT.md", scope: list[str] | None = None,
             test_paths: list[str] | None = None,
             dependencies: list[str] | None = None,
             dependents: list[str] | None = None, gates: list[dict] | None = None,
             manifest: dict | None = None) -> None:
        data = {
            "schema": 1, "kind": "leaf", "layer": layer, "parent": parent,
            "scope": ["src/**"] if scope is None else scope,
            "dependencies": dependencies or [],
            "dependents": dependents or [], "red_lines": ["test boundary"],
            "gates": gates or [],
        }
        if test_paths is not None:
            data["test_paths"] = test_paths
        if manifest:
            data["manifest"] = manifest
        self.context(path, data)

    def root_index(self, routes: list[dict], exclusions: list[dict] | None = None) -> None:
        self.context("CONTEXT.md", {
            "schema": 1, "kind": "index", "routes": routes,
            "exclusions": exclusions or [{"patterns": ["CONTEXT.md"], "reason": "metadata"}],
        })

    def audit(self) -> tuple[list, dict[str, int]]:
        with mock.patch.dict(os.environ, isolated_git_environment(), clear=True):
            return layer_context.audit(self.root)

    def findings(self) -> list:
        return self.audit()[0]


class ContextAuditNegativeTests(unittest.TestCase):
    def setUp(self) -> None:
        self.fixture = Fixture()

    def tearDown(self) -> None:
        self.fixture.close()

    def assert_kind(self, expected: str) -> None:
        kinds = {finding.kind for finding in self.fixture.findings()}
        self.assertIn(expected, kinds, kinds)

    def test_unmapped_path_is_rejected(self) -> None:
        self.fixture.root_index([])
        self.fixture.write("orphan.txt")
        self.fixture.git("add", "orphan.txt", "CONTEXT.md")
        self.assert_kind("unmapped_path")

    def test_fixture_git_commands_ignore_outer_index_file(self) -> None:
        with tempfile.TemporaryDirectory() as outer_temp:
            outer_index = pathlib.Path(outer_temp) / "index"
            with mock.patch.dict(os.environ, {"GIT_INDEX_FILE": str(outer_index)}):
                self.fixture.root_index([])
                self.fixture.write("orphan.txt")
                self.fixture.git("add", "orphan.txt", "CONTEXT.md")
                self.fixture.findings()

            self.assertFalse(outer_index.exists())
        staged = self.fixture.git("diff", "--cached", "--name-only").stdout.splitlines()
        self.assertEqual(["CONTEXT.md", "orphan.txt"], staged)

    def test_untracked_path_is_not_audited(self) -> None:
        self.fixture.root_index([])
        self.fixture.git("add", "CONTEXT.md")
        self.fixture.write("arbitrary-untracked.txt")
        findings, counts = self.fixture.audit()
        self.assertFalse(any(finding.path == "arbitrary-untracked.txt" for finding in findings))
        self.assertEqual(1, counts["total"])

    def test_sibling_overlap_is_rejected(self) -> None:
        self.fixture.root_index([
            {"patterns": ["src/**"], "context": "src/CONTEXT.md"},
            {"patterns": ["src/*.py"], "context": "other/CONTEXT.md"},
        ])
        self.fixture.leaf()
        self.fixture.leaf(path="other/CONTEXT.md", layer="Other", scope=["src/*.py"])
        self.fixture.write("src/a.py")
        self.fixture.git("add", "src/a.py")
        self.assert_kind("sibling_overlap")

    def test_test_path_sibling_overlap_is_rejected(self) -> None:
        self.fixture.root_index([
            {"patterns": ["src/**"], "test_paths": ["tests/shared.py"],
             "context": "src/CONTEXT.md"},
            {"patterns": ["other/**"], "test_paths": ["tests/shared.py"],
             "context": "other/CONTEXT.md"},
        ])
        self.fixture.leaf(test_paths=["tests/shared.py"])
        self.fixture.leaf(path="other/CONTEXT.md", layer="Other", scope=["other/**"],
                          test_paths=["tests/shared.py"])
        self.fixture.write("tests/shared.py")
        self.fixture.git("add", "tests/shared.py")
        self.assert_kind("sibling_overlap")

    def test_context_cycle_is_rejected(self) -> None:
        self.fixture.root_index([{"patterns": ["src/**"], "context": "child/CONTEXT.md"}])
        self.fixture.context("child/CONTEXT.md", {
            "schema": 1, "kind": "index",
            "routes": [{"patterns": ["src/**"], "context": "../CONTEXT.md"}],
            "exclusions": [],
        })
        self.fixture.write("src/a.py")
        self.assert_kind("cycle")

    def test_missing_context_is_rejected(self) -> None:
        self.fixture.root_index([{"patterns": ["src/**"], "context": "missing/CONTEXT.md"}])
        self.fixture.write("src/a.py")
        self.assert_kind("missing_context")

    def test_parent_leaf_mismatch_is_rejected(self) -> None:
        self.fixture.root_index([{"patterns": ["src/**"], "context": "src/CONTEXT.md"}])
        self.fixture.leaf(parent="wrong/CONTEXT.md")
        self.fixture.write("src/a.py")
        self.assert_kind("parent_leaf_mismatch")

    def test_parent_leaf_test_paths_mismatch_is_rejected(self) -> None:
        self.fixture.root_index([
            {"patterns": ["src/**"], "test_paths": ["tests/source.py"],
             "context": "src/CONTEXT.md"},
        ])
        self.fixture.leaf(test_paths=["tests/different.py"])
        self.assert_kind("parent_leaf_mismatch")

    def test_duplicate_layer_id_is_rejected(self) -> None:
        self.fixture.root_index([
            {"patterns": ["src/**"], "context": "src/CONTEXT.md"},
            {"patterns": ["other/**"], "context": "other/CONTEXT.md"},
        ])
        self.fixture.leaf()
        self.fixture.leaf(path="other/CONTEXT.md", layer="Source", scope=["other/**"])
        self.assert_kind("duplicate_layer_id")

    def test_invalid_gate_is_rejected(self) -> None:
        self.fixture.root_index([{"patterns": ["src/**"], "context": "src/CONTEXT.md"}])
        self.fixture.leaf(gates=[{"id": "bad", "kind": "magic", "mode": "sometimes", "command": []}])
        self.assert_kind("invalid_gate")

    def test_missing_dependency_is_rejected(self) -> None:
        self.fixture.root_index([{"patterns": ["src/**"], "context": "src/CONTEXT.md"}])
        self.fixture.leaf(dependencies=["Ghost"])
        self.assert_kind("missing_dependency")

    def test_reciprocal_dependency_drift_is_rejected(self) -> None:
        self.fixture.root_index([
            {"patterns": ["src/**"], "context": "src/CONTEXT.md"},
            {"patterns": ["base/**"], "context": "base/CONTEXT.md"},
        ])
        self.fixture.leaf(dependencies=["Base"])
        self.fixture.leaf(path="base/CONTEXT.md", layer="Base", scope=["base/**"])
        self.assert_kind("reciprocal_dependency_drift")

    def test_dependency_cycle_is_rejected(self) -> None:
        self.fixture.root_index([
            {"patterns": ["src/**"], "context": "src/CONTEXT.md"},
            {"patterns": ["base/**"], "context": "base/CONTEXT.md"},
        ])
        self.fixture.leaf(dependencies=["Base"], dependents=["Base"])
        self.fixture.leaf(path="base/CONTEXT.md", layer="Base", scope=["base/**"],
                          dependencies=["Source"], dependents=["Source"])
        self.assert_kind("dependency_cycle")

    def test_package_manifest_dependency_drift_is_rejected(self) -> None:
        self.fixture.root_index([{"patterns": ["src/**"], "context": "src/CONTEXT.md"}])
        self.fixture.write("src/Package.swift", '.package(path: "../Ghost")\n')
        self.fixture.leaf(manifest={
            "kind": "swift-package", "path": "src/Package.swift", "local_dependencies": []
        })
        self.assert_kind("manifest_dependency_drift")

    def test_project_manifest_dependency_drift_is_rejected(self) -> None:
        self.fixture.root_index([{"patterns": ["src/**"], "context": "src/CONTEXT.md"}])
        self.fixture.write("src/project.yml", "targets:\n  App:\n    dependencies:\n      - package: Core\n")
        self.fixture.leaf(manifest={
            "kind": "xcodegen-target", "path": "src/project.yml", "target": "App",
            "local_dependencies": [],
        })
        self.assert_kind("manifest_dependency_drift")

    def test_gate_failure_is_structured_with_red_lines(self) -> None:
        self.fixture.root_index([{"patterns": ["src/**"], "context": "src/CONTEXT.md"}])
        self.fixture.leaf(gates=[{
            "id": "red", "kind": "test", "mode": "local",
            "command": ["python3", "-c", "raise SystemExit(7)"],
        }])
        stderr = io.StringIO()
        args = SimpleNamespace(layer="Source", gate="red", mode="local", path="src/a.py")
        with redirect_stderr(stderr):
            self.assertEqual(7, layer_context.command_run(args, self.fixture.root))
        failure = json.loads(stderr.getvalue())
        self.assertEqual({"layer", "path", "kind", "detail", "red_lines"}, set(failure))
        self.assertEqual("Source", failure["layer"])
        self.assertEqual("src/a.py", failure["path"])
        self.assertEqual("gate_failed", failure["kind"])

    def test_missing_gate_executable_is_structured_without_traceback(self) -> None:
        self.fixture.root_index([{"patterns": ["src/**"], "context": "src/CONTEXT.md"}])
        self.fixture.leaf(gates=[{
            "id": "missing", "kind": "test", "mode": "local",
            "command": ["executable-that-does-not-exist"],
        }])
        stderr = io.StringIO()
        args = SimpleNamespace(layer="Source", gate="missing", mode="local", path="src/a.py")
        with redirect_stderr(stderr):
            self.assertEqual(1, layer_context.command_run(args, self.fixture.root))
        output = stderr.getvalue()
        failure = json.loads(output)
        self.assertEqual("gate_execution_failed", failure["kind"])
        self.assertNotIn("Traceback", output)

    def test_gate_expands_owned_test_and_python_paths(self) -> None:
        self.fixture.root_index([
            {"patterns": ["src/**"], "test_paths": ["tests/source_*.py"],
             "context": "src/CONTEXT.md"},
        ])
        self.fixture.write("src/source.py")
        self.fixture.write("src/notes.txt")
        self.fixture.write("tests/source_one.py")
        self.fixture.write("tests/source_two.py")
        self.fixture.git("add", "src/source.py", "src/notes.txt",
                         "tests/source_one.py", "tests/source_two.py")
        self.fixture.leaf(test_paths=["tests/source_*.py"], gates=[{
            "id": "paths", "kind": "test", "mode": "local",
            "command": ["probe", "{test_paths}", "--python", "{owned_python_paths}"],
        }])
        args = SimpleNamespace(layer="Source", gate="paths", mode="local", path=None)
        owned = ["src/notes.txt", "src/source.py", "tests/source_one.py",
                 "tests/source_two.py"]
        with mock.patch.object(layer_context, "tracked_files", return_value=owned), \
                mock.patch.object(layer_context.subprocess, "run") as run:
            run.return_value.returncode = 0
            self.assertEqual(0, layer_context.command_run(args, self.fixture.root))
        self.assertEqual([
            "probe", "tests/source_one.py", "tests/source_two.py", "--python",
            "src/source.py", "tests/source_one.py", "tests/source_two.py",
        ], run.call_args.args[0])


class NestedLeafOwnershipTests(unittest.TestCase):
    def setUp(self) -> None:
        self.fixture = Fixture()
        self.fixture.root_index([
            {"patterns": ["Packages/**"], "context": "Packages/CONTEXT.md"},
        ])
        self.fixture.context("Packages/CONTEXT.md", {
            "schema": 1,
            "kind": "index",
            "routes": [{
                "patterns": ["Core/**"],
                "test_paths": ["Tests/test_core.py"],
                "context": "Core/CONTEXT.md",
            }],
            "exclusions": [{"patterns": ["CONTEXT.md"], "reason": "metadata"}],
        })
        self.fixture.leaf(
            path="Packages/Core/CONTEXT.md",
            layer="Core",
            parent="Packages/CONTEXT.md",
            scope=["Core/**"],
            test_paths=["Tests/test_core.py"],
        )

    def tearDown(self) -> None:
        self.fixture.close()

    def test_nested_leaf_scope_is_relative_to_parent_index(self) -> None:
        result = layer_context.resolve(self.fixture.root, "Packages/Core/source.py")
        self.assertEqual("Core", result.layer)
        self.assertEqual("Packages/Core/CONTEXT.md", result.context)

    def test_nested_leaf_test_path_is_relative_to_parent_index(self) -> None:
        result = layer_context.resolve(self.fixture.root, "Packages/Tests/test_core.py")
        self.assertEqual("Core", result.layer)
        self.assertEqual("Packages/Core/CONTEXT.md", result.context)


class LayersCommandTests(unittest.TestCase):
    def setUp(self) -> None:
        self.fixture = Fixture()
        self.fixture.root_index([
            {"patterns": ["src/**"], "context": "src/CONTEXT.md"},
            {"patterns": ["docs/**"], "context": "docs/CONTEXT.md"},
        ])
        self.fixture.leaf(layer="ZSource")
        self.fixture.leaf(path="docs/CONTEXT.md", layer="ADocs", scope=["docs/**"])

    def tearDown(self) -> None:
        self.fixture.close()

    def test_positional_paths_emit_sorted_unique_touched_layers(self) -> None:
        args = SimpleNamespace(paths=["src/a.py", "docs/readme.md", "src/b.py"],
                               stdin=False, all=False, json=False)
        stdout = io.StringIO()
        with redirect_stdout(stdout):
            self.assertEqual(0, layer_context.command_layers(args, self.fixture.root))
        self.assertEqual("ADocs\nZSource\n", stdout.getvalue())

    def test_stdin_paths_emit_sorted_unique_touched_layers(self) -> None:
        args = SimpleNamespace(paths=[], stdin=True, all=False, json=False)
        stdout = io.StringIO()
        with mock.patch("sys.stdin", io.StringIO("src/a.py\ndocs/readme.md\nsrc/a.py\n")), \
                redirect_stdout(stdout):
            self.assertEqual(0, layer_context.command_layers(args, self.fixture.root))
        self.assertEqual("ADocs\nZSource\n", stdout.getvalue())

    def test_all_preserves_explicit_full_enumeration(self) -> None:
        args = SimpleNamespace(paths=[], stdin=False, all=True, json=False)
        stdout = io.StringIO()
        with redirect_stdout(stdout):
            self.assertEqual(0, layer_context.command_layers(args, self.fixture.root))
        self.assertEqual("ADocs\nZSource\n", stdout.getvalue())

    def test_group_emits_only_group_members(self) -> None:
        source = layer_context.parse_context(self.fixture.root, "src/CONTEXT.md")
        source["group"] = "product"
        self.fixture.context("src/CONTEXT.md", {
            key: value for key, value in source.items() if key != "_context_path"
        })
        args = SimpleNamespace(paths=[], stdin=False, all=False, group="product", json=False)
        stdout = io.StringIO()
        with redirect_stdout(stdout):
            self.assertEqual(0, layer_context.command_layers(args, self.fixture.root))
        self.assertEqual("ZSource\n", stdout.getvalue())


class RepositoryResolutionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.root = pathlib.Path(__file__).resolve().parents[3]

    def test_representative_paths_resolve_to_expected_leaves(self) -> None:
        expected = {
            "Packages/AIDashCore/Package.swift": "AIDashCore",
            "Packages/DesignKit/Sources/DesignKit/ColorSystem.swift": "DesignKit",
            "Packages/AIDashUI/Sources/AIDashUI/CardRouter.swift": "AIDashUI",
            "Apps/AIDashApp/Sources/AIDashApp.swift": "AIDashApp",
            "CLI/aidash/Sources/AIDashCLI.swift": "aidashCLI",
            "aidata/adapters/raven.py": "AidataL1L2",
            "aidata/schema/warehouse.sql": "AidataL3",
            "aidata/L4_serve/queries/trends.sql": "AidataL4",
            "aidata/L5_apps/digest/app.py": "AidataL5",
            "aidata/scripts/aidata_digest_run.sh": "AidataOps",
            "aidata/tests/test_config_m3.py": "AidataFoundation",
            "aidata/tests/test_raven_cost.py": "AidataL1L2",
            "aidata/tests/test_model_canon.py": "AidataL1L2",
            "aidata/tests/test_warehouse_integrity.py": "AidataL3",
            "aidata/tests/test_query_tiers.py": "AidataL4",
            "aidata/tests/test_digest_golden.py": "AidataL5",
            "aidata/tests/test_cron_installer.py": "AidataOps",
            "aidata/tests/test_cst_day_contract.py": "AidataIntegrationTests",
            "project.yml": "XcodeWorkspace",
            ".github/workflows/build.yml": "RepoInfra",
            "docs/ci-gates.md": "RepoInfra",
        }
        for path, layer in expected.items():
            with self.subTest(path=path):
                self.assertEqual(layer_context.resolve(self.root, path).layer, layer)

    def test_repository_audit_classifies_every_file_once(self) -> None:
        findings, counts = layer_context.audit(self.root)
        self.assertEqual([], findings)
        self.assertEqual(counts["total"], counts["leaf"] + counts["excluded"])

    def test_ci_consumes_declared_required_context_gates(self) -> None:
        workflow = (self.root / ".github/workflows/build.yml").read_text(encoding="utf-8")
        self.assertIn("scripts/context/run RepoInfra --mode ci", workflow)
        for layer in ("AIDashCore", "AIDashUI", "DesignKit", "AIDashApp", "aidashCLI"):
            self.assertIn(f"scripts/context/run {layer} --mode ci", workflow)
        self.assertIn("scripts/context/layers --group aidata", workflow)
        self.assertNotIn("ruff check scripts/ci scripts/context", workflow)


if __name__ == "__main__":
    unittest.main()
