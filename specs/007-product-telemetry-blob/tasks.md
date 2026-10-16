# Tasks: Manual Product Blob Batch Landing

## Execution contract

This exact planning revision is the RepoInfra authority prerequisite. It must
receive independent Standards + Spec PASS and merge before either implementation
task is dispatched. A planning PASS is not implementation approval.

The later implementation is one descendant chain with one independently
verifiable commit per changed product layer:

```text
reviewed + merged RepoInfra authority
  -> T101 AidataFoundation commit
  -> T102 AidataL1L2 commit
  -> exact final-head implementation review/publication
  -> separately authorized T7 evidence
```

Routing/context files listed with a task are only the exact parent/leaf metadata
needed for that layer's new path or changed contract. They do not transfer
product ownership. Hooks and CI own tests; implementers inspect their receipts
and do not invoke suites directly.

## Phase 1: Manual CLI/config foundation

- [ ] **T101 [US2] Add the disabled-by-default manual `product-blob` CLI boundary.**

| Metadata | T101 |
|---|---|
| Owning layer / context | **AidataFoundation** — `CONTEXT.md` → `aidata/CONTEXT.md` → `aidata/CONTEXT.foundation.md`; `aidata/tech-context.md` |
| Files in scope | `aidata/config.py`; `aidata/config_local.example.py`; `aidata/cli.py`; `aidata/tech-context.md`; `aidata/CONTEXT.foundation.md`; only the matching Foundation routing/test-path hunk in `aidata/CONTEXT.md`; `aidata/tests/test_config_m3.py`; new `aidata/tests/test_product_blob_cli.py` |
| Files NOT to touch | `aidata/adapters/**` and `aidata/tests/test_product_blob.py` (T102); `aidata/rawio.py`; `aidata/state.py`; `aidata/requirements.lock`; merge/schema/L4/L5/scripts; `.github/**`; Swift/App/Configs/fastlane; existing test deletion/skip/weakening |
| Interface / contract | `contracts/manual-batch-collector.md` MB-004 and MB-013–MB-015; two empty tracked selectors; one no-argument command separate from generic `collect`; safe result validation; Constitution success/error envelopes |
| Existing behavior preserved | Generic `collect`, `SOURCES`, `MERGE_SOURCES`, `SCHEDULED_SOURCES`, runner/cron, all existing commands/tests, and absent-local-config no-op behavior remain byte/behavior compatible outside the exact additions |
| Removed behavior | None from live main. Do not add the superseded dependency, registry, scheduler, page/object state, custom caps, or L2-L5 behavior in MB-020 |
| Functional acceptance | Both empty selectors are a successful `empty` no-op with no adapter import; partial/unsafe selector pairs fail closed. Completed/empty safe adapter results produce exactly MB-014; extra args, import/load failure, adapter exception, and malformed/sentinel-bearing return produce exactly MB-015 with a fresh request ID but no message interpolation. Output contains no endpoint, identity, Blob name, payload, or absolute path |
| Verification | One success-path and validation/failure CLI test exercise the real CLI seam with isolated return/exception fakes; config tests prove empty defaults and malformed-pair rejection. A normal commit/push must produce **AidataFoundation** hook receipts; required aidata CI owns pytest/Ruff/degrade-not-crash |
| Constitution refs (1.14.0) | §A Scope Discipline; §B CLI Surface; §D Error Handling; §G Test Coverage; §Testing → Who runs tests; §No Identity in Version Control |
| Dependencies / slice | Exact reviewed+merged RepoInfra authority; opens US2 without an adapter, registry, activation, or live operation |

**Commit boundary**: T101 is one normal AidataFoundation commit. If retained
production or an existing test exposes a real defect, stop with exact evidence
and return to Team Lead; do not widen this task.

## Phase 2: Opaque L1 batch adapter

- [ ] **T102 [US2] Implement one atomic manual Azure batch landing.**

| Metadata | T102 |
|---|---|
| Owning layer / context | **AidataL1L2** — `CONTEXT.md` → `aidata/CONTEXT.md` → `aidata/adapters/CONTEXT.md`; `aidata/tech-context.md` |
| Files in scope | new `aidata/adapters/product_blob.py`; `aidata/adapters/CONTEXT.md`; only the matching L1/L2 routing/test-path hunk in `aidata/CONTEXT.md`; new `aidata/tests/test_product_blob.py` |
| Files NOT to touch | T101 Foundation paths; `aidata/rawio.py`; `aidata/state.py`; merge/schema/L4/L5/scripts; any registry/config activation; `.github/**`; Swift/App/Configs/fastlane; existing test deletion/skip/weakening |
| Interface / contract | All MB-001–MB-020. The adapter hides Azure preflight/argv/privacy, tempfile staging, opaque filesystem validation, fsync, and one atomic directory publish behind the T101 command |
| Existing behavior preserved | All prior completions are immutable; generic sources/pipeline, runner/cron, producer/consent, and existing tests remain unchanged |
| Removed behavior | None from live main. The task MUST NOT introduce the superseded per-Blob raw ID/registry, parser, custom cap, page/checkpoint, resume/dedupe, dependency, generic activation, Ops, scheduler, or L2-L5 plan |
| Functional acceptance | Exact version/cloud/batch argv and child environment; one private same-filesystem stage; startup terminal rejection under the trusted-local model; no private output retention; exit-0/nonempty-only publication; byte-identical file tree; fsync files/tree, one absent-target directory rename, then parent fsync; zero completion for empty/nonzero/pre-commit interruption; abandoned stages ignored; earlier completions untouched; later success creates a distinct batch; CLI result remains MB-014/MB-015 |
| Verification | One executable scenario-driven fake `az` is invoked only through the real CLI/adapter lookup seam. Its ledger records only commands actually invoked; assertions use exact argv/environment and real tempfile/completion outcomes, never prewritten traces or fabricated finals. A normal commit/push must produce **AidataL1L2** hook receipts; required aidata CI owns pytest/Ruff |
| Constitution refs (1.14.0) | §A Scope Discipline; §D Error Handling; §G Test Coverage; §Testing → Who runs tests; §No Identity in Version Control |
| Dependencies / slice | T101 hard dependency; closes the hermetic US2 implementation at the descendant final head |

**Commit boundary**: T102 is one normal AidataL1L2 commit after T101. Review is
bound to the exact final descendant head and includes both commits. A need to
modify a T101 path or another layer returns to Team Lead; it is not folded into
this commit.

## External milestone: T7 manual evidence

**T7 (no T-number; no repository implementation owner)** begins only after the
exact implementation head is merged and separate live authorization exists.
The authorized operator uses MB-016, records the actual TestFlight build and
Blob name only in the private workflow evidence file, and obtains the exact
batch/Blob-scoped filtered/count result in
`contracts/e2e-evidence.md`. Generic `collect` is distinct evidence. T7
authorizes no source edit, credential read, role/policy change, scheduler, or
cross-run idempotency claim.

## Acceptance coverage

| Requirement / scenario | Owning closure |
|---|---|
| FR-001–FR-004 / retained producer and consent | Existing merged authority; no task |
| FR-005 / US2 disabled, empty, failure, success, atomic L1 batch | T101 + T102 |
| FR-006 / US3 private TestFlight → Blob → completion → scoped query | Post-merge T7 |
| FR-007 / least privilege and public privacy | T101 + T102 + T7 |
| SC-001 retained producer evidence | Existing merged authority |
| SC-002 exact manual collector observables | T101 + T102 |
| SC-003 absence of superseded machinery | Final-head diff/review |
| SC-004 live batch/Blob association | T7 |
| SC-005 no private tracked/public material | Every task privacy scan + review |
| SC-006 routing/hooks/CI/reviews | Each exact layer commit and final head |

## Definition of done

- T101 and T102 stay within their exact layer/path scopes and form the declared
  acyclic dependency chain.
- New tests are registered in matching parent and leaf routing in their owning
  commits; context audit has no finding.
- Normal commit/push receipts select the intended leaf; no human/agent directly
  invokes a suite and no host-based app test runs locally.
- All MB IDs and FR/SC outcomes have the owning proof above; no competing
  reader mechanics remain in another canonical artifact.
- Existing live-main tests remain present and unweakened. Any future final diff
  that deletes/skips/weakens one, or changes Constitution/gates, stops for
  explicit Owner approval on the published final PR head.
- Exact local, pushed branch, PR, and review heads match before publication.
