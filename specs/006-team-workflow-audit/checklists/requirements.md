# Specification Quality Checklist: On-Demand Team Workflow Audit

**Purpose**: Verify Specify-stage completeness before Plan.
**Created**: 2026-08-30
**Feature**: `specs/006-team-workflow-audit/spec.md`

## Content Quality

- [x] No implementation stack or file-path choices appear in user stories or success criteria.
- [x] User value and operational boundaries are stated before technical requirements.
- [x] Every story is independently demonstrable and prioritized.
- [x] Baseline, incremental, missing-evidence, invalid-link, duplicate, and failure paths are covered.

## Requirement Completeness

- [x] No unresolved clarification marker remains.
- [x] Every requirement is testable and uses mandatory language.
- [x] Required entities and stable identities are defined.
- [x] The three core axes and separate Task Effectiveness axis cannot be conflated.
- [x] All six finding lifecycle states are explicit.
- [x] Feedback lineage and per-role repeat metrics preserve every source-required identity and breakdown.
- [x] Typed cohort/cases, evidence coverage, axis-specific verdicts, ordered timeline events/attempts, and five role-repeat variants are explicit.
- [x] Release channel, collision disposition, grill/full-report/externalization, and all SHA-256/referential invariants are locked.
- [x] Collision observations are append-only and independently keyed without mutating accepted snapshots.
- [x] Exact payload-size, mandatory-link reservation, and optional externalization behavior are deterministic.
- [x] T005 maps type, scalar, cross-field, referential, round-trip, public-API, fallback, and exact 262,144/262,145-byte proofs to its exact eleven-file Types+Service allowlist.
- [x] FR-020–FR-025 stabilize every remaining Round 2 correctness/proof finding and map each proof to its owning Core, aidata, or AIDashUI task/test files.
- [x] The former executable T002 is coordination-only; T022–T026 form a serial contract-first AidataL1L2 graph with non-overlapping files and interfaces.
- [x] T022 directly proves D18–D26 and T025 repeats them with neutral bundles: exact timeline order/back-pointers/UTC chronology, complete artifact event/case/finding ownership, structured arbitrary-size integer handling, limited empty/short baseline behavior, and contract-wide required-key/null/type/duplicate/integer-impostor rejection.
- [x] `contracts/team-audit-snapshot-v1.md` pins the complete raw `snapshot.json` version, nested key allowlists, JSON types/nullability, and locked vocabularies; T022 need not infer a producer schema.
- [x] `TeamAuditIdentityIndex` is derived and rebuildable from authoritative append-only raw history; cache-only state never grants acceptance.
- [x] `ArtifactManifestEntryWire` is distinct from enriched normalized artifacts, and the canonical raw entry alone defines the 65,536/65,537-byte gate and artifact identity hash.
- [x] A typed reference catalog makes finding/case/event/evidence/subject/revision references locally resolvable across independently decoded card parts.
- [x] A typed artifact catalog entry makes an overview full-report reference independently resolvable by kind, ID, hash, URL, and sidecar.
- [x] Lineage uses SHA-256 while `mergeSHA` uses this repository's lowercase 40-hex Git SHA-1 object format.
- [x] The URL-policy seam is architecture-compliant: Models owns structural data/helpers, the Validation Service supplies the protocol witness, and existing `SchemaValidator`/`URLPolicy` files remain unchanged.
- [x] Artifact acceptance distinguishes mandatory P0/P1 chains from optional P2/info chains and binds full reports/externalization by ID, hash, URL, and sidecar.
- [x] Normative proof requires exact equality for all eight variants, all three axis-scoped insufficient-evidence values, Core structured error propagation, AIDashUI rendered fallback, unsafe optional-string preservation, and exact valid mandatory byte fixtures.
- [x] Artifact sidecar grill fields and the aidashCLI action consumer are specified end to end.
- [x] L4 exposes immutable required inputs only; L5 computes final publication coverage, reconciles independent P0/P1-finding and mandatory-link count pairs, and US1 emits every mandatory finding/artifact.
- [x] Missing/invalid mandatory URLs reject publication; only optional artifact/grill links degrade to text.
- [x] Collision observations carry explicit accepted parent snapshot ID/hash.
- [x] Sidecar identity/exact byte hash persists through normalized, warehouse, query, payload, and collision contracts.
- [x] Finding subject ID and responsibility layer remain explicit through every layer.
- [x] Manual invocation and no-dispatch/no-remediation boundaries are explicit.
- [x] Acknowledgement/approval semantics supersede the older event allowlist only for audit cards.
- [x] Assumptions and non-goals prevent hidden implementation authority.

## Outcome Verifiability

- [x] Success criteria are measurable without prescribing an implementation.
- [x] Every story has a fixture- or spy-based independent test surface.
- [x] Immutable ingestion and deduplication have observable pass/fail outcomes.
- [x] Approval receipt behavior distinguishes recorded intent from canonical snapshot state.

## Readiness

- [x] Repository constitution conflict is resolved by constitution 1.13.0.
- [x] Constitution publication requires its own `constitution: <change>` PR and PR-body migration note; planning review is not a substitute.
- [x] T020/PR #204, T021/PR #210, and T019/PR #215 are completed historical prerequisites and are not schedulable recovery work.
- [x] T001 is completed/non-schedulable at `d75b14dfbfd7876610782479ec3f94d036c8efd0`, and the T022 dependency edge is explicitly satisfied.
- [x] The exact planning commit receiving PASS is the T005 implementation base (or is byte-identically preserved in an approved descendant); parent `fdace13d…` alone is not valid.
- [x] The registered MY-1522 workspace and candidate `12577b03c866c73c53fa23d236d2005a68790358` are preserved evidence; no new implementation starts before exact revised-planning PASS, base pinning, and a fresh Team Lead handoff.
- [x] The T022 recovery is a semantic forward-port of accepted package `1ba0062bb2597efd91c46b8de9080b53b8484da1` onto current-main base `bdf1435fe7d3d9c4da43ed4297cbc24482447b46`; newer FR-020–FR-025/T005 work is preserved and T023 remains gated on accepted T022.
- [x] HTTPS-only artifact and grill entry-point behavior agrees with the repository URL policy.
- [x] The specification is ready for Plan-stage architecture and contract design.
