# Research: Minimal CI-Gated TestFlight Release

## R1 — Canonical cross-app pattern

**Decision**: Use Owner decision B on MY-1777 as the canonical control-flow
shape for all three apps, while keeping AIDash's runner, secrets, lane,
keychain, path allowlist, and gates repository-specific.

**Why**: Two implementation review rounds on revision 3 exposed expanding
privilege-boundary and workflow-harness complexity. The Owner chose scope
reduction rather than another repair round.

## R2 — One release job and ordinary write permission

**Decision**: Use one serialized self-hosted release job with job-level
`contents: write`; do not design a hosted provenance job or CAS-only permission
boundary. The final marker update still uses the observed ref as a compare-and-
swap guard inside that one job.

**Safety retained**: A job-level event guard validates exact workflow path/name,
same-repository push, successful `main`, and candidate format. The job checks
official-main reachability and pins the exact candidate before signing secrets
or Fastlane steps. Checkout uses full history.

**Accepted tradeoff**: The write permission exists for the job rather than a
dedicated marker-only boundary. This is an explicit Owner decision, not an
accidental omission.

## R3 — Marker-only relevance

**Decision**: Keep only `testflight/last-released`. Existing ancestor state uses
`marker..candidate`; equality skips; non-ancestor state fails closed. An
automatic run with no marker fails closed; manual `force=true` may bootstrap
the exact pinned current-main candidate. Force otherwise bypasses relevance
only.

**Why**: This matches the literal marker-to-head minimal contract, avoids
inventing an implicit cursor when no marker exists, and retains accumulated
relevance without queue, skip, attempt, recovery, or quarantine records.

## R4 — Preserve the lane as the release boundary

**Decision**: Treat successful return of unchanged `fastlane ios beta` as the
upload-success boundary, then compare-and-swap the observed marker to the exact
candidate using a lease against the exact observed remote marker object ID (or
expected absence for bootstrap). Marker compare-and-swap success is the
successful release outcome; rejection means this run did not mutate the marker
and fails after upload.

**Preserved**: ASC global build number, runtime profile fetch, five secrets,
login keychain, internal distribution behavior, tracked marketing version.

**Removed from revision 3**: workflow-owned group preflight/readback,
`release:minor`, annotated metadata, and terminal phase taxonomy.

## R5 — Cleanup follows each repository's signing model

**Decision**: AIDash may use only `security unlock-keychain` on
`login.keychain-db` for signing. It must not run
`security set-keychain-settings`, mutate the user search list, or run
`security set-key-partition-list`. Signing relies on the runner's preconfigured
certificate ACL. If unlock was attempted, `always()` cleanup unconditionally
runs `security lock-keychain` while removing workflow-created temporary refs/
signing artifacts. After marker success, cleanup errors are caught and emit only
secret-free warnings; before marker success they cannot mask the earlier
failure.

**Why**: AIDash intentionally uses the runner login keychain, while sibling
repositories have different signing mechanics. Cross-app consistency applies
to release control flow, not signing internals. Warning-only post-marker cleanup
prevents a successful marker from contradicting a later failed run conclusion.

## R6 — Narrow verification surface

**Decision**: Replace the current manual-only regression with table-driven
relevance cases that extract and execute the exact production classifier block,
stable workflow-structure assertions, and verification-only `actionlint` over
the complete workflow. Delete rather than port the unpublished shadow-policy
suite; preserve every mandatory repository gate.

**Harness boundary**: Locate one stable production classifier step, fail on
missing/ambiguous extraction, and execute its exact Bash scalar in isolated
temporary Git repositories with temporary outputs. Do not copy the allowlist
into Python. Provision a pinned task-local `actionlint`, record its version, and
run `actionlint .github/workflows/testflight.yml` without a tracked dependency
or host-wide install.

**Why**: The Owner explicitly rejected an exhaustive workflow-policy harness.
The new tests must not recreate provenance, marker, version, distribution, or
outcome state machines in Python.

## R7 — One issue and four paths or fewer

**Decision**: Keep one RepoInfra task/issue/PR and the existing owned paths:
workflow, old test deletion, concise replacement test, and handoff guide.

**Why**: All paths resolve to `RepoInfra`, serve one release goal, and require
one protected-path review. Splitting would not create independent value.

## R8 — Delivery sequencing

**Decision**: Park revision-3 candidate `e8c353ce…`; do not publish or repair
it. Resume in the registered delivery workspace only after exact-revision
planning PASS and Team Lead handoff. MY-1692 gates merge, not post-PASS
implementation preparation.
