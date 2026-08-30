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

## Decision 9: Calibrate the `teamAudit` light classification token

**Decision**: Keep the shared 32×32 badge recipe unchanged: the glyph uses the
full classification tint and the container uses the same tint source-over
composited at `0.15` alpha. Calibrate only `Classification.teamAudit`'s light
token from `#FF2D55` to `#E6294D`; keep dark `#FF375F`. The acceptance measure
is `ratio(tint, composite(tint, ground, 0.15)) >= 3.0` across both DesignKit
neutral palettes, both schemes, and the `card`, `inner`, and `bg` grounds.

**Rationale**: The original light system pink reaches only 2.58:1 in the worst
rendered badge case. `#E6294D` preserves its hue, remains visually distinct
from the fixed danger semantic, and clears the worst approved ground at 3.06:1;
the unchanged dark value clears at least 3.35:1. Keeping the correction inside
the DesignKit token source preserves the existing small classification
interface and localizes implementation and verification to one resolver leaf.

**Alternatives rejected**:

- Use the least-dark passing stop `#E8294D`: it clears the worst ground at only
  3.02:1; the visually negligible two-channel-unit difference does not justify
  the narrower calibration margin.
- Reduce the shared badge-fill opacity: retaining `#FF2D55` requires about
  3.6% or less on the worst ground, materially weakening every badge and
  changing the constitution-owned AIDashUI recipe.
- Add a `teamAudit`-specific badge recipe or separate on-subtle glyph token:
  expands the DesignKit-to-AIDashUI interface and creates a per-type special
  case when one calibrated classification value satisfies the contract.

## Decision 10: Repair the existing remote-branch gate as a separate RepoInfra prerequisite

**Decision**: Add one RepoInfra-only delivery task to stabilize
`run_with_timeout` when a command leader exits zero before the deadline but
leaves descendants to clean. Merge that repair independently to `main`; only
then may Fullstack integrate the exact main revision into the preserved MY-1505
workspace/branch and retry its normal push. T006 remains a three-file DesignKit
task and PR #200 remains Draft.

**Rationale**: PR #200's remote branch already exists. For an existing remote
ref, `scripts/hooks/pre-push` compares the remote SHA directly with the local
SHA, not with the PR merge-base. The remote branch's `scripts/hooks/pre-push`
blob differs from both the preserved local candidate and `main`; therefore
every compliant successor that removes the inherited hook drift necessarily
selects RepoInfra. Commit ancestry cannot remove a tree difference between
those two endpoints. A passing RepoInfra gate is consequently a real delivery
prerequisite, not T006 implementation scope.

**Alternatives rejected**:

- Another in-place topology wrapper: endpoint path selection is invariant to
  ancestry once the remote SHA is nonzero, so RepoInfra remains selected.
- Reintroduce the remote hook blob: makes the PR endpoint out of scope and
  repeats the reviewer P0.
- Delete/recreate the branch, force-push, bypass hooks, or change the hook:
  violates the delivery constraints and/or destroys PR #200's preserved Draft
  history.
- Depend on existing Draft PR #186: its current review and `review-gate`
  checks fail and its broader coverage-context scope is not an accepted repair
  for this blocker.

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
