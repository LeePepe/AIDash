# Quickstart: Run-Health L0 Collection

This is an implementation and acceptance guide. Commands that contact Multica are for the one authorized local acceptance run only; automated tests and CI use fixtures.

## 1. Configure locally

Copy the neutral examples for `MULTICA_RUN_AGENTS`, protected branches, and red-line rules into ignored `aidata/config_local.py`. Use real values only there. Never place agent, workspace, runtime, email, or local-path values in tracked files or evidence.

With no configured agents, the new collection path must return zero without error.

## 2. Implement in layer order

1. Complete the `AidataFoundation` configuration task and commit it as one layer-scoped commit.
2. Complete the `AidataL1L2` adapter task and commit it as the dependent layer-scoped commit.
3. Keep the two commits in one feature PR. Do not modify L2 schemas, source registries, cron scripts, L3/L4/L5, Swift packages, or UI.

Normal commit and push hooks select the repository gates. Do not bypass them and do not manually repeat the full suite.

## 3. Fixture verification

Fixture coverage must prove:

- New run on an old issue is discovered from agent tasks.
- Queued/running becomes completed, failed, or cancelled on a later pass.
- Unknown status remains pending.
- Task pagination and incomplete bare-list responses are honest.
- Message sequence overlap is gap-free and idempotent.
- Secret sentinels never appear in serialized records.
- Every red-line rule has positive and near-miss cases.
- Empty Copilot run/runtime usage remains empty with no model/token fallback.
- Agent snapshots write only on change.
- Timeline replay and truncation metadata are preserved.
- PR candidates retain provenance without surrounding content.
- Mutation command prefixes are rejected before subprocess launch.
- Existing normalized run and registered runner-source contracts remain green.

## 4. One real local acceptance run

After fixture and hook success, run the already-supported aidata collect entry points for `multica_issue`, `multica_comment`, and `multica_run` once with local configuration. Do not add a permanent live test or schedule.

Capture only this sanitized evidence for each family:

| Raw family | Required evidence |
|---|---|
| `multica_run` | logical row count; one sample with IDs replaced and lifecycle field names retained |
| `multica_run_message` | logical row count; one sample showing sequence, hashes, lengths, and rule name/null |
| `multica_agent_snapshot` | logical row count; one sample with agent/runtime IDs replaced |
| `multica_runtime_usage` | logical row count; one sample preserving empty usage when observed |
| `multica_runtime_activity` | logical row count; one sample with runtime ID replaced |
| `multica_issue_timeline` | logical row count; one sample showing action and truncation flag with IDs replaced |
| `multica_issue_pr_link` | logical row count; one sample with issue/source IDs replaced and a public normalized PR URL only if safe |

The evidence must not include raw body/input/output, email, private metadata, local path, CLI stderr, or configured IDs. If a family has zero rows, report zero and the reason; do not manufacture a sample.

## 5. Handoff checks

- Confirm changed files match the two task allowlists.
- Confirm `.specify/feature.json` and planning documents are not accidentally included in the implementation PR unless the reviewed planning revision is intentionally its base.
- Confirm `config_local.py` is untracked and absent from the diff.
- Confirm the existing source registry and cron runner list did not change.
- Confirm hook/CI results and the sanitized seven-family evidence are attached to the implementation handoff.
- Pin local HEAD, pushed branch SHA, and PR head SHA byte-for-byte before independent implementation review.

## Failure handling

- A CLI response-shape or pagination mismatch blocks completeness claims; preserve the fixture/observed shape and return to Team Lead rather than guessing a cursor.
- A source that returns empty usage is successful empty evidence, not a failure.
- Timeline truncation is successful partial evidence and must remain marked incomplete.
- Any need to change normalized schemas, schedule scripts, analytics, or UI is a separate issue and does not expand this feature.
