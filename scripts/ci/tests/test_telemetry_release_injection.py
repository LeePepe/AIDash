"""Prove TestFlight telemetry injection is path-only, private, and self-cleaning."""
from pathlib import Path
import json
import os
import shlex
import stat
import subprocess
import textwrap
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
        if os.path.lexists(self.config):
            self.config.unlink()
        harness = self.scratch / "fastlane_release_harness.rb"
        if harness.exists():
            harness.unlink()
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

    def run_release(self, force_failure=False, env_overrides=None):
        harness = self.scratch / "fastlane_release_harness.rb"
        harness.write_text(
            textwrap.dedent(
                """
                require "json"

                $lanes = {}
                $build_options = nil

                def default_platform(*) end
                def desc(*) end
                def platform(*)
                  yield
                end
                def lane(name, &block)
                  $lanes[name] = block
                end
                def private_lane(name, &block)
                  $lanes[name] = block
                end
                def app_store_connect_api_key(**)
                  :key
                end
                def sh(*) end
                def latest_testflight_build_number(**)
                  41
                end
                def get_provisioning_profile(**)
                  "neutral-profile"
                end
                def build_app(**options)
                  $build_options = options
                  raise "forced build failure" if ENV["FORCE_RELEASE_FAILURE"] == "1"
                end
                def upload_to_testflight(**) end
                def distribute_to_internal_groups(**) end

                module UI
                  def self.message(*) end
                  def self.user_error!(message)
                    raise message
                  end
                end

                load ARGV.fetch(0)
                begin
                  $lanes.fetch(:beta).call
                  status = 0
                  error_message = nil
                rescue => error
                  status = 23
                  error_message = error.message
                end

                xcargs = $build_options&.fetch(:xcargs, nil)
                puts JSON.generate({status: status, xcargs: xcargs, error: error_message})
                exit status
                """
            ),
            encoding="utf-8",
        )
        env = {
            **self.env,
            "AIDASH_DEVELOPMENT_TEAM": "NEUTRALTEAM",
            "ASC_KEY_ID": "neutral-key",
            "ASC_ISSUER_ID": "neutral-issuer",
            "ASC_KEY_P8_BASE64": "bmV1dHJhbA==",
            "TELEMETRY_XCCONFIG_PATH": str(self.config),
            "FORCE_RELEASE_FAILURE": "1" if force_failure else "0",
        }
        for key, value in (env_overrides or {}).items():
            if value is None:
                env.pop(key, None)
            else:
                env[key] = value
        return subprocess.run(
            ["ruby", str(harness), str(FASTFILE)],
            cwd=ROOT / "fastlane",
            env=env,
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

    def test_actual_release_path_is_path_only_private_and_self_cleaning(self):
        for force_failure in (False, True):
            with self.subTest(force_failure=force_failure):
                created = self.run_helper("create")
                self.assertEqual(created.returncode, 0, created.stderr)
                self.assertEqual(stat.S_IMODE(self.config.stat().st_mode), 0o600)

                release = self.run_release(force_failure=force_failure)
                self.assertEqual(
                    release.returncode,
                    23 if force_failure else 0,
                    release.stdout + release.stderr,
                )
                self.assert_no_sentinel(release)
                payload = json.loads(release.stdout)
                self.assertEqual(payload["status"], 23 if force_failure else 0)
                self.assertEqual(
                    shlex.split(payload["xcargs"])[:2],
                    ["-xcconfig", str(self.config)],
                )
                self.assertFalse(self.config.exists())

    def test_actual_release_path_cleans_up_after_wrong_mode(self):
        created = self.run_helper("create")
        self.assertEqual(created.returncode, 0, created.stderr)
        self.config.chmod(0o644)

        release = self.run_release()

        self.assertEqual(release.returncode, 23, release.stdout + release.stderr)
        self.assert_no_sentinel(release)
        self.assertIn("private runner-temp file", release.stdout)
        self.assertFalse(self.config.exists())

    def test_actual_release_path_cleans_up_after_preflight_failure(self):
        created = self.run_helper("create")
        self.assertEqual(created.returncode, 0, created.stderr)

        release = self.run_release(env_overrides={"ASC_KEY_ID": None})

        self.assertEqual(release.returncode, 23, release.stdout + release.stderr)
        self.assert_no_sentinel(release)
        self.assertFalse(self.config.exists())

    def test_actual_release_path_cleans_up_after_file_stat_failure(self):
        created = self.run_helper("create")
        self.assertEqual(created.returncode, 0, created.stderr)
        self.config.unlink()
        self.config.symlink_to(self.scratch / "missing.xcconfig")

        release = self.run_release()

        self.assertEqual(release.returncode, 23, release.stdout + release.stderr)
        self.assert_no_sentinel(release)
        self.assertFalse(os.path.lexists(self.config))

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
