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
- Reachability: candidate is an ancestor of freshly fetched official protected
  `main`

### Manual

- Event: `workflow_dispatch`
- Input: `force` boolean, default false
- Candidate: official protected `main` resolved once in hosted read-only
  provenance and pinned for the run
- `force=true` bypasses only app-path relevance
- No candidate selector, recovery mode, build-number override, or other input

## Privilege ordering

1. A hosted provenance job with read-only contents/actions permission uses a
   metadata-only Git repository and official remote. It does not use
   `actions/checkout`, execute repository content, enter a self-hosted runner,
   request contents write, or reference release secrets.
2. It validates the complete automatic/manual entrypoint contract and
   protected-main reachability, and emits one immutable candidate SHA.
3. Only a proven candidate may enter the self-hosted release job. Automatic and
   manual release jobs share concurrency group `testflight` with
   `cancel-in-progress: false`.
4. Under the lock and before candidate checkout or secret reference, the job
   refetches official protected `main` and `testflight/last-released`,
   revalidates candidate reachability, strictly validates the marker, and
   determines the comparison range and path relevance.
5. Contents-write authority is used only for the final public-marker
   compare-and-swap. Existing ASC readback credentials are first referenced,
   step-scoped, for group existence after provenance, marker, ancestry, path,
   and version preflight; signing/keychain material remains step-scoped to the
   subsequent release path.

## Sole durable release state

- `refs/tags/testflight/last-released` is the only durable release-progress
  state.
- The workflow MUST NOT create a queue-start, queue/cursor/skip, attempted,
  confirmed, quarantine, recovery, or any other operational ref. It MUST NOT
  use an artifact, cache, database, issue, or external record as a second
  release cursor.
- The concurrency group is a lock, not a queue. GitHub may replace an older
  pending run; the contract does not promise an upload or terminal workflow
  summary for every intermediate head.
- A skipped or failed run leaves the marker unchanged. With an existing
  ancestor marker, a later descendant evaluates the accumulated
  `marker..candidate` range and can carry forward a relevant intermediate
  change. With no marker, a later candidate uses only its own first-parent/root
  delta and does not carry an earlier head implicitly.

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

Every other path is non-triggering unless manual `force=true`.

## Marker relationship and comparison range

Under the concurrency lock, strictly parse and dereference the freshly fetched
marker before any release side effect:

1. **Marker missing, candidate has a first parent**: compare the first parent to
   the candidate. This is the only automatic bootstrap range.
2. **Marker missing, candidate is a root**: compare the empty tree to candidate.
3. **Marker equals candidate**: absolute no-upload skip, including manual force.
4. **Marker is an ancestor of candidate**: compare `marker..candidate`.
5. **Marker is a descendant of candidate**: stale-candidate skip; do not rewind.
6. **Marker and candidate are unrelated**: fail closed.
7. **Marker is invalid or cannot be dereferenced**: fail closed.

Normal automatic/manual execution proceeds only when the applicable range has
an allowlisted path. Manual `force=true` may override only that result. A
workflow-only enabling merge with no marker skips; the first later
app-relevant candidate can bootstrap from its own first-parent delta.

## Strict public-marker metadata

Annotated tag metadata is UTF-8 `key=value`, one field per line. Each permitted
key occurs exactly once; no empty value or unknown key is accepted.

`testflight/last-released` permits exactly:

```text
schema=1
marketing-version=<semantic version>
build-number=<positive integer>
```

The tag must dereference to a commit. Only a genuine lightweight
`testflight/last-released` tag is accepted as legacy and supplies no
version/build metadata. An annotated tag with absent, empty, malformed,
duplicate, or unknown metadata is invalid, never legacy.

## Version and build selection

1. Parse the tracked project marketing version from `project.yml`.
2. For a valid annotated marker, parse its marketing version; for a missing or
   genuine lightweight marker, use no marker version.
3. The baseline is the semantically greater project/marker version.
4. Query exact-candidate PR association. One proven merged PR with
   `release:minor` increments the baseline minor and resets patch to zero.
   Proven direct push/no PR means no bump; API failure or contradictory
   association fails closed.
5. Apply any version override only inside the isolated candidate checkout.
6. Preserve Fastlane's existing global App Store Connect maximum-plus-one
   allocator. No second build counter or reservation store is permitted.

## Upload, distribution, and marker movement

1. Normalize the existing group contract (default `Internal`; split on commas,
   trim, reject empty or duplicate names) and prove every exact group exists in
   ASC before Fastlane.
2. Require the complete existing five-secret set and runtime signing/profile
   path; do not introduce a new credential or secret.
3. Set `TESTFLIGHT_STRICT_UPLOAD=1` and invoke the existing `fastlane ios beta`
   lane on `[self-hosted, aidash-mac]` for the pinned candidate.
4. Parse exactly one existing Fastlane selected-build message. Zero or multiple
   values fails closed.
5. Independently query ASC for that exact version/build and require membership
   in every intended group. This is mandatory even when the lane exits zero.
6. Create the new annotated public marker locally, targeting the candidate and
   containing only the strict metadata above.
7. Compare-and-swap the remote marker against the fetched prior tag-object ID,
   or against confirmed absence for bootstrap. Blind force-push is forbidden.

The marker moves only after step 5 succeeds. The current Fastfile's strict-mode
configuration alone is not proof that a missing group received the build.

## Automatic/manual interaction

- Both entry kinds share the same concurrency group and marker rules.
- If an automatic run skips a same candidate as irrelevant, a later manual
  `force=true` run may release it because no marker moved.
- If either entry kind successfully advances the marker to the candidate, a
  later same-candidate run skips before upload regardless of force.
- If a newer candidate advances the marker before an older candidate executes,
  the older candidate observes a descendant marker and skips without rewind.
- No run changes another run's candidate or writes a per-candidate durable
  entry.

## Failure and pickup contract

- Any provenance, marker, ancestry, version, group, secret, tooling, signing,
  upload, distribution-proof, or marker-update failure is fatal for that run.
- Every failure leaves `testflight/last-released` unchanged and starts no
  automatic upload retry or rollback.
- A later trusted automatic candidate performs a new evaluation. With an
  existing ancestor marker, its `marker..candidate` range includes any failed
  relevant change. A later manual run pins current protected `main`; force may
  bypass only relevance.
- Upload/distribution and marker movement are not atomic. If external upload
  succeeds but proof or marker update fails, no durable workflow state records
  that result. A later run may upload again. The contract guarantees only that
  a SHA already recorded by the public marker will not upload again; it does
  not guarantee exactly-once upload for unrecorded external outcomes.
- No alternate build runner, credential, signing, upload, journal,
  reconciliation, quarantine, or recovery path is permitted.
- Stale or non-ancestral candidates never move the public marker backward.
- Replacement contract tests remain compatible with `/usr/bin/python3`,
  currently Python 3.9 under the RepoInfra local gate.

## Summary contract

Every run reaching eligibility evaluation records one secret-free summary for
its own candidate containing:

- entry kind and candidate SHA;
- source run ID when applicable;
- public marker shape/commit when available;
- comparison-range kind and relevance/force result;
- terminal outcome and reason;
- effective marketing version when selected;
- build number and GitHub run URL on success.

A platform-replaced pending run may expose only the platform cancellation. No
surviving run fabricates a per-candidate summary for it.
