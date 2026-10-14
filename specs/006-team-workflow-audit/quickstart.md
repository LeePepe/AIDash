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

T020/PR #204, T021/PR #210, and T019/PR #215 are completed history; never
dispatch them again. The T022 recovery planning is a semantic forward-port of
accepted package `1ba0062bb2597efd91c46b8de9080b53b8484da1` onto current-main
base `bdf1435fe7d3d9c4da43ed4297cbc24482447b46`. The former executable T002 is
coordination-only: T022 must pass exact-revision review and be accepted before
Team Lead can advance T023. T023–T026 remain serial.

The separate registered MY-1522 T005 delivery workspace and candidate
`12577b03c866c73c53fa23d236d2005a68790358` remain untouched evidence; this
T022 recovery neither re-reviews nor advances that candidate.

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
- Workflow Conformance, Workflow Fitness, and Outcome Integrity each
  round-trip their own `insufficientEvidence` value using the enclosing axis.
- Replay and overlap records deduplicate by stable identity; hash collision
  never overwrites and emits a separately keyed observation with accepted
  parent snapshot ID/hash.
- All six finding states and all locked verdicts round-trip.
- Feedback lineage preserves problem/delivery/release/observation state, and
  rejects a lineage ID not equal to the canonical U+001F-delimited tuple hash
  or a supplied merge revision that is not a lowercase 40-hex Git SHA-1 OID.
  Repeat metrics
  preserve every role, cycle/cause, five-case tagged role-specific, subject,
  and event value, bound every primary role-round total to attempts, and
  require unique catalog-resolved supporting subjects/events; otherwise they
  reject.
- Artifact IDs and finding-chain references are unique and catalog-resolved;
  P0/P1 chains are mandatory while P2/info chains may remain optional. A full
  report and each externalized optional entity match ID, hash, URL, and sidecar
  exactly; an overview full report matches a typed catalog artifact by kind,
  ID, hash, URL, and sidecar without reading an artifacts card. The
  externalized entity kind cannot represent mandatory content.
- Case timelines embed ordered events/attempts; their stable case/event/
  attempt/role/cycle references resolve exactly and reject missing, duplicate,
  reordered, or foreign identities. Events preserve exact source order,
  matching case back-pointers, UTC timestamps, and non-decreasing chronology;
  equal timestamps retain source order.
- Every artifact event reference resolves; every non-null case binding owns
  the referenced events; each finding-chain event/case membership matches the
  bound finding.
- Arbitrary-size syntactically valid JSON integers return the exact field-valid
  value or structured rejection; no numeric conversion exception escapes.
- Missing/unsafe mandatory artifact URLs reject publication; unsafe optional
  artifact/grill URLs are text; valid HTTPS URLs are actionable.
- Finding subject/responsibility and exact artifact-sidecar ID/content hash
  survive import, warehouse, query, payload, and rendering.
- Collision parent ID/hash/entity/disposition, artifact snapshot/sidecar
  relationships, typed grill links, full-report resolution, and externalized
  optional-entity bindings reject dangling or mismatched references.
- Exact decoded equality covers all eight section variants. Unknown locked
  enum values traverse the Core production structured-error path in T005 and
  render the existing AIDashUI generic fallback in T008; unsafe optional
  strings round-trip without becoming actionable URLs.
- Final otherwise-valid encoded payload fixtures cover exactly 262,144 bytes
  accepted and exactly 262,145 mandatory bytes rejected; whitespace-only or
  merely “greater than limit” fixtures are not proof. The
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
inside the exact eleven-file AIDashCore allowlist. Models contain no
`URLPolicy`/Validation reference; the Service-role extension in
`Validation/TeamAuditPayloadValidation.swift` supplies the existing protocol
witness and is exercised through both `CardType.validate` and
`SchemaValidator.validateCardPut`. Existing `SchemaValidator.swift` and
`URLPolicy.swift` remain unchanged.

The complete T022–T026 interface matrix is
`contracts/t002-acceptance-matrix.md`; T022 directly owns D01–D20 and T025
repeats them through neutral bundles. `contracts/l1l2-normalized-output.md`
is the only T026 → T003 data seam.

## 5. CI evidence

The implementation PR must obtain the repository-required CI checks, including
macOS/iOS App builds, CLI build, Core/package tests, aidata pytest + ruff, and
the repository review target. CI, not a local host-based test, is the source of
truth for assembled App/CLI build compatibility.
