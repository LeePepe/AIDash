"""Verify the post-merge TestFlight release contract without uploading."""

import os
import re
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve()
while not (ROOT / ".github/workflows/testflight.yml").is_file():
    if ROOT == ROOT.parent:
        raise RuntimeError("TestFlight workflow not found")
    ROOT = ROOT.parent
WORKFLOW = ROOT / ".github/workflows/testflight.yml"


def extract_step(workflow: str, step_id: str) -> str:
    id_marker = f"\n        id: {step_id}\n"
    if workflow.count(id_marker) != 1:
        raise AssertionError(f"expected exactly one step with id {step_id}")
    id_offset = workflow.index(id_marker)
    step_start = workflow.rfind("\n      - name:", 0, id_offset)
    step_end = workflow.find("\n      - name:", id_offset)
    if step_start < 0 or step_end < 0:
        raise AssertionError(f"could not isolate step with id {step_id}")
    return workflow[step_start:step_end]


def extract_classifier(workflow: str) -> str:
    gate_step = extract_step(workflow, "gate")
    matches = re.findall(
        r"^[ \t]*# CLASSIFIER-BEGIN\s*$\n(.*?)^[ \t]*# CLASSIFIER-END\s*$",
        gate_step,
        re.MULTILINE | re.DOTALL,
    )
    if len(matches) != 1:
        raise AssertionError("expected exactly one production classifier block")
    return textwrap.dedent(matches[0])


def isolated_git_environment() -> dict:
    environment = os.environ.copy()
    for name in list(environment):
        if name.startswith("GIT_"):
            environment.pop(name)
    return environment


class TestFlightReleaseTests(unittest.TestCase):
    def setUp(self):
        self.workflow = WORKFLOW.read_text(encoding="utf-8")
        self.triggers = self.workflow.split("\non:\n", 1)[1].split(
            "\nconcurrency:", 1
        )[0]
        self.release = self.workflow.split("\n  release:\n", 1)[1]

    def test_entrypoints_and_exact_candidate_are_pinned(self):
        self.assertRegex(self.triggers, r"(?m)^  push:\n    branches: \[main\]$")
        self.assertRegex(self.triggers, r"(?m)^  workflow_dispatch:$")
        force = self.triggers.split("      force:\n", 1)[1]
        self.assertIn("        type: boolean", force)
        self.assertIn("        default: false", force)
        self.assertIn('CANDIDATE="$EVENT_SHA"', self.release)
        self.assertIn("EVENT_SHA: ${{ github.sha }}", self.release)
        self.assertNotIn("workflow_run", self.workflow)
        self.assertNotIn("head_sha", self.workflow)

    def test_checkout_and_job_safety_contract(self):
        self.assertEqual(self.workflow.count("\n  release:\n"), 1)
        self.assertIn("runs-on: [self-hosted, aidash-mac]", self.release)
        self.assertIn("permissions:\n  contents: write", self.workflow)
        self.assertIn("group: testflight", self.workflow)
        self.assertIn("cancel-in-progress: false", self.workflow)
        self.assertIn("ref: ${{ steps.candidate.outputs.sha }}", self.release)
        self.assertIn("fetch-depth: 0", self.release)
        self.assertIn("persist-credentials: false", self.release)
        self.assertIn(
            'git merge-base --is-ancestor "$CANDIDATE_SHA" '
            "refs/remotes/origin/main",
            self.release,
        )

    def test_marker_moves_only_after_upload_with_a_lease(self):
        upload = self.release.index("- name: fastlane ios beta")
        marker = self.release.index("- name: Compare-and-swap last-released marker")
        cleanup = self.release.index("- name: Cleanup and summarize")
        self.assertLess(upload, marker)
        self.assertLess(marker, cleanup)
        self.assertIn("if: steps.upload.outcome == 'success'", self.release)
        self.assertIn('LEASE="${MARKER_REF}:${EXPECTED_MARKER}"', self.release)
        self.assertIn('git push --force-with-lease="$LEASE"', self.release)
        self.assertNotIn("git tag -f", self.release)
        self.assertIn("if: always()", self.release)
        self.assertIn("MARKER_OUTCOME: ${{ steps.marker.outcome }}", self.release)
        self.assertNotIn("steps.marker.outputs.moved", self.release)

    def test_force_scope_and_marker_fail_closed_rules(self):
        self.assertIn(
            'if [ "$MARKER_OID" = "$CANDIDATE_SHA" ]; then', self.release
        )
        self.assertIn(
            'if [ "$EVENT_NAME" != "workflow_dispatch" ] || '
            '[ "$FORCE" != "true" ]; then',
            self.release,
        )
        self.assertIn(
            'if [ "$RELEVANT" != "true" ] && [ "$FORCE" != "true" ]; then',
            self.release,
        )
        self.assertIn(
            'git merge-base --is-ancestor "$MARKER_OID" "$CANDIDATE_SHA"',
            self.release,
        )

    def test_secrets_are_scoped_to_release_steps(self):
        preflight = self.release.split("- name: Verify API key secrets", 1)[0]
        self.assertNotIn("secrets.", preflight)
        self.assertIn("ASC_KEY_ID: ${{ secrets.ASC_KEY_ID }}", self.release)
        self.assertIn(
            "KEYCHAIN_PASSWORD: ${{ secrets.KEYCHAIN_PASSWORD }}", self.release
        )
        marker = self.release.split(
            "- name: Compare-and-swap last-released marker", 1
        )[1]
        self.assertIn("GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}", marker)

    def test_keychain_is_unlock_only_and_always_relocked(self):
        self.assertIn("security unlock-keychain", self.release)
        self.assertIn("security lock-keychain", self.release)
        self.assertNotIn("security set-keychain-settings", self.release)
        self.assertNotIn("security list-keychains", self.release)
        self.assertNotIn("security set-key-partition-list", self.release)
        cleanup = self.release.split("- name: Cleanup and summarize", 1)[1]
        self.assertIn("if: always()", cleanup)
        self.assertIn('if [ "$KEYCHAIN_ATTEMPTED" = "true" ]; then', cleanup)
        self.assertIn("Release succeeded; cleanup reported a warning", cleanup)
        self.assertIn('echo "- Force: \\`${FORCE:-false}\\`"', cleanup)

    def test_classifier_executes_the_exact_production_block(self):
        classifier = extract_classifier(self.workflow)
        patterns_match = re.search(
            r'case "\$path" in\s*\n\s*(.*?)\)', classifier, re.DOTALL
        )
        self.assertIsNotNone(patterns_match)
        patterns = patterns_match.group(1).strip().split("|")
        self.assertEqual(len(patterns), 7)
        included = [pattern.replace("*", "fixture") for pattern in patterns]
        excluded = [
            "docs/testflight-handoff.md",
            "specs/007-release-workflow/spec.md",
            ".github/workflows/build.yml",
            "scripts/ci/check.py",
            "CLI/Sources/main.swift",
            "aidata/README.md",
        ]
        cases = [(path, True) for path in included]
        cases.extend((path, False) for path in excluded)
        for path, expected in cases:
            with self.subTest(path=path), tempfile.TemporaryDirectory() as tmp:
                repo = Path(tmp)
                git_environment = isolated_git_environment()
                subprocess.run(
                    ["git", "init", "-q"],
                    cwd=repo,
                    env=git_environment,
                    check=True,
                )
                subprocess.run(
                    ["git", "config", "user.email", "test@example.invalid"],
                    cwd=repo,
                    env=git_environment,
                    check=True,
                )
                subprocess.run(
                    ["git", "config", "user.name", "Test"],
                    cwd=repo,
                    env=git_environment,
                    check=True,
                )
                subprocess.run(
                    ["git", "commit", "--allow-empty", "-qm", "base"],
                    cwd=repo,
                    env=git_environment,
                    check=True,
                )
                base = subprocess.check_output(
                    ["git", "rev-parse", "HEAD"],
                    cwd=repo,
                    env=git_environment,
                    text=True,
                ).strip()
                changed = repo / path
                changed.parent.mkdir(parents=True, exist_ok=True)
                changed.write_text("fixture\n", encoding="utf-8")
                subprocess.run(
                    ["git", "add", path],
                    cwd=repo,
                    env=git_environment,
                    check=True,
                )
                subprocess.run(
                    ["git", "commit", "-qm", "change"],
                    cwd=repo,
                    env=git_environment,
                    check=True,
                )
                candidate = subprocess.check_output(
                    ["git", "rev-parse", "HEAD"],
                    cwd=repo,
                    env=git_environment,
                    text=True,
                ).strip()
                output = repo / "output"
                script = "set -euo pipefail\n" + classifier
                subprocess.run(
                    ["bash", "-c", script],
                    cwd=repo,
                    env={
                        "PATH": "/usr/bin:/bin",
                        "BASE_SHA": base,
                        "CANDIDATE_SHA": candidate,
                        "GITHUB_OUTPUT": str(output),
                    },
                    check=True,
                )
                self.assertEqual(
                    output.read_text(encoding="utf-8").strip(),
                    f"relevant={'true' if expected else 'false'}",
                )

    def test_classifier_markers_are_unambiguous(self):
        self.assertEqual(self.workflow.count("# CLASSIFIER-BEGIN"), 1)
        self.assertEqual(self.workflow.count("# CLASSIFIER-END"), 1)
        self.assertTrue(extract_classifier(self.workflow).strip())


if __name__ == "__main__":
    unittest.main()
