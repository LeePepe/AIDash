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
        self.config.write_text(CONFIG, encoding="utf-8")

    def command(self, config_text=None, env=None):
        if config_text is not None:
            self.config.write_text(config_text, encoding="utf-8")
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
        self.config.write_text('secret = "fixture-sensitive-invalid', encoding="utf-8")
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
            'print(json.dumps({"args":sys.argv[1:],"review_home":os.environ.get("CODEX_HOME")}))\n',
            encoding="utf-8"
        )
        fake.chmod(0o700)
        review_home = Path(self.directory.name) / "review-home"
        review_home.mkdir()
        (review_home / "config.toml").write_text('model_provider = "isolated-provider"\n', encoding="utf-8")
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
        fake.write_text('#!' + sys.executable + '\nimport sys\nsys.exit(0)\n', encoding="utf-8")
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

    def test_real_launcher_missing_or_unreadable_or_unselected_config_fails_before_codex(self):
        fake = Path(self.directory.name) / "codex"
        fake.write_text('#!' + sys.executable + '\nimport sys\nsys.exit(0)\n', encoding="utf-8")
        fake.chmod(0o700)
        review_home = Path(self.directory.name) / "review-home"
        review_home.mkdir(exist_ok=True)
        env = dict(PATH=os.environ["PATH"], HOME=self.directory.name, CODEX_HOME=str(review_home))

        # Missing config
        cfg = review_home / "config.toml"
        if cfg.exists():
            cfg.unlink()
        result = subprocess.run([sys.executable, str(HELPER), str(fake), "fixture"],
                                env=env, capture_output=True, text=True, timeout=5)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Raven setup failed", result.stderr)

        # Unselected config
        cfg.write_text('approval_policy = "never"\n', encoding="utf-8")
        result = subprocess.run([sys.executable, str(HELPER), str(fake), "fixture"],
                                env=env, capture_output=True, text=True, timeout=5)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Raven setup failed", result.stderr)

        # Missing executable
        cfg.write_text('model_provider = "p"\n', encoding="utf-8")
        result = subprocess.run([sys.executable, str(HELPER), "/nonexistent/path/to/codex", "fixture"],
                                env=env, capture_output=True, text=True, timeout=5)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Raven setup failed", result.stderr)

    def test_caller_keeps_isolation_and_uses_raven_launcher(self):
        source = (CI / "codex-review.sh").read_text(encoding="utf-8")
        self.assertIn(
            '"$REPO_ROOT/scripts/ci/review-python311" '
            '"$REPO_ROOT/scripts/ci/review-raven.py" "$CODEX_BIN"',
            source,
        )
        self.assertIn('CODEX_HOME="${CODEX_REVIEW_HOME:-$HOME/.codex-review}"', source)
        self.assertIn("-c sandbox_mode=read-only", source)
        self.assertIn("-c approval_policy=never", source)
        self.assertNotIn('"$CODEX_BIN" exec', source)

    def run_actual_caller(self, *, override=False, payload_response=None, hang=False,
                          no_review_config=False, unreadable_review_config=False,
                          unselected_review_config=False, malformed_review_config=False,
                          empty_output=False):
        """Run the real shell, renderer, provider helper and watchdog; fake only external tools."""
        root = Path(self.directory.name)
        bin_dir = root / "bin"
        bin_dir.mkdir(exist_ok=True)

        daily = root / ".codex"
        daily.mkdir(exist_ok=True)
        daily_config_content = 'model_provider = "daily-sentinel-must-not-change"\n'
        daily_auth_content = '{"api_key":"daily-auth-file-must-not-be-used"}'
        (daily / "config.toml").write_text(daily_config_content, encoding="utf-8")
        (daily / "auth.json").write_text(daily_auth_content, encoding="utf-8")

        inherited = root / "inherited daily home"
        inherited.mkdir(exist_ok=True)
        inherited_config_content = 'model_provider = "inherited-sentinel-must-not-change"\n'
        inherited_auth_content = '{"api_key":"inherited-auth-sentinel-must-not-change"}'
        (inherited / "config.toml").write_text(inherited_config_content, encoding="utf-8")
        (inherited / "auth.json").write_text(inherited_auth_content, encoding="utf-8")

        codex_raven_config = root / "isolated_raven_config.toml"
        codex_raven_config_content = 'model_provider = "raven-env-sentinel-must-not-change"\n'
        codex_raven_config.write_text(codex_raven_config_content, encoding="utf-8")

        default_review = root / ".codex-review"
        default_review.mkdir(exist_ok=True)
        default_review_auth_content = '{"api_key":"default-review-auth-sentinel"}'
        (default_review / "auth.json").write_text(default_review_auth_content, encoding="utf-8")

        default_review_config_content = None
        if not no_review_config:
            if malformed_review_config:
                default_review_config_content = 'invalid = toml [[[\n'
            elif unselected_review_config:
                default_review_config_content = 'approval_policy = "never"\n'
            else:
                default_review_config_content = 'model_provider = "default-review-provider"\n'
            (default_review / "config.toml").write_text(default_review_config_content, encoding="utf-8")
            if unreadable_review_config:
                (default_review / "config.toml").chmod(0o000)

        override_review = root / "explicit review home"
        override_review.mkdir(exist_ok=True)
        override_review_config_content = 'model_provider = "override-review-provider"\n'
        override_review_auth_content = '{"api_key":"override-review-auth-sentinel"}'
        (override_review / "config.toml").write_text(override_review_config_content, encoding="utf-8")
        (override_review / "auth.json").write_text(override_review_auth_content, encoding="utf-8")

        marker = root / "SHELL_MUST_NOT_RUN"
        payload = f"+ quoted 'text' $(touch {marker}) `touch {marker}` 中文"
        capture = root / "capture.json"
        posted_comments = root / "posted_comments.json"
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
            "if os.environ.get('EMPTY_OUTPUT'): sys.exit(0)\n"
            "raw_resp = os.environ.get('RESPONSE_BODY')\n"
            "Path(args[args.index('-o')+1]).write_text(raw_resp if raw_resp else '')\n",
            encoding="utf-8"
        )
        (bin_dir / "git").write_text(
            "#!" + sys.executable + "\nimport os,sys\n"
            "cmd=sys.argv[1]\n"
            "if cmd=='rev-parse': print(os.environ['FIXTURE_REPO'])\n"
            "elif cmd=='diff': print('fixture.md' if '--name-only' in sys.argv else "
            "'diff --git a/fixture.md b/fixture.md\\n'+os.environ['FIXTURE_DIFF'])\n"
            "elif cmd not in ('fetch','cat-file'): sys.exit(1)\n",
            encoding="utf-8"
        )
        fake_gh = bin_dir / "gh"
        fake_gh.write_text(
            "#!" + sys.executable + "\nimport json,os,sys\nfrom pathlib import Path\n"
            "comments_path = Path(os.environ['POSTED_COMMENTS'])\n"
            "if comments_path.exists():\n"
            "    comments = json.loads(comments_path.read_text(encoding='utf-8'))\n"
            "else:\n"
            "    comments = []\n"
            "args = sys.argv[1:]\n"
            "body = None\n"
            "if 'pr' in args and 'comment' in args and '--body' in args:\n"
            "    body = args[args.index('--body') + 1]\n"
            "elif 'api' in args:\n"
            "    for i, arg in enumerate(args):\n"
            "        if arg.startswith('body='):\n"
            "            body = arg[5:]\n"
            "        elif arg.startswith('-fbody='):\n"
            "            body = arg[7:]\n"
            "        elif arg.startswith('-Fbody='):\n"
            "            body = arg[7:]\n"
            "        elif arg in ('-f', '-F', '--field', '--raw-field') and i + 1 < len(args) and args[i + 1].startswith('body='):\n"
            "            body = args[i + 1][5:]\n"
            "if body is not None:\n"
            "    comments.append({'argv': args, 'body': body})\n"
            "    comments_path.write_text(json.dumps(comments), encoding='utf-8')\n"
            "sys.exit(0)\n",
            encoding="utf-8"
        )
        for binary in (fake, bin_dir / "git", fake_gh):
            binary.chmod(0o700)

        env = {
            "PATH": str(bin_dir) + os.pathsep + os.environ["PATH"],
            "HOME": str(root), "CODEX_HOME": str(inherited), "CODEX_BIN": str(fake),
            "CODEX_RAVEN_CONFIG": str(codex_raven_config),
            "PR_NUMBER": "1", "BASE_SHA": "fixture-base", "HEAD_SHA": "fixture-head",
            "BASE_REPO": "fixture/repository", "CAPTURE": str(capture),
            "POSTED_COMMENTS": str(posted_comments),
            "FIXTURE_REPO": str(CI.parents[1]), "FIXTURE_DIFF": payload,
            "GATE_TIMEOUT_SECONDS": "1" if hang else "30",
            "REVIEW_CLI_TIMEOUT_SECONDS": "1" if hang else "30",
            "RESPONSE_BODY": json.dumps(response_body) if isinstance(response_body, (dict, list)) else str(response_body),
        }
        if empty_output:
            env["EMPTY_OUTPUT"] = "1"
        if override:
            env["CODEX_REVIEW_HOME"] = str(override_review)
        if hang:
            env["FIXTURE_HANG"] = "1"

        try:
            result = subprocess.run(
                ["bash", str(CI / "codex-review.sh")], cwd=CI.parents[1], env=env,
                stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=20,
            )
        finally:
            if unreadable_review_config and not no_review_config:
                (default_review / "config.toml").chmod(0o600)

        self.assertFalse(marker.exists())

        # Verify sentinels across daily, inherited, isolated-env, override, and default review homes
        self.assertEqual((daily / "config.toml").read_text(encoding="utf-8"), daily_config_content)
        self.assertEqual((daily / "auth.json").read_text(encoding="utf-8"), daily_auth_content)
        self.assertEqual((inherited / "config.toml").read_text(encoding="utf-8"), inherited_config_content)
        self.assertEqual((inherited / "auth.json").read_text(encoding="utf-8"), inherited_auth_content)
        self.assertEqual(codex_raven_config.read_text(encoding="utf-8"), codex_raven_config_content)
        self.assertEqual((override_review / "config.toml").read_text(encoding="utf-8"), override_review_config_content)
        self.assertEqual((override_review / "auth.json").read_text(encoding="utf-8"), override_review_auth_content)
        self.assertEqual((default_review / "auth.json").read_text(encoding="utf-8"), default_review_auth_content)
        if default_review_config_content is not None:
            self.assertEqual((default_review / "config.toml").read_text(encoding="utf-8"), default_review_config_content)

        posted_comments_list = json.loads(posted_comments.read_text(encoding="utf-8")) if posted_comments.exists() else []

        return result, capture, env, payload, posted_comments_list

    def assert_sanitized_bodies(self, comments_or_bodies, forbidden_payloads=()):
        """Assert that every captured POST/PATCH body equals the fixed sanitized diagnostic

        and contains no pass rendering or forbidden payloads (sentinels, diff/prompt text).
        """
        if not comments_or_bodies:
            raise AssertionError("No comments or bodies provided for sanitization check")
        if isinstance(comments_or_bodies[0], dict) and "body" in comments_or_bodies[0]:
            bodies = [c["body"] for c in comments_or_bodies]
        else:
            bodies = list(comments_or_bodies)
        expected_diagnostic = (
            "<!-- aidash-codex-review -->\n"
            "⚠️ 自动 review 输出无法解析。为安全起见 **暂不放行**,请人工检查或重跑。"
        )
        for body in bodies:
            self.assertEqual(body, expected_diagnostic)
            self.assertNotIn("✅ codex review:通过", body)
            for forbidden in forbidden_payloads:
                if forbidden:
                    self.assertNotIn(forbidden, body)

    def test_actual_caller_defaults_to_independent_home_without_credentials(self):
        result, capture, env, payload, posted_comments = self.run_actual_caller()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        recorded = json.loads(capture.read_text(encoding="utf-8"))
        self.assertEqual(recorded["home"], str(Path(env["HOME"]) / ".codex-review"))
        self.assertEqual(recorded["args"][0], "exec")
        self.assertIn(payload, recorded["args"][-1])
        self.assertIn("sandbox_mode=read-only", recorded["args"])
        self.assertIn("approval_policy=never", recorded["args"])
        self.assertEqual(recorded["stdin"], "")
        self.assertIn("verdict=pass", result.stdout)
        self.assertTrue(posted_comments)
        self.assertTrue(any("✅ codex review:通过" in c["body"] for c in posted_comments))

    def test_actual_caller_honors_explicit_review_home(self):
        result, capture, env, _, _ = self.run_actual_caller(override=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(json.loads(capture.read_text(encoding="utf-8"))["home"], env["CODEX_REVIEW_HOME"])

    def test_actual_caller_valid_changes_verdict_exits_nonzero(self):
        changes_body = {
            "verdict": "changes",
            "summary": "found issues",
            "blockers": [{"file": "Sources/App.swift", "line": 42, "severity": "critical", "why": "layer violation"}],
            "notes": [{"file": "Sources/App.swift", "line": None, "note": "refactor"}]
        }
        result, capture, _, _, posted_comments = self.run_actual_caller(payload_response=changes_body)
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(capture.exists())
        self.assertIn("verdict=changes, blockers=1", result.stdout)
        self.assertTrue(posted_comments)
        self.assertTrue(any("🔴 codex review:需要修改" in c["body"] for c in posted_comments))
        self.assertTrue(any("layer violation" in c["body"] for c in posted_comments))

    def test_actual_caller_rejects_parseable_invalid_verdict_schema(self):
        sentinel_secret = "ATTACKER_INFLUENCED_SECRET_SENTINEL_XYZ123"
        bad_payloads = [
            # Wrong root type
            ["verdict", "pass"],
            "string root",
            12345,
            # Missing required key
            {"summary": f"s {sentinel_secret}", "blockers": [], "notes": []},
            {"verdict": "pass", "blockers": [], "notes": []},
            {"verdict": "pass", "summary": f"s {sentinel_secret}", "notes": []},
            {"verdict": "pass", "summary": f"s {sentinel_secret}", "blockers": []},
            # Extra key at root
            {"verdict": "pass", "summary": f"s {sentinel_secret}", "blockers": [], "notes": [], "extra": 123},
            # Unknown verdict
            {"verdict": "unknown", "summary": f"s {sentinel_secret}", "blockers": [], "notes": []},
            # Wrong types at root
            {"verdict": "pass", "summary": 123, "blockers": [], "notes": []},
            {"verdict": "pass", "summary": f"s {sentinel_secret}", "blockers": "none", "notes": []},
            {"verdict": "pass", "summary": f"s {sentinel_secret}", "blockers": [], "notes": "none"},
            # Invalid blocker fields or types
            {"verdict": "changes", "summary": "s", "blockers": [{"file": 12, "line": None, "severity": "high", "why": sentinel_secret}], "notes": []},
            {"verdict": "changes", "summary": "s", "blockers": [{"file": "f", "line": "1", "severity": "high", "why": sentinel_secret}], "notes": []},
            {"verdict": "changes", "summary": "s", "blockers": [{"file": "f", "line": True, "severity": "high", "why": sentinel_secret}], "notes": []},
            {"verdict": "changes", "summary": "s", "blockers": [{"file": "f", "line": None, "severity": "low", "why": sentinel_secret}], "notes": []},
            {"verdict": "changes", "summary": "s", "blockers": [{"file": "f", "line": None, "severity": "high"}], "notes": []},
            {"verdict": "changes", "summary": "s", "blockers": [{"file": "f", "line": None, "severity": "high", "why": sentinel_secret, "extra": 1}], "notes": []},
            # Non-string blockers[].why
            {"verdict": "changes", "summary": "s", "blockers": [{"file": "f", "line": None, "severity": "high", "why": 12345}], "notes": []},
            {"verdict": "changes", "summary": "s", "blockers": [{"file": "f", "line": None, "severity": "high", "why": ["not", "string"]}], "notes": []},
            # Invalid note fields or types
            {"verdict": "pass", "summary": "s", "blockers": [], "notes": [{"file": "f", "line": None}]},
            {"verdict": "pass", "summary": "s", "blockers": [], "notes": [{"file": "f", "line": "bad", "note": sentinel_secret}]},
            {"verdict": "pass", "summary": "s", "blockers": [], "notes": [{"file": "f", "line": True, "note": sentinel_secret}]},
            {"verdict": "pass", "summary": "s", "blockers": [], "notes": [{"file": "f", "line": None, "note": sentinel_secret, "extra": 1}]},
            {"verdict": "pass", "summary": "s", "blockers": [], "notes": [{"file": 123, "line": None, "note": sentinel_secret}]},
            # Non-string notes[].note
            {"verdict": "pass", "summary": "s", "blockers": [], "notes": [{"file": "f", "line": None, "note": 12345}]},
            {"verdict": "pass", "summary": "s", "blockers": [], "notes": [{"file": "f", "line": None, "note": {"nested": "dict"}}]},
        ]
        for bad in bad_payloads:
            with self.subTest(bad=bad):
                result, capture, _, payload, posted_comments = self.run_actual_caller(payload_response=bad)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn("verdict=pass", result.stdout)
                # Ensure rejected output content is sanitized and never dumped to process output
                self.assertNotIn(sentinel_secret, result.stdout + result.stderr)
                # Ensure sticky comment is posted with sanitized diagnostic and no attacker secret, prompt payload, or pass rendering
                self.assertTrue(posted_comments)
                self.assert_sanitized_bodies(posted_comments, forbidden_payloads=(sentinel_secret, payload))

    def test_actual_caller_rejects_state_inconsistent_verdicts(self):
        sentinel_secret = "STATE_INCONSISTENT_SECRET_SENTINEL_456"
        inconsistent_payloads = [
            # pass with blockers
            {"verdict": "pass", "summary": sentinel_secret,
             "blockers": [{"file": "f", "line": 1, "severity": "critical", "why": "bug"}], "notes": []},
            # changes with 0 blockers
            {"verdict": "changes", "summary": sentinel_secret, "blockers": [], "notes": []},
        ]
        for bad in inconsistent_payloads:
            with self.subTest(bad=bad):
                result, capture, _, payload, posted_comments = self.run_actual_caller(payload_response=bad)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("verdict schema 或 state consistency 校验失败", result.stdout + result.stderr)
                self.assertNotIn("verdict=pass", result.stdout)
                self.assertNotIn(sentinel_secret, result.stdout + result.stderr)
                self.assertTrue(posted_comments)
                self.assert_sanitized_bodies(posted_comments, forbidden_payloads=(sentinel_secret, payload))

    def test_actual_caller_rejects_unparsable_output_sanitized(self):
        sentinel = "UNPARSABLE_SECRET_IN_PROMPT_OR_DIFF"
        result, capture, _, payload, posted_comments = self.run_actual_caller(payload_response=f"not json at all {sentinel}")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("无法解析 verdict", result.stdout + result.stderr)
        self.assertNotIn("verdict=pass", result.stdout)
        self.assertNotIn(sentinel, result.stdout + result.stderr)
        self.assertTrue(posted_comments)
        self.assert_sanitized_bodies(posted_comments, forbidden_payloads=(sentinel, payload))

    def test_actual_caller_contaminated_body_followed_by_sanitized_fails(self):
        expected_diagnostic = (
            "<!-- aidash-codex-review -->\n"
            "⚠️ 自动 review 输出无法解析。为安全起见 **暂不放行**,请人工检查或重跑。"
        )
        contaminated_comments = [
            {"argv": ["fake", "post"], "body": "unexpected non-diagnostic body"},
            {"argv": ["fake", "patch"], "body": expected_diagnostic},
        ]
        with self.assertRaises(AssertionError):
            self.assert_sanitized_bodies(contaminated_comments, forbidden_payloads=("secret", "diff"))

    def test_actual_caller_empty_output_fails_closed(self):
        result, capture, _, _, posted_comments = self.run_actual_caller(empty_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("codex CLI 失败", result.stdout)
        self.assertNotIn("verdict=pass", result.stdout)
        self.assertTrue(posted_comments)
        self.assertTrue(any("自动 review 未能完成(codex CLI 异常)" in c["body"] for c in posted_comments))

    def test_actual_caller_missing_review_config_fails_before_codex(self):
        result, capture, _, _, _ = self.run_actual_caller(no_review_config=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(capture.exists())
        self.assertIn("Raven setup failed", result.stderr)

    def test_actual_caller_unreadable_review_config_fails_before_codex(self):
        result, capture, _, _, _ = self.run_actual_caller(unreadable_review_config=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(capture.exists())
        self.assertIn("Raven setup failed", result.stderr)

    def test_actual_caller_unselected_review_config_fails_before_codex(self):
        result, capture, _, _, _ = self.run_actual_caller(unselected_review_config=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(capture.exists())
        self.assertIn("Raven setup failed", result.stderr)

    def test_actual_caller_malformed_review_config_fails_before_codex(self):
        result, capture, _, _, _ = self.run_actual_caller(malformed_review_config=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(capture.exists())
        self.assertIn("Raven setup failed", result.stderr)

    def test_actual_caller_watchdog_still_bounds_exec(self):
        result, capture, _, _, posted_comments = self.run_actual_caller(hang=True)
        self.assertTrue(capture.exists(), result.stdout + result.stderr)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("超时", result.stdout)
        self.assertTrue(posted_comments)
        self.assertTrue(any("codex CLI 超过" in c["body"] for c in posted_comments))


if __name__ == "__main__":
    unittest.main()
