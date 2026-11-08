"""Unit and end-to-end tests for AIDash Kimi once-per-PR quota guard, draft/docs-only skip, and context slimming."""

from __future__ import annotations

import os
import pathlib
import subprocess
import tempfile

CI_DIR = pathlib.Path(__file__).resolve().parents[1]
KIMI = CI_DIR / "kimi-review.sh"
WORKFLOW = CI_DIR.parents[1] / ".github" / "workflows" / "kimi-review.yml"


def _setup_repo_and_stubs(tmp_path: pathlib.Path, *, docs_only: bool = False):
    repo = tmp_path / "repo"
    repo.mkdir()
    git_env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    subprocess.run(["git", "init", "-q", "-b", "main"], cwd=repo, env=git_env, check=True)
    subprocess.run(["git", "config", "user.name", "t"], cwd=repo, env=git_env, check=True)
    subprocess.run(["git", "config", "user.email", "t@example.invalid"], cwd=repo, env=git_env, check=True)
    (repo / "scripts" / "ci").mkdir(parents=True)
    (repo / "scripts" / "ci" / "kimi-review.sh").write_text(KIMI.read_text(encoding="utf-8"), encoding="utf-8")
    (repo / "scripts" / "ci" / "kimi-review.sh").chmod(0o755)
    (repo / "scripts" / "ci" / "kimi-review-agent.md").write_text(
        (CI_DIR / "kimi-review-agent.md").read_text(encoding="utf-8"),
        encoding="utf-8",
    )
    (repo / "AGENTS.md").write_text("# Base rules\n" + ("x" * 10000), encoding="utf-8")
    (repo / "src.py").write_text("X = 1\n", encoding="utf-8")
    subprocess.run(["git", "add", "."], cwd=repo, env=git_env, check=True)
    subprocess.run(["git", "commit", "-qm", "base"], cwd=repo, env=git_env, check=True)
    base_sha = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, env=git_env, text=True).strip()

    if docs_only:
        (repo / "docs.md").write_text("# Docs update\n", encoding="utf-8")
    else:
        (repo / "src.py").write_text("X = 2\n", encoding="utf-8")
    subprocess.run(["git", "add", "."], cwd=repo, env=git_env, check=True)
    subprocess.run(["git", "commit", "-qm", "head"], cwd=repo, env=git_env, check=True)
    head_sha = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, env=git_env, text=True).strip()
    subprocess.run(["git", "checkout", "-q", "--detach", base_sha], cwd=repo, env=git_env, check=True)
    subprocess.run(["git", "remote", "add", "origin", str(repo)], cwd=repo, env=git_env, check=True)

    tools = tmp_path / "tools"
    tools.mkdir()
    out = tmp_path / "out"
    out.mkdir()

    gh_stub = tools / "gh"
    gh_stub.write_text(
        "#!/bin/sh\n"
        'case "$*" in\n'
        '  *"--paginate"*".body // empty"*)\n'
        '    printf "%s" "${STUB_EXISTING_STICKY:-}"\n'
        "    ;;\n"
        '  *"--paginate"*)\n'
        '    printf "%s" "${STUB_COMMENT_ID:-}"\n'
        "    ;;\n"
        '  "pr comment"*)\n'
        '    prev=""\n'
        '    for a in "$@"; do\n'
        '      [ "$prev" = "--body" ] && printf "%s" "$a" > "$STUB_OUT/comment"\n'
        '      prev="$a"\n'
        "    done\n"
        "    ;;\n"
        "  *)\n"
        '    for a in "$@"; do\n'
        '      case "$a" in body=*) printf "%s" "${a#body=}" > "$STUB_OUT/comment" ;; esac\n'
        "    done\n"
        "    ;;\n"
        "esac\n"
        "exit 0\n",
        encoding="utf-8",
    )
    gh_stub.chmod(0o755)

    kimi_stub = tools / "kimi"
    kimi_stub.write_text(
        "#!/bin/sh\n"
        'prev=""\n'
        'for a in "$@"; do [ "$prev" = "-p" ] && printf "%s" "$a" > "$STUB_OUT/prompt"; prev="$a"; done\n'
        'printf \'%s\\n\' \'{"role":"assistant","content":"{\\"verdict\\":\\"pass\\",\\"summary\\":\\"ok\\",\\"blockers\\":[],\\"notes\\":[]}"}\'\n',
        encoding="utf-8",
    )
    kimi_stub.chmod(0o755)

    return repo, base_sha, head_sha, tools, out


def _run_kimi(repo, base_sha, head_sha, tools, out, **extra_env):
    for f in out.iterdir():
        f.unlink()
    gh_output = out / "github_output"
    env = {
        k: v
        for k, v in os.environ.items()
        if not k.startswith("GIT_")
    }
    env.update(
        PATH=f"{tools}:{os.environ.get('PATH', '/usr/bin:/bin')}",
        PR_NUMBER="42",
        BASE_SHA=base_sha,
        HEAD_SHA=head_sha,
        BASE_REPO="LeePepe/AIDash",
        KIMI_BIN=str(tools / "kimi"),
        STUB_OUT=str(out),
        GITHUB_OUTPUT=str(gh_output),
    )
    env.update(extra_env)
    proc = subprocess.run(
        ["bash", str(repo / "scripts" / "ci" / "kimi-review.sh")],
        cwd=repo,
        env=env,
        capture_output=True,
        text=True,
        timeout=30,
        check=False,
    )
    comment = (out / "comment").read_text(encoding="utf-8") if (out / "comment").exists() else ""
    outputs = gh_output.read_text(encoding="utf-8").splitlines() if gh_output.exists() else []
    return proc, comment, outputs


def test_workflow_skips_draft_and_includes_ready_for_review() -> None:
    text = WORKFLOW.read_text(encoding="utf-8")
    assert "ready_for_review" in text
    assert "!github.event.pull_request.draft" in text


def test_slim_diff_and_context_excerpt_caps() -> None:
    source = KIMI.read_text(encoding="utf-8")
    assert "--unified=15" in source
    assert 'MAX_BYTES="${REVIEW_MAX_BYTES:-40000}"' in source
    assert 'KIMI_MAX_ATTEMPTS="${KIMI_MAX_ATTEMPTS:-1}"' in source
    assert "p[:8000]" in source
    assert "p[:24000]" not in source


def test_once_per_pr_guard_skips_completed_review_and_reruns_unavailable() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        repo, base_sha, head_sha, tools, out = _setup_repo_and_stubs(pathlib.Path(tmp))
        for existing in (
            "<!-- kimi-advisory-review -->\n## ✅ Kimi advisory review: pass\n",
            "<!-- kimi-advisory-review -->\n## 🔴 Kimi advisory review: findings\n",
            "<!-- shared-ci-kimi-review -->\n## kimi advisory review: pass\n",
            "<!-- kimi-advisory-review -->\n## ⚠️ Kimi advisory review\n",
        ):
            proc, comment, outputs = _run_kimi(
                repo, base_sha, head_sha, tools, out, STUB_EXISTING_STICKY=existing
            )
            assert proc.returncode == 0
            assert "already has a completed Kimi review; skipping per once-per-PR quota policy." in proc.stdout
            assert not (out / "prompt").exists()
            assert comment == ""
            assert "completed=true" in outputs

        # Unavailable previous comment allows Kimi to run
        unavailable = "<!-- kimi-advisory-review -->\n## ⚪ Kimi advisory review unavailable\n"
        proc, comment, outputs = _run_kimi(
            repo, base_sha, head_sha, tools, out, STUB_EXISTING_STICKY=unavailable
        )
        assert proc.returncode == 0
        assert (out / "prompt").exists()
        assert "## ✅ Kimi advisory review: pass" in comment
        assert "completed=true" in outputs

        # Force rerun overrides completed sticky review
        proc, comment, outputs = _run_kimi(
            repo,
            base_sha,
            head_sha,
            tools,
            out,
            STUB_EXISTING_STICKY="<!-- kimi-advisory-review -->\n## ✅ Kimi advisory review: pass\n",
            KIMI_FORCE_RERUN="1",
        )
        assert proc.returncode == 0
        assert (out / "prompt").exists()
        assert "## ✅ Kimi advisory review: pass" in comment


def test_docs_only_diff_skips_kimi_invocation() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        repo, base_sha, head_sha, tools, out = _setup_repo_and_stubs(
            pathlib.Path(tmp), docs_only=True
        )
        proc, comment, outputs = _run_kimi(repo, base_sha, head_sha, tools, out)
        assert proc.returncode == 0
        assert not (out / "prompt").exists()
        assert "No non-documentation code changes; skipped Kimi LLM invocation to conserve quota." in comment
        assert "completed=true" in outputs
