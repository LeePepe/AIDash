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
| Interface / contract | `contracts/manual-batch-collector.md` MB-004 and MB-013–MB-015; two empty tracked selectors; one no-argument command separate from generic `collect`; safe import/return validation; Constitution success/error envelopes |
| Existing behavior preserved | Generic `collect`, `SOURCES`, `MERGE_SOURCES`, `SCHEDULED_SOURCES`, runner/cron, all existing commands/tests, and absent-local-config no-op behavior remain byte/behavior compatible outside the exact additions |
| Removed behavior | None from live main. Do not add the superseded dependency, registry, scheduler, page/object state, custom caps, or L2-L5 behavior in MB-020 |
| Context acceptance | Foundation context records `PRODUCT_BLOB_CONTAINER_URL` plus `PRODUCT_BLOB_PREFIX` as the only noncredential selectors for `product_blob`; tracked defaults stay empty, one configured prefix is the Owner-allow-listed VoxPocket value, real values stay only in ignored `config_local.py`, and no credential/auth-mode field is tracked. Foundation-owned `aidata/tech-context.md` records `product_blob` as the sole manual opaque immutable-L1/no-normalize exception; all other sources retain their existing selectors/config defaults and paired collect→normalize/append-only-redaction behavior. T101 adds only `test_product_blob_cli.py` to Foundation test routing and does not define adapter, Azure-child, fake-`az`, staging, or filesystem assertions |
| Functional acceptance | Both empty selectors are a successful `empty` no-op with no adapter import; partial/unsafe selector pairs fail closed. Completed/empty safe adapter results produce exactly MB-014; extra args, import/load failure, adapter exception, and malformed/sentinel-bearing return produce exactly MB-015 with a fresh request ID but no message interpolation. Output contains no endpoint, identity, Blob name, payload, or absolute path |
| Verification | Config tests prove empty defaults and malformed-pair rejection; CLI tests cover argument, adapter import/load, return-value, exception, and exact envelope seams with isolated import/return fakes only. A normal commit/push must produce **AidataFoundation** hook receipts; required aidata CI owns pytest/Ruff/degrade-not-crash |
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
| Interface / contract | Adapter-owned MB-001–MB-003, MB-005–MB-012, MB-016, and MB-018–MB-020. T102 consumes T101's MB-004 and MB-013–MB-015 command/config boundary without editing it; MB-017 remains the external T7 milestone. The adapter hides Azure preflight/argv/privacy, tempfile staging, opaque filesystem validation, fsync, and one atomic directory publish behind the T101 command |
| Existing behavior preserved | All prior completions are immutable; generic sources/pipeline, runner/cron, producer/consent, and existing tests remain unchanged |
| Removed behavior | None from live main. The task MUST NOT introduce the superseded per-Blob raw ID/registry, parser, custom cap, page/checkpoint, resume/dedupe, dependency, generic activation, Ops, scheduler, or L2-L5 plan |
| Context acceptance | L1/L2 context records `product_blob` as the sole opaque immutable-L1/no-normalize exception: collection remains read-only and publishes one completion directory. Paired collect+normalize and redacted append-only-raw defaults remain unchanged for every other adapter; dependency direction and unconfigured no-op behavior stay intact. T102 adds only `test_product_blob.py` to adapter test routing |
| Functional acceptance | Exact version/cloud/batch argv and child environment; one current-UID-owned private same-filesystem stage/completion; startup terminal symlink/non-directory rejection; output symlink/special/lexical-or-resolved-path-escape rejection; no private output retention; exit-0/nonempty-only publication; byte-identical file tree; fsync files/tree, one absent-target directory rename, then parent fsync; zero completion for empty/nonzero/pre-commit interruption; real delegated rename followed by response loss/post-commit interruption retains the whole immutable completion; abandoned stages ignored; earlier completions untouched; later success creates a distinct batch; CLI result remains MB-014/MB-015 |
| Verification | One executable scenario-driven fake `az` is invoked only through the real CLI/adapter lookup seam. Its ledger records only commands actually invoked; assertions use exact argv/environment, current UID/private modes, unsafe-entry/path rejection, and real tempfile/completion outcomes. A post-commit seam delegates to the real rename before inducing response loss/interruption; fixtures never prewrite traces or fabricate finals. A normal commit/push must produce **AidataL1L2** hook receipts; required aidata CI owns pytest/Ruff |
| Constitution refs (1.14.0) | §A Scope Discipline; §D Error Handling; §G Test Coverage; §Testing → Who runs tests; §No Identity in Version Control |
| Dependencies / slice | T101 hard dependency; closes the hermetic US2 implementation at the descendant final head |

**Commit boundary**: T102 is one normal AidataL1L2 commit after T101. Review is
bound to the exact final descendant head and includes both commits. A need to
modify a T101 path or another layer returns to Team Lead; it is not folded into
this commit.

## External milestone: T7 manual evidence

**T7 (no T-number; no repository implementation owner)** is an external
milestone with this executable contract:

| Field | T7 |
|---|---|
| Gate | Final VoxPocket producer and collector heads are merged; the Owner-authorized workflow 05 lead/operator has re-read and recorded the exact final merged VoxPocket producer contract/head and confirmed the existing TestFlight/Azure/collection/query authorization still applies |
| Executor | Owner-authorized workflow 05 lead/operator through a Codex subagent in the workflow lead's local session; the Multica Team Lead owns neither that subagent nor personal TestFlight/Azure authority, and this is not a product implementation task |
| Inputs | One selected completion batch ID, exact relative Blob path, actual TestFlight build, and authorized UTC window, all retained only in Owner-local workflow evidence |
| Procedure | Invoke MB-016 for the manual batch as authorized, then execute MB-017's one-pass gzip NDJSON validation against the exact final merged VoxPocket producer contract, build/UTC/batch/relative-Blob filters, and unique source-line-locator counting |
| Acceptance | All product-event counts and property validations required by the exact final merged VoxPocket producer contract; records that contract classifies outside product-event counting are excluded from those counts; total validated lines; duplicate locator keys exactly `0`; selected build/Blob/completion-relative L1 association; UTC window; query summary/output. Identical content lines remain separately counted |
| Privacy/boundary | No sensitive payload or real value is prefilled or printed publicly. No source edit, credential read, role/policy change, product query/state, scheduler, personal TestFlight/Azure authority, unauthorized manual dispatch, live authority from this plan, or cross-batch/run idempotency claim. Generic `collect` is distinct evidence |

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
