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

## Decision 9: Recover through four non-overlapping PR contracts

**Decision**: Recover from exact synchronized-main implementation base
`8716846ac42b48bfd89b9a09d5dd05fc4819025d` through the existing dedicated RepoInfra
watchdog PR, a planning/constitution PR, an AIDashUI future-CardType
compatibility PR, and a fresh AIDashCore-only T005 PR. T020 must publish a
genuinely new three-dot implementation surface: its head differs from the base
and rejected `b4aa5e51bdf381d71a6ab77fa2342349a6a5dedb`, and its only permitted
paths are `scripts/ci/review-common.sh`,
`scripts/ci/review_process_supervisor.py`, and
`scripts/ci/tests/test_review_shell.py`. The constitution PR uses the required
`constitution: <change>` title and carries the in-flight migration note in its
PR description. T005 retains its original nine-file allowlist and consumes
`contracts/t005-acceptance-matrix.md`.

**Rationale**: Exact implementation review of `b4aa5e51...` found a destructive
P0: its `PPID=1` plus executable-name heuristic could import and TERM/KILL
unrelated system shells, Python/Node processes, or sleeps. Removing that
heuristic exposed the unresolved startup race: sampled Bash/`ps` discovery
cannot deterministically capture a fast child that leaves the root PGID and is
reparented before the first snapshot. `scripts/CONTEXT.md` already owns every
`scripts/**` path and gates Python with pytest/ruff, so one stdlib-only helper
is the smallest explicit scope correction that provides a testable platform
adapter and state-machine seam without adding a layer, dependency, workflow,
ruleset, or timeout change. The invalidated branch also
proved that adding the eleventh CardType in Core alone makes three existing
AIDashUI switches non-exhaustive under repository-wide required CI. A small
merge-first AIDashUI fallback is the expand step; T005 is the Core contract
step; the explicit renderer/token work remains T008. This keeps every PR
one-layer, reviewable, and independently buildable without weakening the
CardType contract.

**Alternatives rejected**:

- Re-review rejected head `b4aa5e51...`: it contains the destructive P0 and is
  explicitly frozen as evidence.
- Keep the original two-file allowlist by embedding a Python supervisor in a
  quoted shell string: this destroys locality, avoids normal Python lint/import
  review, and recreates the gate's historical quoting risk.
- Use process group or sampled ancestry alone: neither retains a fast
  `setsid` descendant after reparenting.
- Import recent PPID-1/name-matching orphans: ancestry is unproven and the
  signal can destroy unrelated work.
- Put AIDashUI changes into T005: violates its AIDashCore allowlist and the
  one-layer PR rule.
- Add `teamAudit` UI cases before the Core enum exists: does not compile.
- Ignore repository-wide builds until T008: the protected-branch build gate is
  required for every PR, so T005 would be unmergeable.
- Transplant the failed watchdog patch: its lingering-descendant regression
  still failed and requires a separately authorized RepoInfra diagnosis.

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
