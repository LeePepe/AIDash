# Tasks: Hidden Team Audit Core Residuals

**Input**: Design documents in `specs/007-team-audit-core-residuals/`

**Organization**: One vertical slice and one AIDashCore layer task. The task is
not schedulable until the exact planning revision passes the single final plan
gate and Team Lead pins the immutable base.

## Phase 1: User Story 1 — Preserve trustworthy hidden references (P1)

**Goal**: Add an internal, unregistered Core value contract that closes the
present-artifact case reference and full-report/externalization residuals.

**Independent Test**: The focused invariant suite exercises every CR-001
through CR-022 row without adding a `CardType` or consumer surface.

- [ ] T001 [US1] Implement the hidden residual contract in `Packages/AIDashCore/Sources/AIDashCore/Models/Payloads/TeamAuditPayload.swift` and its complete proof in `Packages/AIDashCore/Tests/AIDashCoreTests/TeamAuditPayloadInvariantTests.swift`.

| Metadata | T001 |
|---|---|
| Owning layer / context | **AIDashCore** — `CONTEXT.md → Packages/CONTEXT.md → Packages/AIDashCore/CONTEXT.md`; `Packages/AIDashCore/tech-context.md` |
| Files in scope | `Packages/AIDashCore/Sources/AIDashCore/Models/Payloads/TeamAuditPayload.swift`; `Packages/AIDashCore/Tests/AIDashCoreTests/TeamAuditPayloadInvariantTests.swift` |
| Files NOT to touch | `Packages/AIDashCore/Sources/AIDashCore/Models/CardType.swift`; `EffectiveCardSize.swift`; `CardPayloadProtocol.swift`; `Packages/AIDashCore/Sources/AIDashCore/Validation/**`; all existing generic/public Core tests; every other AIDashCore path; AIDashUI; DesignKit; Apps; CLI; aidata; `project.yml`; `.specify`; specs; context; scripts; workflows; constitution |
| Contract | `spec.md` FR-001–FR-009 and `contracts/core-residual-matrix.md` CR-001–CR-022 |
| Interface boundary | Internal Codable/Sendable/Equatable Types value graph and structural invariant entry point only; no `CardType`, public API, schema dispatch, URL parser/policy, or consumer |
| Functional acceptance | Nil case binding passes; present case resolves exactly once; blank/duplicate/dangling cases fail. Overview and artifact-section reports resolve by exact kind/ID/hash/raw-URL/sidecar tuple; each one-field mismatch fails. Externalized report equals the resolved report; positive byte counts pass and non-positive fail; fixed reason and all eight optional-only kinds round-trip; unknown raw values fail and mandatory kinds do not exist. |
| Compatibility acceptance | Current ten-card registration/discovery/effective-size/schema behavior and every existing test remain unchanged; raw URL equality does not duplicate `URLPolicy`; fixtures are public-neutral. |
| Exact verification | Normal commit/push with configured hooks; hook-selected AIDashCore SwiftPM build/test succeeds. Diff against the approved base is exactly the two files. No manual duplicate suite and no `xcodebuild`. Local HEAD, remote branch, and PR head SHA match before implementation review. |
| Blocking edges / slice | Exact plan-gate PASS → Team Lead immutable-base handoff → T001. The review-machinery dependency affects later merge eligibility only. Serves US1/AC1–US1/AC7. |

**US1 checkpoint**: T001 passes every contract row while the card remains
unregistered and undiscoverable.

## Dependency Graph

```text
exact reviewed planning revision
  → Team Lead handoff
    → T001 [AIDashCore]
      → normal implementation review and delivery

review-machinery dependency → later merge eligibility only
```

The graph is acyclic. No `[P]` task exists because both files form one atomic
contract and one layer-owned slice.

## Acceptance Coverage

| Acceptance | Task / proof |
|---|---|
| US1/AC1, FR-002, SC-001 | T001 / CR-001–CR-003 |
| US1/AC2–AC3, FR-003, SC-002 | T001 / CR-004–CR-010 |
| US1/AC4, FR-004 | T001 / CR-011–CR-015 |
| US1/AC5, FR-005, SC-003 | T001 / CR-016 |
| US1/AC6, FR-006, SC-004 | T001 / CR-017–CR-019 |
| FR-007–FR-008 | T001 / CR-020 plus forbidden-path proof |
| US1/AC7, FR-001/FR-009, SC-005 | T001 / CR-021–CR-022 plus exact diff surface |

## Definition of Done

- T001 changes exactly the two declared files.
- Every CR-001–CR-022 row has a named focused proof or exact diff assertion.
- Existing card count remains 10; no Team Audit registration, discovery,
  public API, URL policy, or consumer is added.
- No accepted test is removed or weakened.
- Hook-selected AIDashCore gates pass on the implementation head.
- Exact SHA parity is established before implementation review.
- The predecessor workspace/candidates remain untouched.
