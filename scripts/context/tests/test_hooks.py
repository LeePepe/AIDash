"""Regression tests for resolver-driven git hook semantics."""

from __future__ import annotations

import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest
from unittest import mock


REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[3]
REPO_INFRA_GATE_REGRESSION_ACTIVE = "AIDASH_REPO_INFRA_GATE_REGRESSION_ACTIVE"
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


def repository_git(*arguments: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", *arguments],
        cwd=REPOSITORY_ROOT,
        env=isolated_git_environment(),
        check=check,
        text=True,
        capture_output=True,
    )


def repo_infra_gate_mode() -> str:
    try:
        probe = subprocess.run(
            ["/usr/bin/python3", "-c", "import pytest"],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except OSError:
        return "ci"
    return "local" if probe.returncode == 0 else "ci"


class HookFixture:
    def __init__(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temp.name)
        self.records = self.root / "records"
        self.records.mkdir()
        self.git("init", "-q")
        self.git("config", "user.email", "test@example.com")
        self.git("config", "user.name", "Hook Test")

    def close(self) -> None:
        self.temp.cleanup()

    def write(self, path: str, content: str, *, executable: bool = False) -> None:
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding="utf-8")
        if executable:
            target.chmod(0o755)

    def git(
        self, *arguments: str, check: bool = True,
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["git", *arguments],
            cwd=self.root,
            env=isolated_git_environment(),
            check=check,
            text=True,
            capture_output=True,
        )

    def install_hook(self, name: str) -> pathlib.Path:
        source = REPOSITORY_ROOT / "scripts" / "hooks" / name
        target = self.root / "scripts" / "hooks" / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        return target

    def install_context_stubs(self) -> None:
        self.write(
            "scripts/context/audit",
            "#!/bin/sh\nprintf 'called\\n' >> \"$HOOK_RECORDS/audit\"\n",
            executable=True,
        )
        self.write(
            "scripts/context/layers",
            "#!/bin/sh\n"
            "input=\"$(cat)\"\n"
            "if [ -z \"$input\" ]; then\n"
            "    exit 96\n"
            "fi\n"
            "printf '%s\\n' \"$input\" > \"$HOOK_RECORDS/layers\"\n"
            "printf 'RepoInfra\\n'\n",
            executable=True,
        )
        self.write(
            "scripts/context/run",
            "#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$HOOK_RECORDS/run\"\n",
            executable=True,
        )

    def install_swiftlint_config(self) -> None:
        shutil.copy2(REPOSITORY_ROOT / ".swiftlint.yml", self.root / ".swiftlint.yml")

    def install_failing_swiftlint(self) -> pathlib.Path:
        bin_directory = self.root / "bin"
        bin_directory.mkdir()
        swiftlint = bin_directory / "swiftlint"
        swiftlint.write_text(
            "#!/bin/sh\n"
            "printf 'called\\n' > \"$HOOK_RECORDS/swiftlint-called\"\n"
            "exit 97\n",
            encoding="utf-8",
        )
        swiftlint.chmod(0o755)
        return bin_directory

    def install_recording_swiftlint(self) -> pathlib.Path:
        bin_directory = self.root / "bin"
        bin_directory.mkdir()
        swiftlint = bin_directory / "swiftlint"
        swiftlint.write_text(
            "#!/bin/sh\n"
            "printf '%s\\n' \"$@\" > \"$HOOK_RECORDS/swiftlint-args\"\n",
            encoding="utf-8",
        )
        swiftlint.chmod(0o755)
        return bin_directory

    def install_exclusion_aware_swiftlint(self) -> pathlib.Path:
        bin_directory = self.root / "bin"
        bin_directory.mkdir()
        swiftlint = bin_directory / "swiftlint"
        swiftlint.write_text(
            "#!/usr/bin/python3\n"
            "import os\n"
            "import pathlib\n"
            "import sys\n"
            "args = sys.argv[1:]\n"
            "if '--force-exclude' not in args or '--config' not in args:\n"
            "    raise SystemExit(91)\n"
            "config_index = args.index('--config')\n"
            "config = pathlib.Path(args[config_index + 1]).read_text(encoding='utf-8')\n"
            "if '\"**/.build\"' not in config or '\"**/Tests\"' not in config:\n"
            "    raise SystemExit(92)\n"
            "linted = []\n"
            "for raw_path in args[config_index + 2:]:\n"
            "    parts = pathlib.PurePosixPath(raw_path).parts\n"
            "    if '.build' in parts or 'Tests' in parts:\n"
            "        continue\n"
            "    linted.append(raw_path)\n"
            "    if 'fixture violation' in pathlib.Path(raw_path).read_text(encoding='utf-8'):\n"
            "        raise SystemExit(93)\n"
            "pathlib.Path(os.environ['HOOK_RECORDS'], 'swiftlint-linted').write_text(\n"
            "    ''.join(f'{path}\\n' for path in linted), encoding='utf-8'\n"
            ")\n",
            encoding="utf-8",
        )
        swiftlint.chmod(0o755)
        return bin_directory

    def environment(self) -> dict[str, str]:
        environment = isolated_git_environment()
        environment["HOOK_RECORDS"] = str(self.records)
        return environment


class GitHookTests(unittest.TestCase):
    def setUp(self) -> None:
        self.fixture = HookFixture()

    def tearDown(self) -> None:
        self.fixture.close()

    def test_hook_environment_strips_outer_repository_scope_and_preserves_path(self) -> None:
        outer_scope = {
            "GIT_INDEX_FILE": "/tmp/outer-index",
            "GIT_DIR": "/tmp/outer-git-dir",
            "GIT_WORK_TREE": "/tmp/outer-work-tree",
            "GIT_PREFIX": "outer-prefix/",
            "PATH": os.environ["PATH"],
        }
        with mock.patch.dict(os.environ, outer_scope):
            environment = self.fixture.environment()

        for name in outer_scope.keys() - {"PATH"}:
            self.assertNotIn(name, environment)
        self.assertEqual(outer_scope["PATH"], environment["PATH"])

    def test_repo_infra_gate_preserves_injected_index_and_outer_ref(self) -> None:
        if os.environ.get(REPO_INFRA_GATE_REGRESSION_ACTIVE):
            self.skipTest("already running inside the RepoInfra gate regression")

        head_before = repository_git("rev-parse", "HEAD").stdout.strip()
        symbolic_ref_before = repository_git(
            "symbolic-ref", "--quiet", "HEAD", check=False,
        )
        ref_oid_before = (
            repository_git("rev-parse", symbolic_ref_before.stdout.strip()).stdout.strip()
            if symbolic_ref_before.returncode == 0 else None
        )

        with tempfile.TemporaryDirectory() as outer_temp:
            index_path = pathlib.Path(repository_git("rev-parse", "--git-path", "index").stdout.strip())
            if not index_path.is_absolute():
                index_path = REPOSITORY_ROOT / index_path
            external_index = pathlib.Path(outer_temp) / "outer-index"
            shutil.copy2(index_path, external_index)
            index_before = external_index.read_bytes()

            environment = isolated_git_environment()
            environment["GIT_INDEX_FILE"] = str(external_index)
            environment[REPO_INFRA_GATE_REGRESSION_ACTIVE] = "1"
            gate_mode = repo_infra_gate_mode()
            result = subprocess.run(
                [
                    str(REPOSITORY_ROOT / "scripts/context/run"),
                    "RepoInfra",
                    "--mode",
                    gate_mode,
                ],
                cwd=REPOSITORY_ROOT,
                env=environment,
                text=True,
                capture_output=True,
            )

            self.assertEqual(0, result.returncode, result.stdout + result.stderr)
            self.assertEqual(index_before, external_index.read_bytes())

        self.assertEqual(head_before, repository_git("rev-parse", "HEAD").stdout.strip())
        symbolic_ref_after = repository_git("symbolic-ref", "--quiet", "HEAD", check=False)
        self.assertEqual(symbolic_ref_before.returncode, symbolic_ref_after.returncode)
        self.assertEqual(symbolic_ref_before.stdout, symbolic_ref_after.stdout)
        if ref_oid_before is not None:
            self.assertEqual(
                ref_oid_before,
                repository_git("rev-parse", symbolic_ref_before.stdout.strip()).stdout.strip(),
            )

    def test_repo_infra_gate_mode_uses_ci_without_system_pytest(self) -> None:
        probe_result = subprocess.CompletedProcess([], returncode=1)
        with mock.patch.object(subprocess, "run", return_value=probe_result) as probe:
            self.assertEqual("ci", repo_infra_gate_mode())

        probe.assert_called_once_with(
            ["/usr/bin/python3", "-c", "import pytest"],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

    def test_repo_infra_gate_mode_uses_local_with_system_pytest(self) -> None:
        probe_result = subprocess.CompletedProcess([], returncode=0)
        with mock.patch.object(subprocess, "run", return_value=probe_result):
            self.assertEqual("local", repo_infra_gate_mode())

    def test_pre_commit_routes_deleted_paths_through_layers_stdin(self) -> None:
        self.fixture.write("deleted.txt", "remove me\n")
        self.fixture.git("add", "deleted.txt")
        self.fixture.git("commit", "-qm", "base")
        (self.fixture.root / "deleted.txt").unlink()
        self.fixture.git("add", "-u")
        hook = self.fixture.install_hook("pre-commit")
        self.fixture.install_context_stubs()

        result = subprocess.run(["bash", str(hook)], cwd=self.fixture.root,
                                env=self.fixture.environment(), text=True, capture_output=True)

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("deleted.txt\n", (self.fixture.records / "layers").read_text())
        self.assertEqual("RepoInfra --mode local\n", (self.fixture.records / "run").read_text())

    def test_pre_push_gates_all_refs_and_routes_docs_to_repo_infra(self) -> None:
        self.fixture.write("seed.txt", "base\n")
        self.fixture.git("add", "seed.txt")
        self.fixture.git("commit", "-qm", "base")
        base = self.fixture.git("rev-parse", "HEAD").stdout.strip()
        self.fixture.git("update-ref", "refs/remotes/github/main", base)

        self.fixture.write("Sources/Feature.swift", "let value = 1\n")
        self.fixture.git("add", "Sources/Feature.swift")
        self.fixture.git("commit", "-qm", "code ref")
        code_head = self.fixture.git("rev-parse", "HEAD").stdout.strip()

        self.fixture.git("checkout", "-q", "--detach", base)
        self.fixture.write("docs/readme.md", "docs\n")
        self.fixture.git("add", "docs/readme.md")
        self.fixture.git("commit", "-qm", "docs ref")
        docs_head = self.fixture.git("rev-parse", "HEAD").stdout.strip()

        hook = self.fixture.install_hook("pre-push")
        self.fixture.install_context_stubs()
        self.fixture.write(
            "scripts/quality/require-tests.sh",
            "#!/bin/sh\nprintf '%s %s\\n' \"$1\" \"$2\" >> \"$HOOK_RECORDS/require-tests\"\n",
            executable=True,
        )
        zero = "0" * 40
        push_input = (
            f"refs/heads/code {code_head} refs/heads/code {zero}\n"
            f"refs/heads/docs {docs_head} refs/heads/docs {zero}\n"
        )

        result = subprocess.run(["bash", str(hook), "github", "unused"], cwd=self.fixture.root,
                                env=self.fixture.environment(), input=push_input,
                                text=True, capture_output=True)

        self.assertEqual(0, result.returncode, result.stderr)
        routed = set((self.fixture.records / "layers").read_text().splitlines())
        self.assertEqual({"Sources/Feature.swift", "docs/readme.md"}, routed)
        ranges = (self.fixture.records / "require-tests").read_text().splitlines()
        self.assertEqual(2, len(ranges))
        self.assertIn(f"{base} {code_head}", ranges)
        self.assertIn(f"{base} {docs_head}", ranges)
        self.assertEqual("RepoInfra --mode local\n", (self.fixture.records / "run").read_text())
        origin_main = self.fixture.git(
            "show-ref", "--verify", "--quiet", "refs/remotes/origin/main", check=False,
        )
        self.assertNotEqual(0, origin_main.returncode)

    def test_pre_push_empty_diffs_skip_layer_routing_but_keep_range_gates(self) -> None:
        self.fixture.write("seed.txt", "base\n")
        self.fixture.git("add", "seed.txt")
        self.fixture.git("commit", "-qm", "base")
        base = self.fixture.git("rev-parse", "HEAD").stdout.strip()
        self.fixture.git("update-ref", "refs/remotes/github/main", base)

        self.fixture.git("commit", "--allow-empty", "-qm", "empty")
        empty_head = self.fixture.git("rev-parse", "HEAD").stdout.strip()

        hook = self.fixture.install_hook("pre-push")
        self.fixture.install_context_stubs()
        self.fixture.write(
            "scripts/quality/require-tests.sh",
            "#!/bin/sh\nprintf '%s %s\\n' \"$1\" \"$2\" >> \"$HOOK_RECORDS/require-tests\"\n",
            executable=True,
        )
        zero = "0" * 40
        push_input = (
            f"refs/heads/existing {empty_head} refs/heads/existing {base}\n"
            f"refs/heads/new-at-main {base} refs/heads/new-at-main {zero}\n"
        )

        result = subprocess.run(
            ["bash", str(hook), "github", "unused"],
            cwd=self.fixture.root,
            env=self.fixture.environment(),
            input=push_input,
            text=True,
            capture_output=True,
        )

        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertEqual("called\n", (self.fixture.records / "audit").read_text())
        self.assertEqual(
            [f"{base} {empty_head}", f"{base} {base}"],
            (self.fixture.records / "require-tests").read_text().splitlines(),
        )
        self.assertFalse((self.fixture.records / "layers").exists())
        self.assertFalse((self.fixture.records / "run").exists())

    def test_pre_push_non_swift_change_does_not_call_swiftlint(self) -> None:
        self.fixture.write("seed.txt", "base\n")
        self.fixture.git("add", "seed.txt")
        self.fixture.git("commit", "-qm", "base")
        base = self.fixture.git("rev-parse", "HEAD").stdout.strip()

        self.fixture.write("docs/readme.md", "docs\n")
        self.fixture.git("add", "docs/readme.md")
        self.fixture.git("commit", "-qm", "docs")
        head = self.fixture.git("rev-parse", "HEAD").stdout.strip()

        hook = self.fixture.install_hook("pre-push")
        self.fixture.install_context_stubs()
        self.fixture.install_swiftlint_config()
        bin_directory = self.fixture.install_failing_swiftlint()
        environment = self.fixture.environment()
        environment["PATH"] = f"{bin_directory}{os.pathsep}{environment['PATH']}"
        push_input = f"refs/heads/docs {head} refs/heads/docs {base}\n"

        result = subprocess.run(
            ["bash", str(hook), "github", "unused"],
            cwd=self.fixture.root,
            env=environment,
            input=push_input,
            text=True,
            capture_output=True,
        )

        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertFalse((self.fixture.records / "swiftlint-called").exists())

    def test_pre_push_lints_deduplicated_existing_swift_paths_across_refs(self) -> None:
        self.fixture.write("seed.txt", "base\n")
        self.fixture.write("Sources/Deleted.swift", "let deleted = true\n")
        self.fixture.git("add", "seed.txt", "Sources/Deleted.swift")
        self.fixture.git("commit", "-qm", "base")
        base = self.fixture.git("rev-parse", "HEAD").stdout.strip()

        self.fixture.write("Sources/Shared.swift", "let shared = 1\n")
        self.fixture.write("Tests/ExcludedTests.swift", "let force = try! value()\n")
        self.fixture.write(".build/Generated.swift", "let generated = true\n")
        self.fixture.write("docs/readme.md", "docs\n")
        self.fixture.git("add", "Sources/Shared.swift", "Tests/ExcludedTests.swift", "docs/readme.md")
        self.fixture.git("add", "-f", ".build/Generated.swift")
        self.fixture.git("commit", "-qm", "first ref")
        first_head = self.fixture.git("rev-parse", "HEAD").stdout.strip()

        self.fixture.write("Sources/Second.swift", "let second = 2\n")
        (self.fixture.root / "Sources/Deleted.swift").unlink()
        self.fixture.git("add", "Sources/Second.swift")
        self.fixture.git("add", "-u")
        self.fixture.git("commit", "-qm", "second ref")
        second_head = self.fixture.git("rev-parse", "HEAD").stdout.strip()

        hook = self.fixture.install_hook("pre-push")
        self.fixture.install_context_stubs()
        self.fixture.install_swiftlint_config()
        bin_directory = self.fixture.install_recording_swiftlint()
        environment = self.fixture.environment()
        environment["PATH"] = f"{bin_directory}{os.pathsep}{environment['PATH']}"
        push_input = (
            f"refs/heads/first {first_head} refs/heads/first {base}\n"
            f"refs/heads/second {second_head} refs/heads/second {base}\n"
        )

        result = subprocess.run(
            ["bash", str(hook), "github", "unused"],
            cwd=self.fixture.root,
            env=environment,
            input=push_input,
            text=True,
            capture_output=True,
        )

        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertEqual(
            [
                "lint",
                "--strict",
                "--quiet",
                "--force-exclude",
                "--config",
                str((self.fixture.root / ".swiftlint.yml").resolve()),
                ".build/Generated.swift",
                "Sources/Second.swift",
                "Sources/Shared.swift",
                "Tests/ExcludedTests.swift",
            ],
            (self.fixture.records / "swiftlint-args").read_text().splitlines(),
        )

    def test_pre_push_force_excludes_tests_and_build_swift_paths(self) -> None:
        self.fixture.write("seed.txt", "base\n")
        self.fixture.git("add", "seed.txt")
        self.fixture.git("commit", "-qm", "base")
        base = self.fixture.git("rev-parse", "HEAD").stdout.strip()

        self.fixture.write("Packages/Core/Sources/Feature.swift", "let value = 1\n")
        self.fixture.write(
            "Packages/Core/Tests/FeatureTests.swift", "fixture violation\n",
        )
        self.fixture.write(
            "Packages/Core/.build/Generated.swift", "fixture violation\n",
        )
        self.fixture.git(
            "add", "Packages/Core/Sources/Feature.swift", "Packages/Core/Tests/FeatureTests.swift",
        )
        self.fixture.git("add", "-f", "Packages/Core/.build/Generated.swift")
        self.fixture.git("commit", "-qm", "swift files")
        head = self.fixture.git("rev-parse", "HEAD").stdout.strip()

        hook = self.fixture.install_hook("pre-push")
        self.fixture.install_context_stubs()
        self.fixture.install_swiftlint_config()
        bin_directory = self.fixture.install_exclusion_aware_swiftlint()
        environment = self.fixture.environment()
        environment["PATH"] = f"{bin_directory}{os.pathsep}{environment['PATH']}"
        push_input = f"refs/heads/feature {head} refs/heads/feature {base}\n"

        result = subprocess.run(
            ["bash", str(hook), "github", "unused"],
            cwd=self.fixture.root,
            env=environment,
            input=push_input,
            text=True,
            capture_output=True,
        )

        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertEqual(
            "Packages/Core/Sources/Feature.swift\n",
            (self.fixture.records / "swiftlint-linted").read_text(),
        )

    def test_pre_push_falls_back_to_an_existing_remote_tracking_main(self) -> None:
        self.fixture.write("seed.txt", "base\n")
        self.fixture.git("add", "seed.txt")
        self.fixture.git("commit", "-qm", "base")
        base = self.fixture.git("rev-parse", "HEAD").stdout.strip()
        self.fixture.git("update-ref", "refs/remotes/upstream/main", base)

        self.fixture.write("docs/readme.md", "docs\n")
        self.fixture.git("add", "docs/readme.md")
        self.fixture.git("commit", "-qm", "docs ref")
        head = self.fixture.git("rev-parse", "HEAD").stdout.strip()

        hook = self.fixture.install_hook("pre-push")
        self.fixture.install_context_stubs()
        self.fixture.write(
            "scripts/quality/require-tests.sh",
            "#!/bin/sh\nprintf '%s %s\\n' \"$1\" \"$2\" > \"$HOOK_RECORDS/require-tests\"\n",
            executable=True,
        )
        zero = "0" * 40
        push_input = f"refs/heads/docs {head} refs/heads/docs {zero}\n"

        result = subprocess.run(
            ["bash", str(hook), "github", "unused"],
            cwd=self.fixture.root,
            env=self.fixture.environment(),
            input=push_input,
            text=True,
            capture_output=True,
        )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(
            f"{base} {head}\n",
            (self.fixture.records / "require-tests").read_text(),
        )
        github_main = self.fixture.git(
            "show-ref", "--verify", "--quiet", "refs/remotes/github/main", check=False,
        )
        self.assertNotEqual(0, github_main.returncode)

    def test_pre_push_falls_back_to_repository_root_without_tracking_main(self) -> None:
        self.fixture.write("seed.txt", "base\n")
        self.fixture.git("add", "seed.txt")
        self.fixture.git("commit", "-qm", "base")
        root = self.fixture.git("rev-parse", "HEAD").stdout.strip()

        self.fixture.write("docs/readme.md", "docs\n")
        self.fixture.git("add", "docs/readme.md")
        self.fixture.git("commit", "-qm", "docs ref")
        head = self.fixture.git("rev-parse", "HEAD").stdout.strip()

        hook = self.fixture.install_hook("pre-push")
        self.fixture.install_context_stubs()
        self.fixture.write(
            "scripts/quality/require-tests.sh",
            "#!/bin/sh\nprintf '%s %s\\n' \"$1\" \"$2\" > \"$HOOK_RECORDS/require-tests\"\n",
            executable=True,
        )
        zero = "0" * 40
        push_input = f"refs/heads/docs {head} refs/heads/docs {zero}\n"

        result = subprocess.run(
            ["bash", str(hook), "github", "unused"],
            cwd=self.fixture.root,
            env=self.fixture.environment(),
            input=push_input,
            text=True,
            capture_output=True,
        )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(
            f"{root} {head}\n",
            (self.fixture.records / "require-tests").read_text(),
        )
        remote_refs = self.fixture.git(
            "for-each-ref", "--format=%(refname)", "refs/remotes",
        ).stdout
        self.assertEqual("", remote_refs)


if __name__ == "__main__":
    unittest.main()
