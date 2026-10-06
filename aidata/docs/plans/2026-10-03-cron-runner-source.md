# Cron runner single-source companion plan

Status: planning draft for independent review; no implementation, test, delivery
or deployment result is claimed.

Source baseline: `f3088d834a7d1ab935bca78739de69c3c3455a71`.

## Read contract

Before executing a task, read [AGENTS.md](../../../AGENTS.md) and the
[constitution](../../../.specify/memory/constitution.md), especially Technical
Constraints → Testing → Who runs tests, Cross-Cutting Quality Bars → A. Scope
Discipline, and Development Workflow. Resolve its paths and read the returned
context chain; [AidataOps](../../scripts/CONTEXT.md) owns orchestration and its
tests, while [AidataFoundation](../../CONTEXT.foundation.md) owns these documents.

For the existing scheduler contract, read ADR-12 in the
[digest design](../specs/2026-07-10-aidata-digest-design.md) and Task 5 of the
[M5 plan](2026-07-11-aidata-digest-m5.md). For the already-delivered explicit
source-list guard, read T0 of the
[cleanup plan](2026-07-27-l1-l5-cleanup.md). Those historical plans provide
intent, not current manual-test commands, tolerated failures, or live-run
authority. This companion does not select a different Spec Kit feature or amend
the constitution.

## Intent and interface

The scheduler-visible runner has an independently copied orchestration body.
Editing the repository body can therefore leave scheduled execution stale.
Keep the copied artifact as a stable launcher and place orchestration in one
versioned pipeline. After a separately authorized one-time launcher deployment,
pipeline updates in the configured checkout will take effect without recopying
the launcher. Source delivery alone cannot establish that live transition.

The public entrypoint remains `aidata/scripts/aidata_digest_run.sh`. Preserve
its shebang, shell-option setup, existing `AIDATA_HOME` default, quoted directory
selection and root-failure behavior. Its final command becomes exactly:

```bash
. scripts/aidata_digest_pipeline.sh "$@"
```

This ordinary, unconditional Bash builtin runs the implementation in the same
shell and selected directory. It preserves arguments, stdio and inherited
`-e`/`-x` without a second interpreter or another `BASH_ENV` evaluation. Keep it
outside conditional or `||` wrappers, which would suppress inherited errexit.
The implementation file is not a new public entrypoint.

Move the complete existing body after directory selection to
`aidata/scripts/aidata_digest_pipeline.sh`; option setup and `cd` occur only in
the launcher. Preserve every command, source and stage order, date calculation,
timeout discovery/fallback, flag, output and existing failure behavior, including
the final command's exit result. This is relocation, not a retry, stale-data or
exit-status repair. Review every relocated statement and every non-commentary
byte changed against the immutable baseline. Relocation may change diagnostic
source paths/line numbers; tracing remains enabled, not byte-identical.

## Files in scope

| Path (repository-relative) | Owning leaf | Permitted change |
|---|---|---|
| `aidata/scripts/aidata_digest_run.sh` | AidataOps | Stable launcher and relevant comments |
| `aidata/scripts/aidata_digest_pipeline.sh` | AidataOps | New, relocated body |
| `aidata/tests/test_runner_sources.py` | AidataOps | Preserve source-list guard; additive seam regressions |
| `aidata/README.md` | AidataFoundation | Source-update versus prepared deployment explanation |
| `aidata/tech-context.md` | AidataFoundation | Only obsolete copy-synchronization prose |
| `aidata/docs/plans/2026-10-03-cron-runner-source.md` | AidataFoundation | This companion and task completion evidence |

The six paths above remain the implementation boundary. The additional planning
artifact is
[`aidata/docs/plans/2026-10-03-cron-runner-source/tasks.md`](2026-10-03-cron-runner-source/tasks.md),
owned by AidataFoundation; it records the exact tasks for repository intake and
adds no runtime behavior or implementation scope.

All other paths are out of scope, including the cron installer, job schema or
state, source configuration, L1–L5 implementation, card payloads, hooks, CI and
repository policy. Preserve tech-context metadata and layer/privacy/gate rules.
If a necessary adaptation falls outside the table, report it before expanding
the task. Existing issues, PRs and their writers retain ownership.

## Acceptance

The observable seams are the public launcher with configured `AIDATA_HOME` and
arguments, and an unchanged copied launcher resolving the pipeline from that
configured checkout. Observe subprocess exit status, stdout and stderr rather
than private Python functions or a scheduler registry.

- A synthetic baseline fixture locks the actual body's complete source and
  stage order, flags, timeout paths and existing failure behavior before moving
  production code. Retain the explicit source-list/config equality assertion
  against the relocated canonical body.
- A bounded source-freshness regression fails against the independent-copy
  baseline, then passes after relocation: the same copied launcher observes two
  configured pipeline revisions without replacement of that launcher. The
  fixture exercises the actual launcher, not a test-only facsimile.
- Additional synthetic cases prove spaced and relative configured roots,
  argument and result propagation, visible non-success when the implementation
  is missing (no old-copy fallback), and unchanged root-selection failure.
- Synthetic inherited-errexit, tracing and single-startup cases distinguish
  same-shell sourcing from a new Bash or a conditional dot invocation. Only a
  task-owned `BASH_ENV` fixture may be loaded.
- Independent review accounts for the relocated body and confirms that source
  order, date, deadlines, retry behavior and publish flags remain unchanged.
- Documentation distinguishes source commit, prepared launcher deployment,
  separately authorized live proof and rollback. Live-copy state remains
  unverified by this source task.

## Safety and verification checkpoints

Use task-owned synthetic files and process-boundary fakes only. Configure
`AIDATA_HOME` to the fixture; preserve the real identity and `HOME`. Select a
minimal credential-free subprocess environment without inherited model or
benchmark configuration and never dump environments. Even a baseline failure
must stay inside the fixture: no real CLI, model, app, network, warehouse,
browser data, cron registry or private configuration access. Install no tools
or dependencies and perform no deployment.

Tests remain hook-owned. Before the first hook run, inspect every selected leaf
and test for live effects and missing-private-config prerequisites, including
AidataFoundation tests selected by documentation changes. A missing or unsafe
prerequisite stops the affected step; it does not authorize changing selection,
the interpreter or the gate.

Verify `git hook run` support in the actual executor environment, retain the
normal `scripts/hooks` configuration, and use `git hook run pre-commit` for
red/green preflight without committing a failing state. The unchanged hook
selects staged paths but executes working-tree content. At each recorded
checkpoint, stage the relevant tests and all new files, require the full tracked
index to equal the working tree, and account for every untracked task file;
partial staging is not a tested-content proof. After any edit, restage and rerun
the same hook before binding review or commit to the candidate. Do not invoke
pytest suites directly, bypass hooks, weaken gates or reuse historical counts.

## Tasks

Read the actual [tasks.md](2026-10-03-cron-runner-source/tasks.md) when preparing
the Multica intake or executing a task. It is the single task-body source for
C0 → C1 → C2, with exact files, owning leaves, dependencies and completion
criteria. Bind each dispatched issue to its task ID and accepted document
version; do not use the unrelated active feature's tasks. The original Multica
TL → Planner → Fullstack → Reviewer route and one writer per task remain.
An artifact's existence is not issue creation, dispatch or workflow completion.

## Delivery and rollback boundary

After task intake and independent review, use ordinary commits/hooks, the normal
App publication identity and one PR per Multica issue. Bind required CI and
effective protected code-owner review to the actual PR head; refreshing main or
editing the candidate requires fresh applicable evidence. Source delivery is
complete only after the normal protected PR route, not after plan acceptance.

A reviewed source revert before deployment changes no live state. Any later
deployment must independently verify launcher/checkout provenance, preserve the
actual previous copy and a compatible checkout, and obtain authority for its
exact backup, apply, live-proof and rollback steps. This plan selects no live
checkout, branch, job, schedule or release policy, and supplies no executable
host-mutation recipe. Fixture success does not prove live parity or recovery.
