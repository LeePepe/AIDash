# Research: Minimal CI-Gated TestFlight Release

## R1 — Repository authority

**Decision**: Use repository-local rules and the `RepoInfra` layer.

**Evidence**: `AGENTS.md`, the constitution, `CONTEXT.md`, and
`scripts/CONTEXT.md` govern all declared paths. No shared-ci pin exists.

## R2 — Keep Spec 007

**Decision**: Revise the active Spec 007 artifacts instead of reopening
completed Spec 004 history or creating another feature directory.

**Evidence**: `.specify/feature.json` and the Spec Kit block in `AGENTS.md`
already select Spec 007. The Owner changed the approach, not the feature goal.

## R3 — Direct exact-head release job

**Decision**: Use one self-hosted job. Accept only a successful same-repository
`build` push on `main`, and checkout the event's exact `head_sha` with full
history. Keep manual dispatch against `main`.

**Evidence**: `build.yml` is named `build` and runs on push and pull request.
The push/same-repository guards keep the credentialed job on repository main,
while exact SHA checkout prevents a moving-tip substitution. The Owner
explicitly rejected a dedicated hosted provenance boundary for minimal v1.

## R4 — Marker-range relevance

**Decision**: Classify `git diff --name-only marker..head` with the existing app
path roots. Keep the public tag as the only durable release state.

**Evidence**: `workflow_run` has no native changed-path filter. The marker range
accumulates unreleased app changes without a cursor or skip record. Missing or
invalid marker state fails closed; retained manual force can bootstrap.

**Rejected**: First-parent bootstrap state machines, ancestry taxonomies,
queue/cursor/skip refs, and per-head journals.

## R5 — Production classifier with focused unit tests

**Decision**: Put a small Python 3.9-compatible classifier/CLI and its unit tests
in `scripts/ci/tests/test_testflight_relevance.py`; the workflow calls that
exact classifier.

**Evidence**: This keeps the final diff at four paths and avoids a test that
parses or simulates the entire workflow. Unit tests can exercise path matching
without shadowing permissions, triggers, marker logic, or step ordering.

**Rejected**: Porting the unpublished 542-line policy suite; duplicating the
allowlist in a separate test oracle; adding a fifth helper path.

## R6 — One permission boundary

**Decision**: Give the one job ordinary `contents: write` permission and move
the tag only after lane success.

**Evidence**: Serialization prevents concurrent release jobs. The Owner chose
this simple boundary over a CAS-only job/token design.

**Rejected**: Hosted permission staging, force-with-lease/CAS orchestration,
annotated marker metadata, and alternate durable state.

## R7 — Existing lane and strict secret scope

**Decision**: Reuse `fastlane ios beta` unchanged. Put all five secrets,
validation, keychain preparation, and lane execution on one build/upload step.

**Evidence**: The lane already owns global build-number allocation, signing,
upload, and internal distribution. Reimplementing those policies in the
workflow caused the superseded complexity. Step-only environment scope meets
the Owner's credential boundary without another job.

## R8 — Cleanup

**Decision**: A final `always()` step restores the prior keychain search list
and deletes only run-scoped temporary keychain files and local temporary tags.

**Evidence**: The existing workflow changes persistent keychain search/settings
state. Cleanup must run on success, skip, and failure and must not need secrets
or touch the remote marker.

## R9 — Workflow lint

**Decision**: Use actionlint as the requested workflow linter in addition to
focused classifier tests and normal repository gates.

**Evidence**: The repository has no current workflow-lint command and this
planning machine has no actionlint binary. Homebrew exposes actionlint 1.7.12.
Fullstack records the installed version and treats installation/lint failure as
a blocker; the plan does not falsely claim pytest validates Actions semantics.

## R10 — Exact implementation scope

**Decision**: One RepoInfra PR changes the workflow, replaces the manual-only
test with the focused classifier/test, and updates the handoff guide.

**Evidence**: Those changes fit the Owner's same-four-path ceiling and require
no Fastlane/project/product edits.

## R11 — Delivery gates and candidate preservation

**Decision**: Preserve `e8c353ce` locally and unpublished. Team Lead must create
a non-descendant publication line in the registered delivery lifecycle before
Fullstack resumes. MY-1692 and protected-path approval remain unchanged.

**Evidence**: Read-only inspection found the candidate clean, without upstream,
and absent from local remote-tracking refs. Publishing any descendant would
make the rejected commit reachable remotely.

## R12 — Failure policy and review budget

**Decision**: Any preflight/build/upload/marker error fails the run, leaves the
remote marker unchanged when failure precedes marker movement, and schedules no
retry. The revised implementation receives the normal two-round review budget;
round-2 failure is parked and reported to the Owner delegate without another
round or Owner escalation.

**Evidence**: This is the explicit `OD-2026-10-15-B` stop rule and prevents
another edge-case expansion cycle.
