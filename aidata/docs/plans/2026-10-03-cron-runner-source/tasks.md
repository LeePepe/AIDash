# Tasks: cron runner single-source repair

Status: document candidate for independent review; all tasks below remain
unchecked. No issue, source implementation, test, commit or deployment result
is implied by this artifact.

**Input:** [companion specification and plan](../2026-10-03-cron-runner-source.md).
**Immutable source baseline:** `f3088d834a7d1ab935bca78739de69c3c3455a71`.
**Story US1:** keep the scheduler-visible launcher stable while updates to the
versioned pipeline in its configured checkout become observable without
recopying the launcher, after a separately authorized initial deployment.

## Intake and execution contract

Read the companion's Read contract, Intent and interface, Acceptance, Safety and
verification checkpoints, and Delivery and rollback boundary before copying any
task into an issue. Those sections govern every task below. The task bodies
follow the repository's
[Multica task template](../../../../.specify/templates/tasks-template.md) and
[constitution](../../../../.specify/memory/constitution.md) §Development Workflow.

Use this explicit repository-relative tasks path in the original Multica
TL → Planner → Fullstack → Reviewer intake; leave the unrelated active feature
selector and historical plans unchanged. Record task ID → actual issue → owner
and dependency mapping in the normal handoff only after those objects exist.
No issue IDs are preassigned here. Fresh issue/PR/path-owner reconciliation is
required before dispatch; inactivity never transfers another task's ownership.

Fullstack owns test authoring and execution through the unchanged hooks,
including complete self-checks and reporting failures. The independent Reviewer
performs the existing read-only plan/spec review and exact-head source/spec/
architecture review; it does not execute or adjudicate tests, builds, lint or
CI, nor monitor the PR. Required verification evidence and protected delivery
remain mandatory through their existing owners.

| Task | Original task | Owning leaf | Hard dependency | Evidence mapping |
|---|---|---|---|---|
| T001 | C0 | AidataFoundation | Fresh document ownership/read contract | Accepted plan and task hashes, base and intake mapping |
| T002 | C1 | AidataOps | T001 | Behavioral acceptance bullets 1–5; exact-content hook and source-review evidence |
| T003 | C2 | AidataFoundation | T002 | Documentation acceptance bullet 6; source/deployment and rollback distinction |

There are no parallel task markers: C0 → C1 → C2 is serial, and C0/C2 share the
companion. Each leaf's implementation is an independently verified commit.

## [T001] C0 — Freeze the planning artifacts [US1]

- [ ] Freeze the companion and the literal task artifact for intake.

**Owning leaf:** AidataFoundation
([context](../../../CONTEXT.foundation.md)).

**Files in scope:**

- `aidata/docs/plans/2026-10-03-cron-runner-source.md`
- `aidata/docs/plans/2026-10-03-cron-runner-source/tasks.md`

**Files NOT to touch:** `aidata/scripts/**`, `aidata/tests/**`,
`aidata/README.md`, `aidata/tech-context.md`, `.specify/**`, `AGENTS.md`, contexts,
hooks, CI, historical plans and all other owners' files.

**Dependencies:** fresh base/path/issue/PR ownership reconciliation and the
companion Read contract. Existing in-flight owners remain unchanged.

**Functional acceptance:**

- Both artifacts describe the same fixed same-Bash method, six original
  implementation paths and two synthetic public seams. This additional tasks
  artifact is planning only, not a seventh implementation change.
- Independent plan/spec review has no unresolved substantive findings. Record
  exact document hashes/base and task-to-issue intake mapping for the later
  handoff; no method/seam approval is reopened.
- Every relative reference resolves; each task names files, leaf, dependency
  and checkable completion. No selector or policy amendment is required or made.
- Current preparation is static only: no hooks/tests/commit/dispatch. Publication
  is a later handoff with normal safety inspection and hook/delivery checks,
  not a docs-only exemption.

**Quality bars:** Constitution §Cross-Cutting Quality Bars, all applicable
sections; §Development Workflow and §Technical Constraints → Testing → Who runs
tests.

## [T002] C1 — Lock behavior and remove the independent body [US1]

- [ ] Preserve orchestration behavior while making the configured pipeline the
  single implementation source.

**Owning leaf:** AidataOps ([context](../../../scripts/CONTEXT.md)).

**Files in scope:**

- `aidata/scripts/aidata_digest_run.sh`
- `aidata/scripts/aidata_digest_pipeline.sh` (new)
- `aidata/tests/test_runner_sources.py`

**Files NOT to touch:** `aidata/scripts/aidata_digest_cron.py`, configuration,
L1–L5 business logic, `aidata/README.md`, `aidata/tech-context.md`, planning
artifacts, hooks, CI, policy and all live files.

**Dependencies:** T001/C0 accepted and bound to the intake; fresh baseline,
source-owner, dependency and selected-test safety checks. Keep the original
Multica execution route.

**Functional acceptance:**

- Follow the companion interface exactly: preserve launcher shebang/options/
  root selection; final unconditional `. scripts/aidata_digest_pipeline.sh "$@"`;
  relocate the complete post-directory-selection body without repeating setup.
  Preserve all commands, order, flags, outputs and existing failure behavior.
- First lock actual baseline behavior with synthetic process fixtures and keep
  source-list/config equality meaningful against the canonical body. Through
  the real pre-commit hook, record the bounded independent-copy regression red,
  then the minimal relocation green; add remaining cases in verified slices.
- Exercise the actual public launcher and unchanged copied launcher against two
  configured pipeline revisions. Cover spaced/relative roots, arguments/results,
  missing implementation and root failure, inherited errexit/tracing and a
  single startup evaluation, as specified by Acceptance bullets 1–4.
- Fullstack records all required hook results against exact content using the
  companion's full-index/working-tree agreement and restage/rerun rules. Even red
  fixtures remain task-local; no real CLI/model/app/network/data/cron access.
  A failing checkpoint is evidence, never a commit or permission to bypass gates.
- Independent source review accounts for every relocated statement and changed
  non-commentary byte against the immutable base (Acceptance bullet 5). Bind the
  candidate, self-check evidence and review to the same content; the ordinary
  commit passes hooks with only the three scoped paths and no live effects.

**Quality bars:** Constitution §Cross-Cutting Quality Bars, all applicable
sections; §Technical Constraints → Testing → Who runs tests. Keep full required
verification; no direct pytest suite or historical-count substitution.

## [T003] C2 — Explain the source/deployment boundary [US1]

- [ ] Replace obsolete copy-maintenance prose with the implemented source seam.

**Owning leaf:** AidataFoundation
([context](../../../CONTEXT.foundation.md)).

**Files in scope:**

- `aidata/README.md`
- `aidata/tech-context.md`
- `aidata/docs/plans/2026-10-03-cron-runner-source.md`

**Files NOT to touch:** scripts, tests, configuration, this task artifact,
tech-context metadata/layer/privacy/gate rules, hooks, CI, policy, historical
plans and all live files.

**Dependencies:** T002/C1 exact reviewed implementation and Fullstack behavior
evidence; fresh ownership and documentation-selected test safety checks.

**Functional acceptance:**

- Explain the single pipeline, prepared one-time launcher transition and later
  source updates. In tech-context, replace only obsolete copy-synchronization
  prose. Point to the companion for rationale instead of duplicating policy.
- Acceptance bullet 6 is met: source commit, deployment, live proof and rollback
  are distinct; live-copy state is unknown, not repaired by this source change.
  No executable host-mutation recipe or live-parity claim is added.
- Relative references resolve; public prose contains no private identity/host
  values; tech-context metadata remains byte-identical. The documentation commit
  receives independent review and Fullstack's normal selected-hook evidence.

**Quality bars:** Constitution §Cross-Cutting Quality Bars, all applicable
sections; §Development Workflow → No Identity in Version Control and §Technical
Constraints → Testing → Who runs tests.

## Completion boundary

Artifact acceptance, task implementation, protected PR delivery and authorized
live deployment are separate facts. Preserve the companion's delivery and
rollback requirements; a completed task or unchecked-to-checked edit is not
whole-workflow completion.
