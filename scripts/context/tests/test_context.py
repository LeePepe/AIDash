"""Focused positive and negative tests for recursive layer context."""

from __future__ import annotations

import importlib.util
import json
import io
import pathlib
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stderr
from types import SimpleNamespace


MODULE_PATH = pathlib.Path(__file__).resolve().parents[1] / "_context.py"
SPEC = importlib.util.spec_from_file_location("layer_context", MODULE_PATH)
assert SPEC and SPEC.loader
layer_context = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = layer_context
SPEC.loader.exec_module(layer_context)


def context_text(data: dict) -> str:
    return f"---\n{json.dumps(data, indent=2)}\n---\n\n# Test context\n"


class Fixture:
    def __init__(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temp.name)
        subprocess.run(["git", "init", "-q"], cwd=self.root, check=True)

    def close(self) -> None:
        self.temp.cleanup()

    def write(self, path: str, content: str = "fixture\n") -> None:
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding="utf-8")

    def context(self, path: str, data: dict) -> None:
        self.write(path, context_text(data))

    def leaf(self, *, path: str = "src/CONTEXT.md", layer: str = "Source",
             parent: str = "CONTEXT.md", scope: list[str] | None = None,
             dependencies: list[str] | None = None,
             dependents: list[str] | None = None, gates: list[dict] | None = None,
             manifest: dict | None = None) -> None:
        data = {
            "schema": 1, "kind": "leaf", "layer": layer, "parent": parent,
            "scope": scope or ["src/**"], "dependencies": dependencies or [],
            "dependents": dependents or [], "red_lines": ["test boundary"],
            "gates": gates or [],
        }
        if manifest:
            data["manifest"] = manifest
        self.context(path, data)

    def root_index(self, routes: list[dict], exclusions: list[dict] | None = None) -> None:
        self.context("CONTEXT.md", {
            "schema": 1, "kind": "index", "routes": routes,
            "exclusions": exclusions or [{"patterns": ["CONTEXT.md"], "reason": "metadata"}],
        })

    def findings(self) -> list:
        return layer_context.audit(self.root)[0]


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
        self.assert_kind("unmapped_path")

    def test_sibling_overlap_is_rejected(self) -> None:
        self.fixture.root_index([
            {"patterns": ["src/**"], "context": "src/CONTEXT.md"},
            {"patterns": ["src/*.py"], "context": "other/CONTEXT.md"},
        ])
        self.fixture.leaf()
        self.fixture.leaf(path="other/CONTEXT.md", layer="Other", scope=["src/*.py"])
        self.fixture.write("src/a.py")
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
            "aidata/tests/test_digest_golden.py": "AidataIntegrationTests",
            "project.yml": "XcodeWorkspace",
            ".github/workflows/build.yml": "RepoInfra",
        }
        for path, layer in expected.items():
            with self.subTest(path=path):
                self.assertEqual(layer_context.resolve(self.root, path).layer, layer)

    def test_repository_audit_classifies_every_file_once(self) -> None:
        findings, counts = layer_context.audit(self.root)
        self.assertEqual([], findings)
        self.assertEqual(counts["total"], counts["leaf"] + counts["excluded"])


if __name__ == "__main__":
    unittest.main()
