"""Run offline Raven contracts through the Python 3.11+ adapter."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


class RavenContractTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.bin_dir = Path(self.directory.name) / "bin"
        self.bin_dir.mkdir()
        self.record = Path(self.directory.name) / "argv.json"
        self.adapter = Path(__file__).resolve().parents[1] / "review-python311"

    def write_interpreter(self, name, *, compatible, target_returncode=0):
        interpreter = self.bin_dir / name
        interpreter.write_text(
            '#!' + sys.executable + '\n'
            'import json, os, sys\n'
            'if sys.argv[1:2] == ["-c"]:\n'
            f'    raise SystemExit({0 if compatible else 1})\n'
            'with open(os.environ["REVIEW_PYTHON311_RECORD"], "a", encoding="utf-8") as stream:\n'
            '    json.dump({"interpreter": os.path.basename(sys.argv[0]), "argv": sys.argv[1:]}, stream)\n'
            '    stream.write("\\n")\n'
            f'raise SystemExit({target_returncode})\n',
            encoding="utf-8",
        )
        interpreter.chmod(0o700)

    def run_adapter(self, *arguments):
        env = dict(os.environ)
        env["PATH"] = str(self.bin_dir)
        env["REVIEW_PYTHON311_RECORD"] = str(self.record)
        return subprocess.run(
            [str(self.adapter), *arguments],
            env=env,
            capture_output=True,
            text=True,
            timeout=5,
        )

    def recorded_invocations(self):
        return [
            json.loads(line)
            for line in self.record.read_text(encoding="utf-8").splitlines()
        ]

    def test_missing_script_argument_fails_before_probe(self):
        result = self.run_adapter()

        self.assertEqual(result.returncode, 2)
        self.assertIn("script argument is required", result.stderr)
        self.assertFalse(self.record.exists())

    def test_uses_compatible_python3_once_with_exact_target_argv(self):
        self.write_interpreter("python3", compatible=True)
        self.write_interpreter("python3.11", compatible=True)

        result = self.run_adapter(
            "-B", "contract.py", "argument with spaces", "$(never-run)", "中文",
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertEqual(
            self.recorded_invocations(),
            [{
                "interpreter": "python3",
                "argv": [
                    "-B", "contract.py", "argument with spaces", "$(never-run)", "中文",
                ],
            }],
        )

    def test_delegates_from_old_python3_to_compatible_python311(self):
        self.write_interpreter("python3", compatible=False)
        self.write_interpreter("python3.11", compatible=True)

        result = self.run_adapter("contract.py", "fixture")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertEqual(
            self.recorded_invocations(),
            [{"interpreter": "python3.11", "argv": ["contract.py", "fixture"]}],
        )

    def test_missing_or_incompatible_python311_fails_before_target(self):
        for python311_compatible in (None, False):
            with self.subTest(python311_compatible=python311_compatible):
                self.write_interpreter("python3", compatible=False)
                if python311_compatible is not None:
                    self.write_interpreter(
                        "python3.11", compatible=python311_compatible,
                    )

                result = self.run_adapter("contract.py", "fixture")

                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Python 3.11+", result.stderr)
                self.assertFalse(self.record.exists())
                python311 = self.bin_dir / "python3.11"
                if python311.exists():
                    python311.unlink()

    def test_selected_interpreter_target_failure_is_not_retried(self):
        self.write_interpreter("python3", compatible=True, target_returncode=23)
        self.write_interpreter("python3.11", compatible=True)

        result = self.run_adapter("contract.py", "fixture")

        self.assertEqual(result.returncode, 23)
        self.assertEqual(
            self.recorded_invocations(),
            [{"interpreter": "python3", "argv": ["contract.py", "fixture"]}],
        )

    def test_offline_provider_and_actual_caller_contracts(self):
        contract = Path(__file__).resolve().with_name("review_raven_contract.py")
        result = subprocess.run(
            [str(self.adapter), "-B", str(contract)],
            capture_output=True,
            text=True,
            timeout=300,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
