# Contract: TestFlight Release Workflow

## Entrypoints

### Automatic

- Event: `workflow_run`
- Source workflow path/name: `.github/workflows/build.yml` / `build`
- Activity: `completed`
- Source event: `push`
- Source repository: `workflow_run.head_repository.full_name == github.repository`
- Branch: `main`
- Required conclusion: `success`
- Candidate: exact 40-hex `workflow_run.head_sha`
- Reachability: candidate commit is an ancestor of freshly fetched official
  protected `main`

### Manual

- Event: `workflow_dispatch`
- Normal input: `force` boolean, default false
- Normal candidate: official protected `main` resolved once in read-only
  provenance and pinned for the run
- `force=true` bypasses only app-path relevance
- Marker-only recovery inputs: an exact attempted candidate SHA plus exact build
  number; both or neither are required
- Recovery mode validates the attempt and ASC evidence, but cannot checkout or
  execute candidate content, invoke Fastlane, build, sign, distribute, or upload

## Privilege ordering

1. A hosted provenance job with read-only contents/actions permission uses a
   metadata-only Git repository and official remote; it does not use
   `actions/checkout` or execute repository content.
2. It validates the complete automatic/manual entrypoint contract and protected-
   main reachability before any contents-write token, self-hosted job,
   candidate checkout, release-secret reference, signing, or upload.
3. An ungrouped admission job is the first write-capable job and may write only
   the queue boundary/entry refs below. It receives no release secrets and
   executes no candidate content.
4. Only after durable admission does the self-hosted drain job enter concurrency
   group `testflight` with `cancel-in-progress: false`.

## Durable queue and drain

- `.github/workflows/testflight.yml` contains exactly one literal
  `release-contract-schema: 1` sentinel. With no public marker, scan freshly
  fetched protected `main` first-parent history and require exactly one commit
  that introduces it. The immutable annotated `testflight/queue-start` boundary
  targets that deterministic activation commit, never the first admitted
  candidate.
- Concurrent boundary creators may produce different annotated tag object IDs.
  A create loser refetches and accepts the existing boundary only when its
  target and strict semantic metadata match the same derived activation commit;
  no winner-specific source-run metadata is permitted. Missing/multiple
  introducing commits, an activation commit later than the candidate, or
  lightweight/mismatched activation evidence fails closed.
- Each proven intent creates an annotated
  `testflight/queue/<source-run-id>-<source-run-attempt>-<candidate-sha>` tag
  pointing to the exact candidate before release concurrency.
- Queue creation is create-only. An exact existing ref/target/metadata tuple is
  an idempotent replay; any collision or disagreement fails closed.
- Under the concurrency lock and before candidate checkout or release secrets,
  the worker refetches state, revalidates every queue source through the Actions
  API, and rechecks protected-main reachability.
- It exhaustively paginates successful same-repository `.github/workflows/build.yml`
  `push` runs on `main` between the public marker (or queue-start) and the newest
  queued head. It materializes missing queue entries, fails closed on an
  incomplete range/API disagreement, de-duplicates candidate SHAs, and drains
  them in protected-main first-parent order.
- GitHub may replace a pending drain worker. This is not candidate cancellation:
  the durable entry remains, and a surviving worker drains it. A running worker
  is never cancelled.
- A queue ref is compare-and-swap deleted only after terminal skip, successful
  release/reconciliation, or safe supersession. Attempted-only state retains
  its queue ref and blocks descendants.

## App-relevant path allowlist

```text
Apps/AIDashApp/**
Packages/AIDashCore/**
Packages/AIDashUI/**
Packages/DesignKit/**
Configs/**
project.yml
fastlane/**
```

Every other path is non-triggering unless normal manual `force` is true.

## Mode-specific invariants

### Common

1. Entrypoint and selected-mode provenance is trusted and the exact candidate is
   reachable from protected `main` before any mode-specific privilege or ref
   mutation.
2. Queue/API reconciliation is complete and candidate order is proven.
3. Candidate resolves to the exact immutable queue target for normal release or
   attempt target for recovery.
4. Existing public marker dereferences to a commit and is an ancestor of the
   candidate; equality is an absolute skip.
5. No earlier unresolved attempted-only ancestor exists; recovery selects the
   exact attempted-only candidate it is resolving.
6. Applicable queue, marker, attempt, confirmation, and version metadata is
   strict, valid, and unambiguous.
7. ASC readback evidence required by the selected mode is exact and
   unambiguous.

### Normal release only

1. The intended internal-group list is normalized, non-empty, duplicate-free,
   and every exact group exists in ASC before the attempt.
2. Project/marker version and exact-PR label evidence is valid and unambiguous.
3. The five existing required release secrets are present.
4. Remote create-only `testflight/attempted/<sha>` is positively confirmed
   immediately before the sole lane invocation.
5. Candidate checkout, build, signing, Fastlane, distribution, upload, and
   postflight exact-build/all-group proof follow the declared release path.

### Marker-only recovery only

1. An existing valid attempted-only ref matches the exact operator-supplied SHA;
   no new attempt is created.
2. The operator supplies one exact positive build number, and ASC independently
   proves the attempt's exact version/build and every recorded group membership.
3. Only the existing ASC credentials required for readback are required; the
   normal five-secret signing/release preflight does not apply.
4. Recovery may create the matching confirmation and compare-and-swap the public
   marker, but performs no candidate checkout, Fastlane, build, signing,
   distribution, or upload.

No input bypasses the applicable common and mode-specific invariants. Manual
`force` bypasses only app relevance and never selects recovery behavior.

## Strict annotated metadata

Metadata is UTF-8 `key=value`, one field per line. Each permitted key occurs
exactly once; no empty value or unknown key is accepted. Every annotated tag
must point to the commit repeated by its `candidate` field where that field is
defined.

### Queue boundary

`testflight/queue-start` permits exactly:

```text
schema=1
boundary-kind=release-contract-activation
candidate=<40-hex commit>
```

The candidate and tag target are the unique first-parent commit that introduces
`release-contract-schema: 1`; source-run fields are forbidden.

### Queue entry

`testflight/queue/<run-id>-<attempt>-<sha>` permits exactly:

```text
schema=1
entry-kind=<automatic|manual>
source-run-id=<positive integer>
source-run-attempt=<positive integer>
candidate=<40-hex commit>
force=<true|false>
```

For automatic entries `force=false`. Ref components, tag target, metadata, and
the re-fetched Actions run must agree.

### Attempt

Create-only `testflight/attempted/<sha>` permits exactly:

```text
schema=1
candidate=<40-hex commit>
marketing-version=<semantic version>
groups=<canonical comma-separated non-empty names>
source-run-id=<positive integer>
source-run-attempt=<positive integer>
```

### Confirmation

Create-only `testflight/confirmed/<sha>` permits exactly:

```text
schema=1
candidate=<40-hex commit>
marketing-version=<semantic version>
build-number=<positive integer>
groups=<canonical comma-separated non-empty names>
source-run-id=<positive integer>
source-run-attempt=<positive integer>
```

Attempt and confirmation candidate/version/groups must match exactly.

### Public release marker

A successful annotated `testflight/last-released` permits exactly:

```text
schema=1
marketing-version=<semantic version>
build-number=<positive integer>
```

Only a genuine lightweight `testflight/last-released` tag is accepted as
legacy and supplies no version/build metadata. An annotated tag with absent,
empty, malformed, duplicate, or unknown metadata is invalid, never legacy.

## Upload, distribution, and confirmation

1. Normalize the lane's existing group contract (default `Internal`, split on
   commas, trim, reject empty or duplicate names) and prove every group exists.
2. Create and refetch the attempt record immediately before the lane.
3. Invoke `fastlane ios beta` at most once for that SHA, with
   `TESTFLIGHT_STRICT_UPLOAD=1`, using the existing secrets/signing/profile path
   and existing self-hosted `[self-hosted, aidash-mac]` release runner.
4. Parse exactly one existing Fastlane selected-build message. Zero or multiple
   values is ambiguous and quarantines the attempt.
5. Independently query ASC for that exact version/build and require membership
   in every intended group. This postflight proof is mandatory even when the
   lane exits zero.
6. Create and refetch the confirmation record.
7. Compare-and-swap the public marker against the fetched prior tag-object ID.
   Blind force-push is forbidden.

## Recovery and quarantine

- Confirmation exists, marker behind and ancestral: advance only the public
  marker by compare-and-swap. Invoke no checkout, Xcode, signing, or Fastlane.
- Confirmation exists, marker equal or descendant: do not rewind or invoke the
  lane; summarize and clean the safe queue entry.
- Attempt exists without confirmation: terminal quarantine for automatic and
  normal manual paths; retain state and block later descendants.
- Explicit marker-only recovery: require exact attempted SHA/build inputs and
  independently prove ASC version/build/all-group membership. It may create the
  matching confirmation and reconcile the public marker. It cannot upload or
  distribute.
- If exact ASC proof is unavailable, quarantine remains. Deleting the attempt
  or invoking the lane again requires a new Owner decision outside this
  contract.
- Ambiguous attempt/confirmation/marker push response is resolved by refetching
  and strict comparison. Ambiguity is never permission to repeat the lane.

## Summary contract

The eventual drain worker records one secret-free row per candidate containing:

- entry kind and candidate SHA;
- source run ID/attempt and queue state;
- public marker state/commit when available;
- terminal outcome and reason;
- effective marketing version when selected;
- build number and GitHub run URL on release or reconciliation.

A platform-cancelled pending worker is not a terminal candidate outcome; its
queue entry remains for the surviving worker's summary.

## Failure contract

- No automatic upload retry or rollback.
- No alternate build runner, credential, signing, or upload path.
- Missing intended group or exact-build membership is fatal; strict-mode
  configuration alone is not sufficient evidence.
- Invalid provenance fails before checkout/self-hosted/secrets.
- State-ref failure is fatal and follows the quarantine/reconciliation rules.
- Stale/non-ancestral candidates never move the public marker backward.
- Replacement contract tests remain compatible with `/usr/bin/python3`,
  currently Python 3.9 under the RepoInfra local gate.
