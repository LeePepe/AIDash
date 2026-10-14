# Implementation Plan: Hidden Team Audit Core Residuals

**Branch**: `007-team-audit-core-residuals` | **Date**: 2026-10-14 | **Spec**: `specs/007-team-audit-core-residuals/spec.md`

**Input**: Decision B and the feature specification above.

## Summary

Add an internal, unregistered Team Audit contract substrate in one AIDashCore
Types file and close the only two unresolved correctness groups in one focused
invariant suite: exact-once present-artifact `caseID` resolution and the FR-024
full-report/externalization matrix. The work introduces no `CardType`, public
API, discovery, command, schema, UI, App, or aidata surface. Raw URL identity is
part of structural matching; the existing AIDashCore `URLPolicy` remains the
sole owner of scheme/host actionability and is unchanged.

## Technical Context

**Language/Version**: Swift 6.0 strict concurrency

**Primary Dependencies**: Foundation only; no new package or dependency

**Storage**: N/A; hidden Codable value contract only

**Testing**: Swift Testing in the existing AIDashCore test target, executed by
the repository's resolver-selected git hooks

**Target Platform**: macOS 26+ and iOS/iPadOS 26+ through AIDashCore SwiftPM

**Project Type**: Existing Swift package inside the AIDash workspace

**Performance Goals**: Linear identity lookup over the bounded reference
catalog; no new runtime/card path exists in this successor

**Constraints**: Exact two-path implementation diff; no registration or public
surface; no duplicated URL policy; neutral fixtures; no local `xcodebuild`

**Scale/Scope**: One AIDashCore resolver leaf, one vertical slice, one PR

## Baseline Evidence

Observed at `bdf1435fe7d3d9c4da43ed4297cbc24482447b46`:

- `CardType.swift` blob `b8f4134d0e5a96c8b12c82d3343e7ca0b632fe8f`
  contains ten cases and no `teamAudit`.
- `SchemaValidator.swift` blob
  `94022c00e1a95d095743dc2474b0c979c43e0873` discovers only
  `CardType.allCases`.
- `URLPolicy.swift` blob `0434cf51c9d2542b2183b7e4bf505cb01e07b63e`
  owns the existing HTTPS-with-host rule.
- The two allowed implementation paths do not exist on the baseline.
- The predecessor round-2 review closed every
  historical correctness/proof group except present artifact case resolution
  and the FR-024 full-report/externalization matrix.

## Constitution Check

### Pre-design gate

| Principle / bar | Result | Evidence |
|---|---|---|
| Constitution 1.13.0 | PASS | No amendment; audit invocation and remediation remain outside AIDash |
| Scope Discipline | PASS | One AIDashCore leaf, exactly two implementation paths, explicit forbidden siblings |
| Module direction | PASS | Hidden Types data has no dependency outside AIDashCore and no UI dependency |
| URL and Link Policy | PASS | Raw URL equality only; unchanged Core `URLPolicy` remains the policy owner |
| Schema locking | PASS | No `CardType`, schema list, CLI help, or XPC registration change |
| Public repository hygiene | PASS | Fixtures use invented IDs, hashes, and `example.com` URLs |
| Test coverage | PASS by plan | Every positive and one-field negative residual maps to the focused invariant suite |
| Hook-driven verification | PASS | Normal commit/push selects AIDashCore SwiftPM build/test; no manual duplicate suite |

### Post-design gate

PASS. The design stays inside the AIDashCore leaf and its Types role, exposes
no registered or public card interface, preserves URL-policy ownership, adds no
dependency, and maps every accepted criterion to one schedulable task and one
automated proof surface.

## Project Structure

### Documentation (this feature)

```text
specs/007-team-audit-core-residuals/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── tasks.md
├── checklists/
│   └── requirements.md
└── contracts/
    └── core-residual-matrix.md
```

### Source Code (repository root)

```text
Packages/AIDashCore/
├── Sources/AIDashCore/Models/Payloads/
│   └── TeamAuditPayload.swift
└── Tests/AIDashCoreTests/
    └── TeamAuditPayloadInvariantTests.swift
```

**Structure Decision**: Both paths route through
`CONTEXT.md → Packages/CONTEXT.md → Packages/AIDashCore/CONTEXT.md` to the
single AIDashCore layer. No context or manifest edit is required because the
existing leaf scope and SwiftPM source discovery already include both paths.

## Module and Seam Design

### Hidden Team Audit contract substrate

`TeamAuditPayload.swift` owns the minimum internal Codable/Equatable value
graph needed to express `SnapshotReferenceCatalog`, `ArtifactManifestEntry`,
`ArtifactReference`, `FullReportReference`, `ExternalizableEntityKind`, and
`ExternalizedEntityReference`, plus one structural-invariant entry point.

The substrate is intentionally not a `CardType` case and exposes no public
initializer or schema registration. It cannot be reached by production decode,
validation, enumeration, App, CLI, aidata, or UI code. A later coordinated
feature may promote and register it only under new authority.

### Exact-once reference rules

- Catalog identities are trimmed, non-empty, and unique.
- `ArtifactManifestEntry.caseID == nil` is valid.
- A present artifact `caseID` is trimmed/non-empty and matches exactly one
  `referenceCatalog.caseIDs` entry.
- A full report resolves to exactly one catalog artifact whose kind is
  `fullReport` and whose ID, hash, raw URL, sidecar ID, and sidecar hash all
  match.
- An externalized entity carries the already resolved report without any
  field substitution, a positive encoded byte count, the fixed reason, and one
  of the eight optional-only entity kinds.

### URL-policy boundary

The Types model compares raw URL strings only for immutable identity. It does
not parse a URL, accept a scheme, or call/duplicate `URLPolicy`. The existing
Core policy continues to own actionability. Because this successor has no
registered decode or consumer path, policy enforcement is deferred to the
separately authorized registration feature; it is not reimplemented here.

## Exact Implementation Boundary

### Allowed paths (complete)

1. `Packages/AIDashCore/Sources/AIDashCore/Models/Payloads/TeamAuditPayload.swift`
2. `Packages/AIDashCore/Tests/AIDashCoreTests/TeamAuditPayloadInvariantTests.swift`

### Forbidden paths (representative and binding)

- `Packages/AIDashCore/Sources/AIDashCore/Models/CardType.swift`
- `Packages/AIDashCore/Sources/AIDashCore/Models/EffectiveCardSize.swift`
- `Packages/AIDashCore/Sources/AIDashCore/Models/CardPayloadProtocol.swift`
- `Packages/AIDashCore/Sources/AIDashCore/Validation/**`
- `Packages/AIDashCore/Tests/AIDashCoreTests/CardTypeDecodeTests.swift`
- `Packages/AIDashCore/Tests/AIDashCoreTests/EnumRoundtripTests.swift`
- `Packages/AIDashCore/Tests/AIDashCoreTests/CardPayloadRoundTripTests.swift`
- `Packages/AIDashCore/Tests/AIDashCoreTests/SchemaValidatorTests.swift`
- `Packages/AIDashCore/Tests/AIDashCorePublicAPITests/**`
- Every other `Packages/AIDashCore/**` path, `Packages/AIDashUI/**`,
  `Packages/DesignKit/**`, `Apps/**`, `CLI/**`, `aidata/**`, `project.yml`,
  `.specify/**`, `specs/**`, `scripts/**`, `.github/**`, and context/constitution
  file during implementation.

## Vertical Slice and Task Graph

### US1 — Preserve trustworthy hidden references

One AIDashCore task creates the hidden value graph, implements both residual
invariant groups, and adds their complete focused proof. Splitting source and
test would leave no independently valid outcome, and both paths share one
resolver leaf and one atomic contract.

```text
exact plan-gate PASS
  → Team Lead immutable-base handoff
    → T001 (AIDashCore hidden contract + focused invariant proof)
      → implementation review / normal delivery

review-machinery dependency → later merge eligibility only
                               (no implementation edge or scope)
```

The graph is acyclic. There is no cross-layer contract, task, or parallel file
owner.

## Verification Strategy

- Implementation starts from the exact planning revision receiving `PASS`, or
  an explicitly approved descendant with byte-identical reviewed artifacts.
- Normal `git commit` and `git push` with `core.hooksPath=scripts/hooks` are the
  authoritative local verification. Resolver-selected AIDashCore gates run
  SwiftPM build and test; no manual duplicate suite and no `xcodebuild` run.
- The focused test file contains a named positive fixture and one independent
  negative for every matrix row in
  `contracts/core-residual-matrix.md`, including nil/valid/dangling case IDs,
  all six full-report binding fields, resolved-versus-externalized mismatch,
  positive/zero/negative byte counts, all eight enum values, and unknown decode.
- A diff-surface check against the approved base must equal the two allowed
  paths exactly. Existing `CardType` count remains 10 and forbidden anchor
  blobs remain unchanged.
- Fixtures use invented IDs, deterministic 64-lowercase-hex hashes, and
  `https://example.com/...`; no real issue, account, workspace, employer, or
  machine identifier appears.
- The implementation handoff captures local HEAD, pushed branch SHA, and PR
  `headRefOid`; all three must match before implementation review.

## Completion Conditions

- US1/AC1–US1/AC7 and FR-001–FR-009 map to passing named proofs.
- The exact implementation diff is the two-path allowlist and no accepted test
  is removed or weakened.
- `CardType.allCases.count == 10`; no Team Audit registration/discovery/public
  API exists.
- Structural matching covers every full-report field and rejects every
  independent mutation.
- Externalization accepts only the eight optional kinds, a positive byte
  count, the fixed reason, and the same resolved report.
- Hook-selected AIDashCore build/test succeeds; no local `xcodebuild` occurs.
- Constitution 1.13.0, recursive context routing, public-neutral fixtures, and
  AIDashCore URL-policy ownership are unchanged.

## Planning Publication and Implementation Base

This planning package is published as one commit containing only the feature
artifacts, `.specify/feature.json`, and the managed Spec Kit marker in
`AGENTS.md`. The review request pins the commit and every artifact blob.

If the single final review returns `PASS`, that exact commit is the recommended
immutable implementation base. If Team Lead must choose a later base, it must
explicitly prove every reviewed planning artifact blob is byte-identical. If
the review returns `NEEDS_WORK`, no second review or implementation is
authorized; the cited failure returns to Team Lead.

## Complexity Tracking

No constitutional violation or exception is required. The two-path boundary
is the minimum useful slice because the hidden Types file owns the invariant
and the matching same-layer test file owns all proof.
