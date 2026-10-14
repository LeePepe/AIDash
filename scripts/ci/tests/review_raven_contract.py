#!/usr/bin/env python3
"""Offline tests: Review home provider routing without credentials, network or GitHub writes."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

CI = Path(__file__).resolve().parents[1]
HELPER = CI / "review-raven.py"
spec = importlib.util.spec_from_file_location("review_raven", HELPER)
raven = importlib.util.module_from_spec(spec)
spec.loader.exec_module(raven)

CONFIG = '''model_provider = "custom-provider"
model = "daily-model-must-not-leak"
approval_policy = "never"
[features]
hooks = true
'''


class RavenRoutingTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.config = Path(self.directory.name) / "config.toml"
        self.config.write_text(CONFIG)

    def command(self, config_text=None, env=None):
        if config_text is not None:
            self.config.write_text(config_text)
        return raven.build_command(
            self.config, "/opt/homebrew/bin/codex",
            ["--output-schema", "schema.json", "-o", "out.json", "synthetic prompt"],
            env,
        )

    def test_provider_neutral_command_construction(self):
        for provider in ("custom-provider", "raven", "openai", "any-provider-name"):
            with self.subTest(provider=provider):
                command = self.command(f'model_provider = "{provider}"\n')
                self.assertEqual(command[:2], ["/opt/homebrew/bin/codex", "exec"])
                self.assertEqual(command[2:], ["--output-schema", "schema.json", "-o", "out.json", "synthetic prompt"])

    def test_missing_or_empty_model_provider_is_rejected(self):
        for invalid in ('approval_policy = "never"\n',
                        'model_provider = ""\n',
                        'model_provider = "   "\n',
                        'model_provider = 123\n'):
            with self.subTest(invalid=invalid):
                with self.assertRaisesRegex(ValueError, "Review Codex configuration must explicitly select a model_provider"):
                    self.command(invalid)

    def test_missing_or_malformed_config_is_sanitized(self):
        self.config.write_text('secret = "fixture-sensitive-invalid')
        with self.assertRaises(ValueError) as error:
            self.command()
        self.assertNotIn("fixture-sensitive", str(error.exception))
        self.config.unlink()
        with self.assertRaises(ValueError):
            self.command()

    def test_no_environment_credential_prerequisite_or_inspection(self):
        class MockNoCredentialReads(dict):
            def __getitem__(self, key):
                raise AssertionError(f"Environment key {key} must not be read")

            def get(self, key, default=None):
                raise AssertionError(f"Environment key {key} must not be inspected")

        # Command construction succeeds without inspecting any environment variables.
        command = self.command(env=MockNoCredentialReads())
        self.assertEqual(command[:2], ["/opt/homebrew/bin/codex", "exec"])

    def test_configuration_is_not_shell_evaluated(self):
        marker = Path(self.directory.name) / "must-not-exist"
        self.command(f'model_provider = "$(touch {marker})"\n')
        self.assertFalse(marker.exists())

    def test_argv_round_trip_keeps_metacharacters_as_data(self):
        marker = Path(self.directory.name) / "never-created"
        arguments = ["--output-schema", "schema with spaces.json", "-o", "out.json",
                     f"prompt 'quoted' $(touch {marker}) `touch {marker}`\n中文"]
        command = raven.build_command(self.config, "/fake codex", arguments)
        self.assertEqual(command[0], "/fake codex")
        self.assertEqual(command[1], "exec")
        self.assertEqual(command[2:], arguments)
        self.assertFalse(marker.exists())

    def test_real_launcher_preserves_exec_arguments_and_review_home(self):
        fake = Path(self.directory.name) / "codex"
        fake.write_text(
            '#!' + sys.executable + '\nimport json,os,sys\n'
            'print(json.dumps({"args":sys.argv[1:],"review_home":os.environ.get("CODEX_HOME")}))\n'
        )
        fake.chmod(0o700)
        review_home = Path(self.directory.name) / "review-home"
        review_home.mkdir()
        (review_home / "config.toml").write_text('model_provider = "isolated-provider"\n')
        env = dict(PATH=os.environ["PATH"], HOME=self.directory.name,
                   CODEX_HOME=str(review_home))
        result = subprocess.run([sys.executable, str(HELPER), str(fake), "--skip-git-repo-check", "fixture"],
                                env=env, capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        output = json.loads(result.stdout)
        self.assertEqual(output["args"], ["exec", "--skip-git-repo-check", "fixture"])
        self.assertEqual(output["review_home"], env["CODEX_HOME"])

    def test_real_launcher_missing_or_empty_codex_home_fails_before_codex(self):
        fake = Path(self.directory.name) / "codex"
        fake.write_text('#!' + sys.executable + '\nimport sys\nsys.exit(0)\n')
        fake.chmod(0o700)
        for bad_home in (None, "", "   "):
            with self.subTest(bad_home=bad_home):
                env = dict(PATH=os.environ["PATH"], HOME=self.directory.name)
                if bad_home is not None:
                    env["CODEX_HOME"] = bad_home
                result = subprocess.run([sys.executable, str(HELPER), str(fake), "fixture"],
                                        env=env, capture_output=True, text=True, timeout=5)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Raven setup failed", result.stderr)

    def test_caller_keeps_isolation_and_uses_raven_launcher(self):
        source = (CI / "codex-review.sh").read_text()
        self.assertIn('python3 "$REPO_ROOT/scripts/ci/review-raven.py" "$CODEX_BIN"', source)
        self.assertIn('CODEX_HOME="${CODEX_REVIEW_HOME:-$HOME/.codex-review}"', source)
        self.assertIn("-c sandbox_mode=read-only", source)
        self.assertIn("-c approval_policy=never", source)
        self.assertNotIn('"$CODEX_BIN" exec', source)

    def run_actual_caller(self, *, override=False, payload_response=None, hang=False,
                          no_review_config=False, malformed_review_config=False):
        """Run the real shell, renderer, provider helper and watchdog; fake only external tools."""
        root = Path(self.directory.name)
        bin_dir = root / "bin"
        bin_dir.mkdir(exist_ok=True)

        daily = root / ".codex"
        daily.mkdir(exist_ok=True)
        (daily / "config.toml").write_text('model_provider = "daily-sentinel-must-not-change"\n')
        (daily / "auth.json").write_text('{"api_key":"daily-auth-file-must-not-be-used"}')

        inherited = root / "inherited daily home"
        inherited.mkdir(exist_ok=True)
        (inherited / "config.toml").write_text('model_provider = "inherited-sentinel-must-not-change"\n')

        default_review = root / ".codex-review"
        default_review.mkdir(exist_ok=True)
        if not no_review_config:
            if malformed_review_config:
                (default_review / "config.toml").write_text('invalid = toml [[[\n')
            else:
                (default_review / "config.toml").write_text('model_provider = "default-review-provider"\n')

        override_review = root / "explicit review home"
        override_review.mkdir(exist_ok=True)
        (override_review / "config.toml").write_text('model_provider = "override-review-provider"\n')

        marker = root / "SHELL_MUST_NOT_RUN"
        payload = f"+ quoted 'text' $(touch {marker}) `touch {marker}` 中文"
        capture = root / "capture.json"
        fake = bin_dir / "codex fixture"

        response_body = payload_response if payload_response is not None else {
            "verdict": "pass",
            "summary": "offline fixture",
            "blockers": [],
            "notes": []
        }

        fake.write_text(
            "#!" + sys.executable + "\nimport json,os,sys,time\nfrom pathlib import Path\n"
            "args=sys.argv[1:]\n"
            "stage=os.environ.get('VS_GATE_STAGE_FILE')\n"
            "Path(os.environ['CAPTURE']).write_text(json.dumps({'args':args,"
            "'home':os.environ.get('CODEX_HOME'),"
            "'stage':Path(stage).read_text() if stage else None,"
            "'stdin':sys.stdin.read()}))\n"
            "if os.environ.get('FIXTURE_HANG'): time.sleep(60)\n"
            "raw_resp = os.environ.get('RESPONSE_BODY')\n"
            "Path(args[args.index('-o')+1]).write_text(raw_resp if raw_resp else '')\n"
        )
        (bin_dir / "git").write_text(
            "#!" + sys.executable + "\nimport os,sys\n"
            "cmd=sys.argv[1]\n"
            "if cmd=='rev-parse': print(os.environ['FIXTURE_REPO'])\n"
            "elif cmd=='diff': print('fixture.md' if '--name-only' in sys.argv else "
            "'diff --git a/fixture.md b/fixture.md\\n'+os.environ['FIXTURE_DIFF'])\n"
            "elif cmd not in ('fetch','cat-file'): sys.exit(1)\n"
        )
        (bin_dir / "gh").write_text("#!/bin/sh\nexit 0\n")
        for binary in (fake, bin_dir / "git", bin_dir / "gh"):
            binary.chmod(0o700)
        env = {
            "PATH": str(bin_dir) + os.pathsep + os.environ["PATH"],
            "HOME": str(root), "CODEX_HOME": str(inherited), "CODEX_BIN": str(fake),
            "PR_NUMBER": "1", "BASE_SHA": "fixture-base", "HEAD_SHA": "fixture-head",
            "BASE_REPO": "fixture/repository", "CAPTURE": str(capture),
            "FIXTURE_REPO": str(CI.parents[1]), "FIXTURE_DIFF": payload,
            "GATE_TIMEOUT_SECONDS": "1" if hang else "30",
            "REVIEW_CLI_TIMEOUT_SECONDS": "1" if hang else "30",
            "RESPONSE_BODY": json.dumps(response_body) if isinstance(response_body, (dict, list)) else str(response_body),
        }
        if override:
            env["CODEX_REVIEW_HOME"] = str(override_review)
        if hang:
            env["FIXTURE_HANG"] = "1"
        result = subprocess.run(
            ["bash", str(CI / "codex-review.sh")], cwd=CI.parents[1], env=env,
            stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=20,
        )
        self.assertFalse(marker.exists())
        self.assertEqual((daily / "config.toml").read_text(), 'model_provider = "daily-sentinel-must-not-change"\n')
        self.assertEqual((daily / "auth.json").read_text(), '{"api_key":"daily-auth-file-must-not-be-used"}')
        self.assertEqual((inherited / "config.toml").read_text(), 'model_provider = "inherited-sentinel-must-not-change"\n')
        return result, capture, env, payload

    def test_actual_caller_defaults_to_independent_home_without_credentials(self):
        result, capture, env, payload = self.run_actual_caller()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        recorded = json.loads(capture.read_text())
        self.assertEqual(recorded["home"], str(Path(env["HOME"]) / ".codex-review"))
        self.assertEqual(recorded["args"][0], "exec")
        self.assertIn(payload, recorded["args"][-1])
        self.assertIn("sandbox_mode=read-only", recorded["args"])
        self.assertIn("approval_policy=never", recorded["args"])
        self.assertEqual(recorded["stdin"], "")
        self.assertIn("verdict=pass", result.stdout)

    def test_actual_caller_honors_explicit_review_home(self):
        result, capture, env, _ = self.run_actual_caller(override=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(json.loads(capture.read_text())["home"], env["CODEX_REVIEW_HOME"])

    def test_actual_caller_valid_changes_verdict_exits_nonzero(self):
        changes_body = {
            "verdict": "changes",
            "summary": "found issues",
            "blockers": [{"file": "Sources/App.swift", "line": 42, "severity": "critical", "why": "layer violation"}],
            "notes": [{"file": "Sources/App.swift", "line": None, "note": "refactor"}]
        }
        result, capture, _, _ = self.run_actual_caller(payload_response=changes_body)
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(capture.exists())
        self.assertIn("verdict=changes, blockers=1", result.stdout)

    def test_actual_caller_rejects_parseable_invalid_verdict_schema(self):
        bad_payloads = [
            # Missing required key
            {"summary": "s", "blockers": [], "notes": []},
            {"verdict": "pass", "blockers": [], "notes": []},
            {"verdict": "pass", "summary": "s", "notes": []},
            {"verdict": "pass", "summary": "s", "blockers": []},
            # Extra key
            {"verdict": "pass", "summary": "s", "blockers": [], "notes": [], "extra": 123},
            # Unknown verdict
            {"verdict": "unknown", "summary": "s", "blockers": [], "notes": []},
            # Wrong types
            {"verdict": "pass", "summary": 123, "blockers": [], "notes": []},
            {"verdict": "pass", "summary": "s", "blockers": "none", "notes": []},
            {"verdict": "pass", "summary": "s", "blockers": [], "notes": "none"},
            # Invalid blocker fields or types
            {"verdict": "changes", "summary": "s", "blockers": [{"file": 12, "line": None, "severity": "high", "why": "w"}], "notes": []},
            {"verdict": "changes", "summary": "s", "blockers": [{"file": "f", "line": "1", "severity": "high", "why": "w"}], "notes": []},
            {"verdict": "changes", "summary": "s", "blockers": [{"file": "f", "line": True, "severity": "high", "why": "w"}], "notes": []},
            {"verdict": "changes", "summary": "s", "blockers": [{"file": "f", "line": None, "severity": "low", "why": "w"}], "notes": []},
            {"verdict": "changes", "summary": "s", "blockers": [{"file": "f", "line": None, "severity": "high"}], "notes": []},
            {"verdict": "changes", "summary": "s", "blockers": [{"file": "f", "line": None, "severity": "high", "why": "w", "extra": 1}], "notes": []},
            # Invalid note fields or types
            {"verdict": "pass", "summary": "s", "blockers": [], "notes": [{"file": "f", "line": None}]},
            {"verdict": "pass", "summary": "s", "blockers": [], "notes": [{"file": "f", "line": "bad", "note": "n"}]},
        ]
        for bad in bad_payloads:
            with self.subTest(bad=bad):
                result, capture, _, _ = self.run_actual_caller(payload_response=bad)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("verdict schema 或 state consistency 校验失败", result.stdout)
                self.assertNotIn("verdict=pass", result.stdout)

    def test_actual_caller_rejects_state_inconsistent_verdicts(self):
        inconsistent_payloads = [
            # pass with blockers
            {"verdict": "pass", "summary": "s",
             "blockers": [{"file": "f", "line": 1, "severity": "critical", "why": "bug"}], "notes": []},
            # changes with 0 blockers
            {"verdict": "changes", "summary": "s", "blockers": [], "notes": []},
        ]
        for bad in inconsistent_payloads:
            with self.subTest(bad=bad):
                result, capture, _, _ = self.run_actual_caller(payload_response=bad)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("verdict schema 或 state consistency 校验失败", result.stdout)
                self.assertNotIn("verdict=pass", result.stdout)

    def test_actual_caller_rejects_unparsable_output(self):
        result, capture, _, _ = self.run_actual_caller(payload_response="not json at all")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("无法解析 verdict", result.stdout)
        self.assertNotIn("verdict=pass", result.stdout)

    def test_actual_caller_missing_review_config_fails_before_codex(self):
        result, capture, _, _ = self.run_actual_caller(no_review_config=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(capture.exists())
        self.assertIn("Raven setup failed", result.stderr)

    def test_actual_caller_malformed_review_config_fails_before_codex(self):
        result, capture, _, _ = self.run_actual_caller(malformed_review_config=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(capture.exists())
        self.assertIn("Raven setup failed", result.stderr)

    def test_actual_caller_watchdog_still_bounds_exec(self):
        result, capture, _, _ = self.run_actual_caller(hang=True)
        self.assertTrue(capture.exists(), result.stdout + result.stderr)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("超时", result.stdout)


if __name__ == "__main__":
    unittest.main()
