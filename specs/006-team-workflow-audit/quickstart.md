# Quickstart: Verify the Team Workflow Audit Slice

This quickstart is for implementation verification with neutral fixtures. It
does not run a real audit, use personal evidence, or contact CloudKit.

## 1. Confirm context ownership

Resolve every changed path before editing:

```bash
scripts/context/contexts <changed-path>
```

Expected implementation leaves are RepoInfra, AidataFoundation,
AidataL1L2, AidataL3, AidataL4, AidataL5, AIDashCore, DesignKit, AIDashUI,
AIDashApp, and aidashCLI. Unrelated CLI commands, `project.yml`, aidata
scripts/cron, generated data, and external audit sources are out of scope.

Recovery uses separate branches/PRs in this order: T020 RepoInfra watchdog,
the planning/constitution surface (T021), T019 AIDashUI compatibility, then the
nine-file AIDashCore T005 surface. They must never be combined. PR #202 is
evidence only.

T020 starts at exact base `2c75188c010ded876e9f3bb62412f011c7b9da14`.
Its candidate head must be different, must change
`scripts/ci/review-common.sh`, and may otherwise change only
`scripts/ci/tests/test_review_shell.py`. A base-equals-head submission is not a
T020 delivery and cannot advance T021.

The T002 repair is coordination-only and runs as five serial AidataL1L2 tasks:

```text
T001 → T022 strict decoder/model
     → T023 atomic snapshot+sidecar reader
     → T024 persisted identity/collision index
     → T025 neutral fixtures + full matrix
     → T026 collector/normalizer wiring
     → T003
```

Do not modify `team_audit_snapshot.py` before T025 is complete. Every new
adapter test path lands in both aidata context indexes with its owning task.

## 2. Exercise the manual boundary with fixtures

Configure the git-ignored Team Audit import directory to a neutral fixture
bundle and explicitly select the manual source:

```bash
./aidata/cli.py collect --source team_audit_snapshot
./aidata/cli.py normalize --source team_audit_snapshot
./aidata/cli.py merge
```

The default commands without `--source team_audit_snapshot` must exclude this
source. Missing configuration must report zero records without failure. No
command in this flow invokes Team Workflow Audit.

## 3. Let repository hooks verify layer-owned behavior

Commit and push normally. The configured pre-commit and pre-push hooks resolve
the changed paths and run the owning leaves' declared local gates; their
structured failure output is the verification signal. Do not run the resolver
test gates proactively or repeat a suite that a hook already ran.

If a hook fails, use its emitted `{layer, path, kind, detail, red_lines}` to
make a layer-local repair. A focused `scripts/context/run <emitted-layer>
--mode local` rerun is permitted only as diagnosis after that failure and does
not replace the next normal hook run.

AIDashApp and aidash heavy build gates are CI-only. Never run the host-based
AIDashApp test target locally. The hostless `AIDashAppLogicTests` target is a
diagnostic exception only when a concrete App-layer failure cannot be isolated
through the hook signal; it is not part of the normal task acceptance path.

## 4. Required neutral fixture proofs

- Baseline and incremental overview parts render different cohort/cursor
  sections, typed evidence coverage, locked axis-specific verdicts, and
  independent reconciled axes.
- Replay and overlap records deduplicate by stable identity; hash collision
  never overwrites and emits a separately keyed observation with accepted
  parent snapshot ID/hash.
- All six finding states and all locked verdicts round-trip.
- Feedback lineage preserves problem/delivery/release/observation state, and
  repeat metrics preserve every role, cycle/cause, five-case tagged
  role-specific, subject, and event value with reconciled non-negative totals.
- Case timelines embed ordered events/attempts; their stable case/event/
  attempt/role/cycle references resolve exactly and reject missing, duplicate,
  reordered, or foreign identities.
- Missing/unsafe mandatory artifact URLs reject publication; unsafe optional
  artifact/grill URLs are text; valid HTTPS URLs are actionable.
- Finding subject/responsibility and exact artifact-sidecar ID/content hash
  survive import, warehouse, query, payload, and rendering.
- Collision parent ID/hash/entity/disposition, artifact snapshot/sidecar
  relationships, typed grill links, full-report resolution, and externalized
  optional-entity bindings reject dangling or mismatched references.
- Final encoded payload boundary fixtures cover 262,144/262,145 bytes;
  mandatory P0/P1 findings and links have independently reconciled
  required/published counts and are never omitted or externalized, while
  oversized optional detail requires a typed full-report reference.
- Acknowledgement and approval produce one append-only receipt each and leave
  the source snapshot unchanged.
- No-op UI environments, write failure, missing source, and missing optional
  artifact cases degrade without crash; missing mandatory artifacts reject
  publication without crashing.
- Spies observe no audit invocation, cron registration, source mutation,
  issue/run mutation, agent dispatch, or remediation execution.

The complete T005 proof-to-file mapping is
`contracts/t005-acceptance-matrix.md`; every matrix row must have fresh evidence
inside the original nine-file AIDashCore allowlist.

The complete AidataL1L2 import proof is
`contracts/t002-acceptance-matrix.md`. T022–T025 prove the decoder, atomic
reader, restartable index, and neutral fixtures through their interfaces;
T026 closes only the public collector/normalizer wiring rows. All five tasks
must obtain their own normal routing-audit and AidataL1L2 hook evidence.

## 5. CI evidence

The implementation PR must obtain the repository-required CI checks, including
macOS/iOS App builds, CLI build, Core/package tests, aidata pytest + ruff, and
the repository review target. CI, not a local host-based test, is the source of
truth for assembled App/CLI build compatibility.
