# Raven review operations

The trusted `codex-review.sh` invokes the standard Codex CLI through
`review-raven.py`. Provider selection is authority-bound exclusively to the
configured review home: `CODEX_HOME`, defaulting to `CODEX_REVIEW_HOME` or
`$HOME/.codex-review`, must define a valid `config.toml` selecting a non-empty
`model_provider`. The helper is provider-neutral, accepts any configured
provider without Raven-specific restrictions or CLI overrides, and preserves all
caller arguments verbatim. It never reads or requires daily config or environment
credentials.

## Runner readiness and authentication

1. Authentication and provider configuration are owned entirely within the
   independent review home (`$CODEX_HOME/config.toml` and associated review-home
   auth state).
2. The launcher does not require, inspect, allowlist, or inject `RAVEN_API_KEY`,
   `OPENAI_API_KEY`, or any other model credentials from the process environment.
   No repository or host credential provisioning is required for this repair.

Project code never sources credential files, shell startup files, or auth.json;
it never selects GH_TOKEN/GITHUB_TOKEN as model credentials. GitHub's job token
remains solely for repository/comment operations. A working terminal does not
prove launchd/runner environment readiness. Do not print keys, copy daily auth
caches, or restart services as an automatic repair.

Runner prerequisites: Python 3.11+ on PATH (stdlib `tomllib`), the existing
standard Codex binary (`CODEX_BIN`, normally `/opt/homebrew/bin/codex`), and
a valid review-home configuration selecting a `model_provider`. Missing or unsafe
provider setup fails before Codex starts, with a sanitized `Raven setup failed`
diagnostic and no direct-OpenAI fallback or retry.

## Independent review home and result validation

The caller sets `CODEX_HOME=${CODEX_REVIEW_HOME:-$HOME/.codex-review}`.
An inherited daily CODEX_HOME is deliberately ignored. Provision that independent
review home separately and preserve its existing model/effort, no-hooks/no-MCP,
read-only sandbox and never-approval settings. The caller continues to pin
read-only and never-approval; the provider helper does not provision or verify
the whole home, and does not modify login state or auth caches.

Before rendering or determining exit status, `codex-review.sh` enforces complete
terminal schema and state consistency validation:
- The JSON object must strictly match the declared schema with exact root keys
  (`verdict`, `summary`, `blockers`, `notes`) and typed blocker/note arrays.
- `pass` strictly requires zero blockers and exits 0.
- `changes` strictly requires at least one blocker and exits 1.
- Contradictory, missing, extra, wrong-typed, or unparsable output fails closed
  with a sanitized invalid-output diagnostic without printing raw model output,
  and exits 1.

Legacy auth-refresh/model-catalog warnings are separate diagnostics: do not
change login, CLI version, model or network policy merely to silence them.
Judge invocation by its exit status and actual output, not a warning alone.

## Trusted-base migration and blocked delivery boundary

`pull_request_target` checks out the trusted base SHA. A candidate's new helper
does not repair the old base's own review execution.

Because the trusted base on `main` still evaluates the pre-existing review script,
the repair PR's required `codex-review-target` check will fail with the recorded
setup signature (`[codex-review] Raven setup failed: Daily Codex must explicitly select the Raven provider`).
Under P2F-R4 / AC-09:
- T1-RI remains incomplete and blocked while `codex-review-target` is red.
- When local checks pass, AI Reviewer PASSes, and all other required checks are green
  on the exact pushed head, PR Manager collects and returns the blocked evidence
  bundle to Team Lead.
- No Dev Team role calls T1-RI delivered or complete, and no shipping or merge step
  follows. No agent prepares, recommends, validates, facilitates, retries, or
  executes a merge or required-check bypass.
- T2-PF (parked PR review proof) is a distinct follow-up that may be scheduled only
  after Team Lead records read-only observation of an external landing outside Dev Team.

Offline contracts exercise the real caller with fake Git/GitHub/Codex tools;
they make no model request and are not an actual review. No setup-only `--check`
mode is added: this helper's normal invocation starts Codex.

AIDash retains review-common.sh scope/evidence protections and its CLI process-group
watchdog. Local verification is the existing pre-commit hook with only candidate
files staged; its Python 3.9 pytest gate delegates the Raven contracts to the
runner's Python 3.11+ without replacing the gate. Never run local host App tests.
