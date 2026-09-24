# Research: On-Demand Team Workflow Audit

## Decision 1: Introduce one typed `teamAudit` card with bounded section variants

**Decision**: Add one schema-locked `teamAudit` CardType. Its payload has a
small common envelope and one of eight section variants: `overview`,
`findings`, `caseTimelines`, `individualMetrics`, `feedbackLineage`,
`agentRepeatMetrics`, `importObservations`, or `artifacts`. A snapshot may
publish multiple cards with deterministic IDs and `partIndex`/`partCount`.

**Rationale**: Existing generic cards cannot preserve finding fingerprints,
six lifecycle states, four independent audit axes, event chains, and Owner
decision targets without lossy text conventions. One variant-based module
keeps the interface smaller than several audit-specific CardTypes, while
bounded parts respect the exact 262,144-byte per-card payload limit and the flat
Briefing → Container → Card hierarchy.

**Alternatives rejected**:

- Encode audit meaning into `digest`, `metric`, `relationship`, and `todoList`
  cards: loses stable typed identity and makes approval target parsing fragile.
- Add one CardType per audit section: enlarges the public schema and duplicates
  common scope/provenance behavior.
- Add a separate audit navigation surface: conflicts with today's single,
  glanceable briefing and is unnecessary for the requested outcome.

## Decision 2: Keep audit invocation outside AIDash with an opt-in manual source

**Decision**: Add `team_audit_snapshot` to a new manual-only source registry.
It is accepted only when the operator explicitly supplies
`--source team_audit_snapshot`; the default collect/normalize source set and
all cron scripts remain unchanged. An empty import directory degrades to zero
records.

**Rationale**: The audit source contract requires explicit invocation, while
aidata already provides an L1–L5 ingest path. A manual source lets AIDash import
completed snapshots without gaining the authority or code needed to run the
audit.

**Alternatives rejected**:

- Add the source to the normal scheduled collection set: obscures the manual
  boundary and weakens no-auto-trigger tests.
- Call the audit skill from aidata or the app: violates source authority and
  the no-dispatch/no-remediation requirement.
- Read directly from a hardcoded checkout: non-portable and forbidden by
  repository identity/path rules.

## Decision 3: Preserve immutable evidence through normalized relational facts

**Decision**: The adapter validates and hashes the source bundle, L3 stores
immutable snapshot and child facts keyed by stable source identities, L4
exposes named read-only queries, and L5 maps only L4 output into card payloads.
Same identity plus same hash is an idempotent replay; same identity plus a
different hash appends an independently keyed collision observation and never
overwrites or annotates the accepted snapshot fact. Every observation carries
the accepted parent snapshot ID and snapshot content hash, so snapshot-scoped
child collisions join unambiguously.

**Rationale**: This follows aidata's declared layer direction, retains
provenance, and lets every UI value be traced back to an accepted immutable
record. It also keeps overlap-window deduplication at the stable-identity seam.

**Alternatives rejected**:

- Store the entire JSON blob only: makes query grain, dedupe, and evidence
  reconciliation opaque.
- Parse directly in L5: creates an empty-shell card without L1–L4 provenance.
- Update rows on replay: violates immutability.

## Decision 4: Preserve feedback lineage and repeat metrics as typed views

**Decision**: Carry the source `feedback_lineage` and `agent_repeat_metrics`
records through dedicated relational grains and dedicated payload sections.
Feedback lineage retains problem, origin/delivery, PR/merge, release/build,
observation/related-feedback, and pending/effectiveness identities. Repeat
metrics remain per role with complete common counters, cycle/cause breakdowns,
role-specific counters, and supporting subject/event identities.

**Rationale**: Reducing either source record to generic numerator/denominator
rows loses the identities needed to judge delivery trust and repeated workflow
activity. A typed module hides storage joins while keeping the source contract
intact at the card interface.

**Alternatives rejected**:

- Fold lineage into case timelines: loses problem-to-release grain and pending
  effectiveness states.
- Collapse repeat metrics across roles: turns descriptive evidence into an
  unsupported personnel score and violates the source counting identity.
- Preserve role-specific data as untyped display JSON: moves source-schema
  interpretation into the view and weakens validation.

## Decision 5: Extend the existing append-only `UserEvent` interface

**Decision**: Add two locked action raw values:
`auditFindingAcknowledged` and `auditFindingRemediationApproved`. Both target
the stable finding fingerprint through `itemRef`, carry `cardType=teamAudit`,
and are idempotent per `(cardId, itemRef, action)` in the App writer. UI emits
intent through environment values; only AIDashApp persists.

**Rationale**: The existing UI-intent → App-writer seam already has two real
adapters: the production SwiftData/CloudKit-backed writer and test/no-op
environment adapters. Reusing it concentrates append-only, offline, dedupe,
and graceful-failure behavior behind the established interface. Constitution
1.13.0 explicitly authorizes these receipts while denying execution authority.

**Alternatives rejected**:

- Mutate finding state in the briefing payload: app would author agent content
  and rewrite an immutable snapshot.
- Introduce a second audit persistence path: duplicates CloudKit authority and
  adds a shallow interface.
- Encode approval as `done` or `star`: destroys action semantics.

## Decision 6: Use a hosted artifact sidecar and the central URL policy

**Decision**: A publishable manually imported bundle contains a typed artifact
sidecar envelope with schema version, stable sidecar identity, exact sidecar
content SHA-256, snapshot identity, artifact entries, and optional
`grillMeURL`/`grillWithDocsURL` strings. Import may retain a missing sidecar as
a limitation, but publication waits for mandatory entries. Each artifact binds
a stable identity and content hash to its snapshot, finding/case identities,
evidence event IDs, revision evidence, and an HTTPS URL. An unsafe/missing
mandatory artifact URL rejects publication; only optional artifact/grill URLs
remain visible as unavailable text. Grill links only open a browser destination.

**Rationale**: The upstream evidence schema mandates Archify outputs but does
not define a portable URL field. The repository rejects `file:` and custom
schemes. A sidecar extends the import bundle without mutating the upstream
snapshot and keeps dynamic team/P0/P1 artifacts viewable on every device.

**Alternatives rejected**:

- `file:` paths to generated HTML: fail URL policy and are unavailable on
  iPhone/iPad.
- Embed arbitrary HTML/WebView content: expands security and rendering scope.
- Custom skill-launch URLs: constitution permits HTTPS only and the app must
  not dispatch work.

## Decision 7: Publish the latest snapshot inside today's briefing

**Decision**: L4 exposes immutable required entities and required-count inputs;
it never computes published/omitted/externalized results. L5 adds one audit
container for the latest accepted snapshot, packs the final cards, computes
`PublicationCoverage`, and emits in US1 a compact overview plus every P0/P1
finding, generic workflow, team relationship, and P0/P1 event-chain link.
Coverage reconciles P0/P1 findings independently from their event-chain links
through distinct required/published count pairs.
Those mandatory items are reserved before optional details. If the budget
cannot contain every mandatory part, publication is rejected. Optional
oversized details may externalize only to a typed validated full-report
reference; required records are never replaced by that report.

**Rationale**: This preserves the product's single-day, flat, five-minute
reading model and avoids an unrequested history/navigation product. Stable
snapshot identity and mode make baseline versus incremental state explicit.

**Alternatives rejected**:

- Add audit history/search navigation: outside current scope and constitutionally
  suspect.
- Put the full raw evidence JSON in one card: breaches payload budget and
  redaction/locality goals.

## Decision 8: Keep verification resolver- and hook-driven

**Decision**: Every implementation task commits and pushes normally with the
configured hooks. The hooks audit routing, resolve changed paths, and run the
affected leaves' declared local gates. A focused resolver rerun is used only to
diagnose an observed hook failure; the authoritative local evidence is the next
normal hook run. App and CLI heavy builds remain CI-only.

**Rationale**: This is the repository-declared verification contract and
avoids the forbidden host-based App tests and duplicate proactive suite runs.
The optional hostless App logic target is diagnostic-only after a concrete
failure, never normal acceptance or a substitute for CI App builds.

## Decision 9: Treat prior recovery gates as history and pin the reviewed plan as base

**Decision**: T020, T021, and T019 are completed history in parent
`fdace13d20ee0b28759c4853c82445fd4d913dcc` through merged PRs #204, #210, and
#215. They are not schedulable dependencies. The only active recovery edge is
`exact revised-plan PASS + published planning-base pin → Team Lead handoff →
T005`. The implementation base is the exact reviewed planning commit named by
the PASS verdict, or an explicitly approved descendant containing byte-identical
copies of all nine artifact blobs.

**Rationale**: The parent contains the completed compatibility and process
work, but it does not contain FR-020–FR-025. Using the parent alone would omit
the reviewed contract; including a later planning commit while diffing from the
parent would contaminate the eleven-file implementation surface. The delivery
protocol explicitly permits an unmerged reviewed planning commit as the base.
Team Lead can therefore reconcile the preserved workspace and candidate only
after pinning that exact reviewed revision in the handoff and delivery metadata.

**Alternatives rejected**:

- Dispatch T020/T021/T019 again: duplicates already-merged work and risks stale
  recovery branches.
- Keep `fdace13d…` as the T005 base: it lacks the reviewed recovery artifacts.
- Count planning files in the T005 implementation diff: violates the exact
  AIDashCore eleven-file surface.
- Re-review candidate `12577b03…` under the new plan: the prior verdict is
  revision-specific and the two-round implementation budget is exhausted.

## Decision 10: Put invocation-scoped supervision behind the existing shell seam

**Decision**: Keep `run_with_timeout` as the only caller-facing interface and
make `review-common.sh` a thin Bash 3.2 adapter to a new stdlib-only
`scripts/ci/review_process_supervisor.py` deep module. The module owns a
pre-release launch barrier, target-only unguessable capability, stable
`(pid,birthMarker)` ledger, one monotonic deadline, output relays, and bounded
TERM-to-KILL cleanup. Its private membership seam has Darwin, Linux, and
scripted deterministic adapters. The complete interface and failure ordering
are locked in `contracts/t020-process-supervisor.md`.

**Rationale**: The external interface stays small while lifecycle complexity
gains locality and direct fake-adapter coverage. Injecting capability ownership
before target release makes membership survive normal fork/exec/`setsid` and
reparenting without guessing from an orphan's name. Birth-marker revalidation
prevents PID reuse from turning retained identities into unrelated targets.
The parent-observed completion timestamp and fixed deadline resolve both the
original false-124 race and the late-exit fail-open race.

**Alternatives rejected**:

- Continue growing private Bash helpers: Bash 3.2 lacks the process identity,
  event, and test-adapter primitives needed for a coherent state machine.
- Poll the whole process table every 10 ms: expensive across a 900-second run
  and still not ownership proof.
- Add a new package, service, privileged tracer, or third-party dependency:
  unnecessary for trusted reviewer CLI descendants and outside RepoInfra.

## Decision 11: Implement Team Audit URL policy as a Service-role protocol witness

**Decision**: Keep the existing `CardPayloadProtocol.validateInvariants()`,
`CardType.validate(_:)`, and `SchemaValidator.validateCardPut` interfaces.
`TeamAuditPayload.swift` owns an internal structural/reference helper but no
public witness body. New Service file
`Packages/AIDashCore/Sources/AIDashCore/Validation/TeamAuditPayloadValidation.swift`
supplies the public witness, runs the structural helper, and applies the
unchanged `URLPolicy` through an internal `TeamAuditPayloadURLValidator`.
Dedicated proof lives in
`Packages/AIDashCore/Tests/AIDashCoreTests/TeamAuditPayloadValidationTests.swift`.

**Rationale**: Models/XPC are the AIDashCore Types role; Validation is Service.
The preserved candidate called `URLPolicy` from Models for full reports,
feedback-lineage PR URLs, and mandatory artifacts, reversing the declared
Types → Service direction. A Service extension implements a Types-owned
protocol instead: Service depends on the decoded Types value, Models never
name Service, and the existing single-decode/error interface remains deep and
stable. The exact T005 implementation surface is eleven files—the original
nine plus the Service implementation and its proof. `SchemaValidator.swift`,
`URLPolicy.swift`, every other layer, parent
`fdace13d20ee0b28759c4853c82445fd4d913dcc`, and candidate
`12577b03c866c73c53fa23d236d2005a68790358` stay unchanged.

**Alternatives rejected**:

- Keep `URLPolicy` calls in `TeamAuditPayload.swift`: violates the canonical
  intra-layer role direction.
- Copy `https`/host checks into Models: creates a second policy source and
  violates constitution §C centralization.
- Add a second decode in `SchemaValidator`: widens orchestration and changes
  `CardType.validate` behavior when the existing protocol seam can carry the
  implementation without upward dependency.
- Modify `URLPolicy` or `SchemaValidator`: no policy/interface defect was
  identified; expanding their scope adds risk without enabling the seam.

## Decision 12: Turn every Round 2 correctness gap into stable acceptance

**Decision**: FR-020 through FR-025 and the T005 matrix lock the six remaining
correctness/test-proof findings: enclosing-axis verdict decode; unique and
catalog-resolved finding references; canonical feedback-lineage hash plus the
repository's 40-hex Git SHA-1 merge OID;
role-round and supporting-evidence reconciliation; unique, priority-aware,
exact artifact/full-report/externalization bindings; and exact production-path
proofs for all sections, Core structured error propagation, AIDashUI rendered
fallback, optional unsafe strings, and byte limits.

**Rationale**: The previous broad matrix language permitted spot checks and
left cross-part reference resolution implicit. A common typed reference
catalog makes each independently decoded card part self-validating without
embedding raw evidence. Typed artifact catalog entries make an overview full
report independently resolvable by kind/ID/hash/URL/sidecar. Typed optional-only externalization and
priority-resolved finding chains preserve P2/info flexibility while making
P0/P1 non-externalizability unrepresentable. The proof split follows ownership:
T005 proves Core failures and T008 proves `CardRouter` fallback. Exact equality
and exact byte fixtures distinguish normative proof from approximate coverage.

**Alternatives rejected**:

- Leave the six items as reviewer prose: later implementation would have no
  stable acceptance IDs or schedulable test mapping.
- Make every finding chain mandatory: incorrectly removes optional P2/info
  behavior.
- Treat a self-declared full-report artifact ID as sufficient: permits hash,
  URL, or sidecar substitution and breaks immutable provenance.
- Accept whitespace-only or merely over-limit fixtures: does not prove that an
  otherwise valid mandatory 262,145-byte payload fails at the wire boundary.

## Resolved source ambiguities

- “Three independent axes” means Workflow Conformance, Workflow Fitness, and
  Outcome Integrity. Task Effectiveness is preserved as a separate fourth
  axis; none is inferred from another.
- The upstream schema leaves event `kind` free-form. AIDash locks only its two
  outbound Owner decision action strings; it preserves other event kinds as
  display text and never assigns transition semantics to them.
- The upstream schema does not define lifecycle transition legality. AIDash
  records receipts and leaves canonical lifecycle state to a later immutable
  snapshot.
- A baseline with fewer than 20 eligible cases is accepted only with an
  explicit limitation. No padding or re-baselining behavior is invented.
