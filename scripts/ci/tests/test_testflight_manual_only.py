"""Exercise TestFlight's scheduled/manual main admission and commit gate only."""
from pathlib import Path
import os
import re
import subprocess
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve()
while not (ROOT / ".github/workflows/testflight.yml").is_file():
    if ROOT == ROOT.parent:
        raise RuntimeError("TestFlight workflow not found")
    ROOT = ROOT.parent
WORKFLOW = ROOT / ".github/workflows/testflight.yml"


class TestFlightSourceTests(unittest.TestCase):
    def setUp(self):
        self.workflow = WORKFLOW.read_text(encoding="utf-8")
        self.triggers = self.workflow.split("\non:\n", 1)[1].split("\nconcurrency:", 1)[0]
        self.release = self.workflow.split("\n  release:\n", 1)[1]

    def test_only_schedule_and_manual_dispatch_are_registered(self):
        events = re.findall(r"^  ([a-z_]+):", self.triggers, re.M)
        self.assertEqual(events, ["schedule", "workflow_dispatch"])
        self.assertEqual(
            re.findall(r"- cron: '([^']+)'", self.triggers),
            ["17 8,20 * * *"],
        )

    def admitted(self, event, ref):
        # This guard uses the common == / && / || / () subset of Actions and
        # Bash expressions. Execute the extracted expression with quoted data.
        guards = re.findall(r"^    if: (.+)$", self.release, re.M)
        self.assertEqual(len(guards), 1)
        expression = guards[0].replace("github.event_name", '"$GITHUB_EVENT_NAME"')
        expression = expression.replace("github.ref", '"$GITHUB_REF"')
        result = subprocess.run(
            ["/bin/bash", "-c", "[[ " + expression + " ]]"],
            env={**os.environ, "GITHUB_EVENT_NAME": event, "GITHUB_REF": ref},
            capture_output=True, text=True, timeout=10, check=False,
        )
        self.assertIn(result.returncode, (0, 1), result.stderr)
        return result.returncode == 0

    def test_actual_admission_accepts_schedule_and_dispatch_on_main(self):
        for event in ("schedule", "workflow_dispatch"):
            with self.subTest(event=event):
                self.assertTrue(self.admitted(event, "refs/heads/main"))

    def test_actual_admission_rejects_other_events_and_refs(self):
        for event in (
            "push", "workflow_run", "pull_request", "pull_request_target",
            "repository_dispatch", "unexpected",
        ):
            with self.subTest(event=event):
                self.assertFalse(self.admitted(event, "refs/heads/main"))
        for event in ("schedule", "workflow_dispatch"):
            for ref in ("refs/heads/topic", "refs/tags/main", "refs/pull/1/merge", ""):
                with self.subTest(event=event, ref=ref):
                    self.assertFalse(self.admitted(event, ref))

    def test_existing_inline_release_pipeline_is_preserved(self):
        self.assertNotIn("needs: freshness", self.release)
        self.assertNotIn("  freshness:", self.workflow)
        force = self.triggers.split("      force:\n", 1)[1]
        self.assertIn("        type: boolean", force)
        self.assertIn("        default: false", force)
        self.assertIn("FORCE_INPUT: ${{ github.event.inputs.force }}", self.release)
        self.assertIn("        run: fastlane ios beta\n", self.release)
        self.assertRegex(
            self.release,
            r"- name: fastlane ios beta\n        if: steps.gate.outputs.release == 'true'",
        )

    def test_single_main_checkout_captures_one_candidate_for_success_marker(self):
        self.assertEqual(self.release.count("uses: actions/checkout@"), 1)
        self.assertIn("          ref: main", self.release)
        self.assertIn("          fetch-depth: 0", self.release)
        self.assertEqual(self.release.count("git rev-parse HEAD"), 1)
        self.assertIn('echo "latest=$LATEST" >> "$GITHUB_OUTPUT"', self.release)
        self.assertIn('SHA="${{ steps.gate.outputs.latest }}"', self.release)
        self.assertIn('git tag -f testflight/last-released "$SHA"', self.release)
        self.assertLess(
            self.release.index("run: fastlane ios beta"),
            self.release.index("- name: Move last-released tag"),
        )
        self.assertRegex(
            self.release,
            r"- name: Move last-released tag\n        if: steps.gate.outputs.release == 'true'",
        )
        self.assertIn("    runs-on: [self-hosted, aidash-mac]", self.release)
        self.assertIn("    timeout-minutes: 40", self.release)
        self.assertIn("  group: testflight\n", self.workflow)
        self.assertRegex(self.workflow, r"(?m)^  cancel-in-progress: false(?: |$)")

    def test_telemetry_cleanup_remains_unconditional(self):
        self.assertIn("if: always()", self.release)


class TestFlightCommitGateTests(unittest.TestCase):
    def setUp(self):
        workflow = WORKFLOW.read_text(encoding="utf-8")
        gate = workflow.split("      - name: Decide whether to release\n", 1)[1]
        gate = gate.split("\n      - name:", 1)[0]
        self.script = textwrap.dedent(gate.split("        run: |\n", 1)[1])
        self.assertNotIn("${{", self.script)
        self.scratch = tempfile.TemporaryDirectory()
        self.addCleanup(self.scratch.cleanup)
        self.repo = Path(self.scratch.name)
        # Hooks can export GIT_* for the real checkout; fixtures must never use
        # its index, config, object directory, or working tree.
        self.env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
        self.env.update({
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": os.devnull,
            "GIT_TERMINAL_PROMPT": "0",
        })
        self.git("-c", "init.templateDir=", "init", "-q")
        self.commit()
        self.baseline = self.git("rev-parse", "HEAD")

    def git(self, *args):
        result = subprocess.run(
            ["git", *args], cwd=self.repo, env=self.env,
            capture_output=True, text=True, timeout=10, check=True,
        )
        return result.stdout.strip()

    def commit(self):
        self.git(
            "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
            "commit", "--allow-empty", "-qm", "fixture commit",
        )

    def run_gate(self, event, force=""):
        output = self.repo / "outputs"
        output.write_text("", encoding="utf-8")
        result = subprocess.run(
            ["/bin/bash", "-c", self.script], cwd=self.repo,
            env={
                **self.env, "GITHUB_EVENT_NAME": event, "FORCE_INPUT": force,
                "GITHUB_OUTPUT": str(output), "GITHUB_SHA": self.baseline,
            },
            capture_output=True, text=True, timeout=10, check=False,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return dict(line.split("=", 1) for line in output.read_text().splitlines())

    def test_same_marker_skips_without_force_for_both_sources(self):
        self.git("tag", "testflight/last-released")
        for event in ("schedule", "workflow_dispatch"):
            for force in ("", "false"):
                with self.subTest(event=event, force=force):
                    self.assertEqual(self.run_gate(event, force), {
                        "latest": self.baseline, "release": "false",
                    })

    def test_changed_checkout_releases_and_ignores_older_event_sha(self):
        self.git("tag", "testflight/last-released")
        self.commit()
        candidate = self.git("rev-parse", "HEAD")
        self.assertNotEqual(candidate, self.baseline)
        for event in ("schedule", "workflow_dispatch"):
            with self.subTest(event=event):
                self.assertEqual(self.run_gate(event), {
                    "latest": candidate, "release": "true",
                })
        self.assertEqual(self.git("rev-parse", "testflight/last-released"), self.baseline)

    def test_manual_force_releases_same_marker(self):
        self.git("tag", "testflight/last-released")
        self.assertEqual(self.run_gate("workflow_dispatch", "true"), {
            "latest": self.baseline, "release": "true",
        })

    def test_schedule_cannot_force_even_with_a_true_input(self):
        self.git("tag", "testflight/last-released")
        self.assertEqual(self.run_gate("schedule", "true"), {
            "latest": self.baseline, "release": "false",
        })

    def test_missing_marker_preserves_first_release_behavior(self):
        for event in ("schedule", "workflow_dispatch"):
            with self.subTest(event=event):
                self.assertEqual(self.run_gate(event), {
                    "latest": self.baseline, "release": "true",
                })


if __name__ == "__main__":
    unittest.main()
