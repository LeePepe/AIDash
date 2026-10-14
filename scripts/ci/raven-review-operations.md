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

Credential provisioning belongs to the host bootstrap, not this repository.
Project code never sources credential files, shell startup files, or auth.json;
it never selects GH_TOKEN/GITHUB_TOKEN as model credentials. GitHub's job token
remains solely for repository/comment operations. A working terminal does not
prove launchd/runner environment readiness. Arrange narrowly scoped runner env
provisioning separately; do not print keys, copy daily auth caches, or restart
services as an automatic repair.

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
  with an invalid-output diagnostic and exits 1.

Legacy auth-refresh/model-catalog warnings are separate diagnostics: do not
change login, CLI version, model or network policy merely to silence them.
Judge invocation by its exit status and actual output, not a warning alone.

## Trusted-base migration and acceptance

`pull_request_target` checks out the trusted base SHA. A candidate's new helper
does not repair the old base's own review execution. First establish runner env
readiness, land the approved bootstrap through the existing protected process,
then verify a later event whose base contains that bootstrap. Never substitute
PR-head code into the trusted runner, bypass checks, or blindly rerun unchanged
missing-environment failures.

Offline contracts exercise the real caller with fake Git/GitHub/Codex tools;
they make no model request and are not an actual review. No setup-only `--check`
mode is added: this helper's normal invocation starts Codex.

Keep evidence distinct: provider setup readiness; actual model invocation;
schema/verdict for the exact PR head; required Actions checks; protected merge.
A successful synthetic model call proves only that process's invocation, not
service environment or Actions consumption. Acceptance requires the real
`codex-review-target` run from the intended trusted base for the exact PR head,
a valid review verdict, and all existing required statuses. Kimi stays advisory,
Claude/legacy workflows and schedules stay paused, and existing deterministic
test/build gates and internal Reviewer responsibilities remain unchanged.

AIDash retains review-common.sh scope/evidence protections and its CLI process-group
watchdog. Local verification is the existing pre-commit hook with only candidate
files staged; its Python 3.9 pytest gate delegates the Raven contracts to the
runner's Python 3.11+ without replacing the gate. Never run local host App tests.
