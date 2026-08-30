# Feature Specification: On-Demand Team Workflow Audit

**Feature Branch**: `006-team-workflow-audit`

**Created**: 2026-08-30

**Status**: Draft

**Input**: Display immutable Team Workflow Audit snapshots and record Owner acknowledgement or remediation-approval events without invoking or remediating the audit.

**Supersession**: For Team Workflow Audit cards only, FR-013 through FR-016
extend the user-event allowlist in `specs/001-core-briefing-cli/spec.md`
FR-020/FR-021. They do not broaden the app into a general input or workflow
execution surface.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Read a trustworthy audit snapshot (Priority: P1)

As the Owner, I can read the latest baseline or incremental Team Workflow Audit snapshot in my briefing and understand exactly what was audited, how complete the evidence was, what the audit concluded, and where evidence is insufficient.

**Why this priority**: A trustworthy read-only snapshot is the smallest useful outcome and the prerequisite for every finding or decision workflow.

**Independent Test**: Publish one neutral baseline fixture and one incremental fixture. Each renders its scope, mode-specific cohort or cursor, snapshot/sidecar provenance, limitations, evidence coverage, three core axes, separate Task Effectiveness, every P0/P1 finding, and all mandatory generic/team/P0/P1 artifact links without invoking an audit or changing source data.

**Acceptance Scenarios**:

1. **Given** an immutable baseline snapshot with a fixed cohort, **When** the briefing is opened, **Then** the Owner sees the scope, cohort identity and cases, instruction versions, evidence coverage, limitations, and independently reconciled Workflow Conformance, Workflow Fitness, Outcome Integrity, and Task Effectiveness summaries.
2. **Given** an incremental snapshot, **When** the briefing is opened, **Then** the Owner sees each source cursor and overlap window and can distinguish the incremental evidence from the original baseline cohort.
3. **Given** missing or redacted evidence, **When** the snapshot is rendered, **Then** the affected conclusion is shown as insufficient evidence and the UI does not infer a result from another axis.
4. **Given** a publishable snapshot with mandatory findings and artifacts, **When** the final briefing parts are packed, **Then** publication coverage is computed from those final parts and the Owner can read every mandatory finding/link with matching required/published counts.

---

### User Story 2 - Inspect findings and their evidence (Priority: P2)

As the Owner, I can inspect stable findings, case timelines, full feedback lineage, per-role repeat metrics, individual metrics, collision observations, and the generated Archify artifacts needed to understand an audit conclusion without exposing raw logs or personal content.

**Why this priority**: Summary counts are actionable only when the Owner can trace important findings to redacted evidence and the operating workflow.

**Independent Test**: Publish a snapshot containing findings across all six lifecycle states, one case timeline, complete feedback lineage, all five roles' repeat/cause/role-specific evidence, one collision observation, a team/repository relationship artifact, and P0/P1 event-chain artifacts. The rendered briefing exposes every required item and opens only validated HTTPS evidence links.

**Acceptance Scenarios**:

1. **Given** findings with stable fingerprints, **When** the Owner reads the audit card, **Then** each finding displays its subject identity, responsibility layer, independent axis, priority, lifecycle state, evidence references, and remediation owner without parsing those identities from its fingerprint or merging findings that share presentation text.
2. **Given** case and individual evidence, **When** the Owner expands the audit details, **Then** event IDs, timestamps, roles, attempts, complete per-role repeat/cause/role-specific metrics, problem-to-release observation lineage, and limitations remain attributable to their source identities.
3. **Given** Archify artifacts, **When** the Owner follows the generic workflow, team/repository relationship, or P0/P1 event-chain link, **Then** the validated artifact opens outside AIDash and preserves the finding fingerprint, event IDs, and revision evidence relationship.
4. **Given** a missing, malformed, non-HTTPS, or unverified mandatory workflow/relationship/P0/P1 artifact URL, **When** publication is attempted, **Then** the snapshot is rejected and no mandatory item is counted as published. For an optional artifact or grill URL, the label remains non-actionable text.
5. **Given** a rejected identity/hash collision, **When** the accepted snapshot is displayed, **Then** the Owner sees the independent collision observation through its explicit accepted-snapshot ID/hash parent while the accepted snapshot content/hash remains unchanged.
6. **Given** a mandatory overview, P0/P1 finding, or required artifact link cannot fit the card budget, **When** publication is attempted, **Then** the snapshot is rejected rather than truncated, omitted, or replaced by a full-report link.

---

### User Story 3 - Record a safe Owner decision (Priority: P3)

As the Owner, I can acknowledge a finding or approve it for a separately governed remediation workflow, see that my decision was recorded, and optionally follow a safe link to a grilling workflow without causing AIDash to dispatch or remediate anything.

**Why this priority**: Owner decisions close the observation loop, but they must preserve the app's narrow append-only feedback authority.

**Independent Test**: From an audit finding, append one acknowledgement and one remediation-approval event. Repeated taps are idempotent, canonical snapshot history remains unchanged, the UI shows the recorded decision, and spies confirm no audit invocation, issue mutation, agent dispatch, or remediation call occurs.

**Acceptance Scenarios**:

1. **Given** an open finding, **When** the Owner acknowledges it, **Then** AIDash appends one acknowledgement event keyed by the card and stable finding fingerprint and displays that the acknowledgement was recorded.
2. **Given** an open or acknowledged finding, **When** the Owner approves it for remediation, **Then** AIDash appends one approval event and displays that approval was recorded without representing the remediation as started or complete.
3. **Given** a snapshot whose canonical finding state is resolved, regressed, or superseded, **When** decision history is displayed, **Then** prior acknowledgement and approval events remain visible but do not rewrite the immutable snapshot state.
4. **Given** an optional grill-me or grill-with-docs HTTPS link supplied by the publisher, **When** the Owner selects it, **Then** AIDash opens the link only; it does not execute a skill, create an issue, or dispatch an agent.

### Edge Cases

- Duplicate snapshots with the same stable snapshot identity are ingested once; a conflicting body for an existing identity is rejected, recorded as an independently identified append-only import observation, and surfaced as a provenance limitation without overwriting the accepted snapshot.
- Incremental records replayed inside the overlap window deduplicate by stable source identity while retaining the source cursor and provenance.
- Unknown future finding states or axis values fail payload validation and render the existing graceful card fallback rather than being mapped to a known state.
- Empty cohorts, incomplete 20-case baselines, missing optional artifacts, and absent individual metrics remain renderable when accompanied by an explicit limitation; the UI never fabricates values.
- Decision-event persistence failure leaves the control unconfirmed and does not crash, optimistically claim success, or retry by dispatching work.
- Multiple devices may append the same logical decision; the displayed receipt deduplicates by finding fingerprint and decision kind while the underlying event history remains append-only.
- Evidence references and optional grill links are untrusted publisher content and follow the central HTTPS-only URL policy.
- A mandatory overview, P0/P1 finding, or required workflow/relationship/event-chain link that cannot fit the existing card payload limit rejects publication of that snapshot; it is never truncated or replaced by a generic report link. An oversized optional detail may be replaced only by an explicit externalized-entity reference to a validated full report.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST accept only explicit Team Workflow Audit snapshot input supplied to the data pipeline; it MUST NOT schedule, discover, or invoke the audit.
- **FR-002**: Snapshot ingestion MUST be append-only, redacted, and immutable, with stable snapshot and source identities, UTC timestamps, instruction-version hashes, artifact-sidecar identity/content hash, provenance, and limitations retained through every data layer and published payload. Snapshot and sidecar parsing and hashing MUST bind to the same observed file contents so a replacement race cannot pair content with another generation's hash.
- **FR-003**: Baseline snapshots MUST preserve the fixed cohort identity and cases; incremental snapshots MUST preserve a per-source `(timestamp, stable identity)` cursor and overlap window without merging incremental evidence into the baseline cohort.
- **FR-004**: Replayed source records and snapshots MUST deduplicate by their stable identities across process restarts; conflicting content for an existing snapshot, child, or sidecar identity MUST NOT overwrite the accepted record and MUST produce an independently keyed, append-only collision observation with explicit immutable accepted-snapshot ID/hash parentage. Loss, corruption, or interruption of derived decision state MUST recover from append-only raw history and MUST never make rejected content authoritative.
- **FR-005**: The briefing MUST display scope, mode, a typed cohort with stable case identities or typed per-source cursors, instruction versions, reconciled evidence coverage, provenance, and limitations.
- **FR-006**: Workflow Conformance, Workflow Fitness, and Outcome Integrity MUST remain three independent core axes. Task Effectiveness MUST remain a separate fourth axis and MUST NOT be inferred from any core axis.
- **FR-007**: Each core-axis summary MUST use its axis-specific locked verdict, appear exactly once, and reconcile non-negative positive, negative, and insufficient-evidence counts to the total case count; Task Effectiveness MUST remain outside the core set and reconcile effective, ineffective, regressed, pending, and insufficient-evidence counts to its evaluated total.
- **FR-008**: The system MUST support stable finding fingerprints and exactly these lifecycle states: open, acknowledged, approved for remediation, resolved, regressed, and superseded.
- **FR-009**: Findings MUST retain explicit `subjectID` and `responsibilityLayer` fields, plus axis, priority, verdict, evidence references, affected cases, remediation owner, and current canonical lifecycle state; consumers MUST NOT recover subject/responsibility by parsing the fingerprint.
- **FR-010**: The briefing MUST display case timelines with ordered embedded events and attempts, full Task Effectiveness feedback lineage, and per-role repeat metrics. Timeline references MUST resolve exactly to stable case/event/attempt/role/cycle identities. Feedback lineage MUST retain problem, origin issue, delivery issue, PR/merge, typed release channel/build, observation, related-feedback, and effectiveness-state identities. Repeat metrics MUST retain actor role, cycle/cause breakdowns, a matching five-role tagged counter set, subject IDs, event IDs, and internally reconciled non-negative totals without collapsing roles into one score.
- **FR-011**: The briefing MUST expose a direct validated link for the generic operating workflow, every team/repository relationship artifact, and every P0/P1 current-state event chain supplied by the snapshot. Mandatory links MUST be reserved and published before optional details and MUST NOT be replaced by one full-report link.
- **FR-012**: Archify artifact links MUST preserve the relationship between finding fingerprint, event IDs, revision evidence, exact SHA-256 content hash, sidecar identity/hash, and the generated artifact. Typed grill links, full-report references, and externalized-entity references MUST resolve to the same immutable sidecar and matching full-report artifact. A missing or invalid mandatory workflow/relationship/P0/P1 URL MUST reject publication; only optional artifact/grill links degrade to non-actionable text. Raw artifact entries MUST exclude importer-derived fields; canonical raw-entry UTF-8 size 65,536 MUST be accepted and 65,537 MUST reject a mandatory entry before raw append, while the complete-card limit remains independently authoritative. A typed full-report reference MAY externalize optional oversized details but MUST NOT substitute for any mandatory artifact or P0/P1 chain.
- **FR-013**: The Owner MUST be able to append an acknowledgement event or an approval-for-remediation event for a finding, keyed by the card identity and stable finding fingerprint.
- **FR-014**: Owner decision events MUST be append-only and idempotent per `(card identity, finding fingerprint, decision kind)` for repeated local actions.
- **FR-015**: Recording a decision MUST NOT mutate a prior snapshot or claim a canonical lifecycle transition; canonical finding state changes only in a later immutable snapshot that incorporates the event.
- **FR-016**: A remediation approval MUST mean only that approval was recorded. The system MUST NOT auto-remediate, mutate source issues or runs, create tasks, or dispatch agents.
- **FR-017**: Optional grill-me and grill-with-docs entry points MUST be typed fields in a publisher-supplied hosted-artifact sidecar with stable sidecar identity and exact sidecar content SHA-256; the sidecar identity/hash and untrusted link strings MUST persist through L1–L5 and payload provenance. AIDash MUST open only centrally validated HTTPS links and MUST NOT execute the workflow.
- **FR-018**: Invalid, incomplete, future-incompatible, or oversized payloads MUST fail or externalize according to the published size contract and MUST NOT crash, truncate an entity, silently coerce an unknown locked enum/evidence value, or exceed the 262,144-byte final serialized UTF-8 card limit. The received 262,144-byte value is accepted and 262,145-byte mandatory value is rejected. Mandatory overview/P0/P1/artifact records are non-externalizable; optional oversized details require a typed full-report reference.
- **FR-019**: Automated tests MUST cover strict nested decoding before storage; raw-versus-enriched artifact schemas, duplicate/nullable-key handling, independent artifact/sidecar hashes, and exact 65,536/65,537 canonical entry boundaries; single-read atomic snapshot/sidecar handling and filesystem races; restart/crash/corrupt-index recovery; immutable ingestion; sidecar identity/hash preservation and collision; independently indexed snapshot/child/sidecar deduplication and accepted-snapshot-parented collision observations; overlap replay; explicit finding subject/responsibility; feedback lineage; complete per-role repeat metrics; payload round trips and exact size boundaries; mandatory-link rejection/reservation; optional-link degradation/externalization; all finding states; baseline and incremental rendering; decision idempotency; manual-only invocation; and no-dispatch/no-remediation behavior.

### Key Entities

- **Team Audit Snapshot**: Immutable, redacted audit publication with stable identity, scope, mode, instruction versions, baseline cohort or incremental cursors, summaries, evidence, findings, artifacts, and limitations.
- **Audit Axis Summary**: Reconciled counts and verdict for one independent core axis or the separate Task Effectiveness axis.
- **Audit Finding**: Stable fingerprint, axis, priority, verdict, affected evidence and cases, lifecycle state, and remediation owner.
- **Audit Case Timeline**: Ordered redacted events and attempts tied to stable case, actor-role, cycle, delivery, release, and observation identities.
- **Feedback Lineage**: Stable problem-to-delivery-to-release-to-observation chain with pending/effective/ineffective/regressed state.
- **Agent Repeat Metric**: Per-role common counters, cycle/cause breakdowns, role-specific counters, and supporting subject/event identities.
- **Import Collision Observation**: Independently keyed append-only record of an identity/hash conflict; carries immutable accepted-snapshot ID/hash parentage and accepted/rejected entity hashes without retaining rejected content or mutating the accepted snapshot.
- **Artifact Sidecar**: Immutable manifest envelope with stable sidecar identity, exact sidecar content hash, artifact bindings, and optional grill links.
- **Archify Artifact**: Validated external representation of a generic workflow, team/repository relationship, or P0/P1 event chain with revision evidence.
- **Publication Coverage**: Reconciled required-versus-published mandatory artifacts, optional omission/externalization counts, and an optional typed full-report reference.
- **Owner Decision Event**: Append-only acknowledgement or remediation-approval receipt targeting a stable finding; it records intent but grants no execution authority.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Every required field from valid baseline and incremental fixtures—including feedback lineage and complete per-role repeat metrics—is visible or reachable in the rendered briefing, with zero cross-axis or cross-role inference.
- **SC-002**: Replaying identical snapshots and overlap records before or after process restart produces one accepted record per snapshot, child, and sidecar stable identity; each conflicting immutable identity produces zero overwrites/rejected bodies and one idempotently merged collision observation per source observation ID, joined to exactly one accepted snapshot ID/hash parent. Restart after lost/corrupt derived state or interruption produces the same accepted result from append-only raw history.
- **SC-003**: All six finding states and every axis verdict round-trip through publication and render without free-form fallback.
- **SC-004**: Repeating acknowledgement or approval on the same finding produces one displayed decision receipt per decision kind and leaves the original snapshot byte-for-byte unchanged.
- **SC-005**: Automated boundary tests observe zero audit invocations, scheduled registrations, source mutations, issue/run mutations, agent dispatches, or remediation calls.
- **SC-006**: Every missing/invalid mandatory artifact URL produces zero published snapshot/card output, every invalid optional artifact/grill URL remains non-actionable text, and every valid HTTPS Archify/grill URL opens through the central URL policy.
- **SC-007**: Boundary fixtures prove a canonical raw mandatory artifact entry at 65,536 bytes is accepted and 65,537 is rejected before raw append; independently, an encoded card at 262,144 bytes is accepted, 262,145 bytes is rejected or externally referenced only when optional, `publishedP0P1FindingCount` exactly equals `requiredP0P1FindingCount`, and each published mandatory workflow/relationship/P0/P1-chain count exactly equals its corresponding required count.

## Assumptions

- The Team Workflow Audit producer remains a separately invoked workflow and supplies schema-conformant, already-redacted JSON plus generated Archify artifacts.
- The first baseline normally contains the source contract's fixed 20-case cohort; a smaller eligible population is accepted only with an explicit limitation and is not padded with fabricated cases.
- AIDash records Owner decisions through its existing append-only user-event path; a later audit run may consume those events and publish a new canonical finding state.
- Artifact generation and source-evidence verification happen before publication. AIDash validates link safety but does not regenerate or repair Archify output.
- No new non-Apple Swift dependency or Python dependency is required.

## Non-Goals

- Invoking, scheduling, or configuring Team Workflow Audit.
- Mutating source issues, runs, repositories, logs, or audit snapshots.
- Automatically creating remediation work, choosing a remediation owner, or dispatching an agent.
- Reproducing raw daemon/session logs or exposing unnecessary personal content.
- Generating or hand-editing Archify JSON, HTML, SVG, or evidence links inside AIDash.
