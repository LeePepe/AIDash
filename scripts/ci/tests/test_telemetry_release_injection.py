"""Prove TestFlight telemetry injection is path-only, private, and self-cleaning."""
from pathlib import Path
import os
import shlex
import stat
import subprocess
import unittest


ROOT = Path(__file__).resolve()
while not (ROOT / ".github/workflows/testflight.yml").is_file():
    if ROOT == ROOT.parent:
        raise RuntimeError("TestFlight workflow not found")
    ROOT = ROOT.parent

HELPER = ROOT / "scripts/ci/telemetry_xcconfig.sh"
WORKFLOW = ROOT / ".github/workflows/testflight.yml"
FASTFILE = ROOT / "fastlane/Fastfile"


class TelemetryReleaseInjectionTests(unittest.TestCase):
    def setUp(self):
        self.scratch = ROOT / ".telemetry-release-test"
        self.scratch.mkdir(exist_ok=True)
        self.config = self.scratch / "release telemetry.xcconfig"
        self.endpoint = "https://example.invalid/container/raw value"
        self.sas = "sig=neutral value&quote='raw'"
        self.env = {
            **os.environ,
            "RUNNER_TEMP": str(self.scratch),
            "TELEMETRY_BLOB_ENDPOINT": self.endpoint,
            "TELEMETRY_BLOB_SAS": self.sas,
        }

    def tearDown(self):
        if self.config.exists():
            self.config.unlink()
        self.scratch.rmdir()

    def run_helper(self, operation):
        return subprocess.run(
            [str(HELPER), operation, str(self.config)],
            cwd=ROOT,
            env=self.env,
            text=True,
            capture_output=True,
            check=False,
        )

    def assert_no_sentinel(self, result):
        output = result.stdout + result.stderr
        for sentinel in (self.endpoint, self.sas):
            self.assertNotIn(sentinel, output)
            self.assertNotIn(shlex.quote(sentinel), output)

    def test_create_is_silent_private_and_cleanup_is_idempotent(self):
        created = self.run_helper("create")
        self.assertEqual(created.returncode, 0, created.stderr)
        self.assert_no_sentinel(created)
        self.assertEqual(stat.S_IMODE(self.config.stat().st_mode), 0o600)

        cleaned = self.run_helper("cleanup")
        self.assertEqual(cleaned.returncode, 0, cleaned.stderr)
        self.assert_no_sentinel(cleaned)
        self.assertFalse(self.config.exists())
        self.assertEqual(self.run_helper("cleanup").returncode, 0)

    def test_forced_release_failure_still_has_silent_cleanup(self):
        created = self.run_helper("create")
        self.assertEqual(created.returncode, 0, created.stderr)

        release = subprocess.run(
            ["bash", "-c", 'printf "%s\\n" "-xcconfig" "$1"; exit 23', "release", str(self.config)],
            cwd=ROOT,
            env=self.env,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(release.returncode, 23)
        self.assertEqual(release.stdout.splitlines(), ["-xcconfig", str(self.config)])
        self.assert_no_sentinel(release)

        cleaned = self.run_helper("cleanup")
        self.assertEqual(cleaned.returncode, 0, cleaned.stderr)
        self.assert_no_sentinel(cleaned)
        self.assertFalse(self.config.exists())

    def test_workflow_uses_protected_names_and_path_only_handoff(self):
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("TELEMETRY_BLOB_ENDPOINT: ${{ secrets.TELEMETRY_BLOB_ENDPOINT }}", workflow)
        self.assertIn("TELEMETRY_BLOB_SAS: ${{ secrets.TELEMETRY_BLOB_SAS }}", workflow)
        self.assertIn("TELEMETRY_XCCONFIG_PATH:", workflow)
        self.assertNotIn("TELEMETRY_BLOB_ENDPOINT: ${{ steps.", workflow)
        self.assertNotIn("TELEMETRY_BLOB_SAS: ${{ steps.", workflow)
        self.assertRegex(workflow, r"(?m)^      - name: Cleanup telemetry xcconfig\n        if: always\(\)")

        fastfile = FASTFILE.read_text(encoding="utf-8")
        self.assertIn('ENV.fetch("TELEMETRY_XCCONFIG_PATH")', fastfile)
        self.assertIn("-xcconfig #{Shellwords.escape(telemetry_xcconfig_path)}", fastfile)
        self.assertNotIn('ENV.fetch("TELEMETRY_BLOB_ENDPOINT")', fastfile)
        self.assertNotIn('ENV.fetch("TELEMETRY_BLOB_SAS")', fastfile)


if __name__ == "__main__":
    unittest.main()
