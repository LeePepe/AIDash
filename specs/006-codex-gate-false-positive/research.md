# Research: Trusted Exact-HEAD Decision Evidence

## Owner authority and incident disposition

- Owner decision option B, effective 2026-08-31, stops the wording-only repair
  after three candidates.
- PR #205 at `f16e5d503304b7951f995286cdbb0727b6d2472e` remains Draft with
  auto-merge disabled. No merge or bypass is authorized.
- Exact-SHA Multica review passed in comment
  `e5a0c8f4-b638-4da7-9861-33942702e332`, but the same-SHA required
  `codex-review-target` still failed because the proposed reviewer
  instructions were PR-controlled diff content.
- The old shipping handoff `220b74e2-dce6-4b32-85ce-777c04128d57` and
  planning revision `82401679541f49f5ee4aa4806759c0e565f78321` are
  superseded.

## Repository control-path findings

- `.github/workflows/codex-review-target.yml` uses
  `pull_request_target`, checks out `base.sha`, and invokes the base copy of
  `scripts/ci/codex-review.sh`. The execution source is trusted.
- `scripts/ci/codex-review.sh` fetches/validates base and head objects,
  computes the full diff, invokes `build_scope_evidence()`, then puts the diff
  and evidence below the untrusted-data fence. Evidence-builder failure exits
  non-zero before the model.
- `scripts/ci/review-common.sh` currently filters changed paths to
  `*.swift` before calling `scripts/ci/review_context.py`.
- `scripts/ci/review_context.py` reads exact-HEAD blobs with
  `git show HEAD:path` and never checks out or executes PR code, but it emits
  only Swift modifier receiver/excerpt evidence.
- `scripts/ci/tests/test_review_context.py` proves Swift diff coordinates,
  receiver ownership, caps, and untrusted framing.
- `scripts/ci/tests/test_review_shell.py` proves shared prompt transport,
  security-token handling, large changed-file-list transport, timeout, schema,
  and failure behavior.

## Predicate evidence from PR #199

- PR #199 exact HEAD `6cefdd4ac8b00dc8b896014cca3ba38ec6dcff17` changed
  `aidata/tests/test_query_tiers.py` near imports and module bindings.
- Unified-diff context exposed `VALID_TIERS = {"explore"}`.
- The unchanged exact-HEAD deciding predicate at line 81 was
  `_tier_of(name) not in VALID_TIERS | {"production"}`.
- The same file's `_tier_of` helper contains the literal `production` fallback.
- The required reviewer twice treated the isolated binding as proof that
  `production` was invalid even though the complete expression admits it.

The hunk is therefore a seed for evidence discovery, not sufficient evidence.
A trusted exact-HEAD AST traversal can deterministically connect the binding
to its out-of-hunk use and local helper without executing the code.

## PR #205 evidence

Relative to exact base `8716846ac42b48bfd89b9a09d5dd05fc4819025d`, PR #205
changes only:

- `docs/ci-gates.md`;
- `scripts/ci/review-common.sh`, specifically reviewer-rule wording; and
- `scripts/ci/tests/test_review_shell.py`, specifically assertions that the
  proposed words are emitted.

It does not change `review_context.py` or generate structural Python evidence.
During its own `pull_request_target` review the base implementation executes;
the proposed instructions appear only as untrusted diff text. A string-
presence regression cannot prove instruction provenance or activate a new
trusted policy. This is a seam failure, not a fourth wording problem.

## Exact-base reconciliation — 2026-08-31

Two Fullstack runs stopped on a clean delivery branch because the five planned
paths already existed and the pre-existing tests passed. Read-only
reconciliation proved that this interpreted file presence as behavior:

- delivery workspace HEAD and `delivery_base_sha` are both
  `8716846ac42b48bfd89b9a09d5dd05fc4819025d`;
- base-to-HEAD diff is empty, the delivery branch is not pushed, and no PR
  exists;
- `review-common.sh:266-285` forwards only `*.swift` and returns success
  without invoking the analyzer when no Swift file changed;
- `review_context.py:100-142` maps only added lines,
  `:145-236` derives only Swift receiver evidence, and `:322-336` skips
  every non-Swift path;
- `review_context.py:283-290` byte-slices the rendered body at the total cap,
  rather than omitting whole typed facts;
- no base source/test outside `aidata/**` contains
  `protected_enforcement_change`, `allowed_domain`,
  `subject_helper_semantics`, `ClaimCompletion`, or `EvidenceBundle`.

The deterministic base probe exercised the real analyzer with PR #199 and
PR #205 inputs:

```text
pr199: rc=0 stdout_bytes=0 stderr=''
pr205: rc=0 stdout_bytes=0 stderr=''
FAILURES:
- PR199 claim-scoped allowed-domain evidence missing
- PR205 protected-enforcement preflight missing
```

This is a tight red-capable acceptance signal. The empty branch is the correct
pre-implementation state; it is not a hard red line and must not be converted
into a synthetic no-op patch.

### Functional-requirement matrix against exact base

| Requirement | Base status | Concrete proof / remaining delta |
|---|---|---|
| FR-001 trusted-base execution / no PR-code execution | Satisfied baseline invariant | Workflow lines 7-39 use `pull_request_target`, checkout base SHA, and run the base script; analyzer lines 5-7 read HEAD through `git show` |
| FR-002 one deep evidence module behind existing seam | Partial | One shell/CLI seam exists, but its implementation is Swift-only and not a typed multi-evidence module |
| FR-003 forward all changed paths; select language internally | Missing | `review-common.sh:266-285` filters `*.swift` and returns before the analyzer for all other PRs |
| FR-004 preserve Swift + add private Python AST adapter | Partial / missing delta | Swift receiver adapter exists; no `ast` import or Python adapter exists |
| FR-005 hunk-context seed and out-of-hunk Python use discovery | Missing | Only `added_line_numbers()` exists; context lines and Python uses are never analyzed |
| FR-006 claim-scoped predicate/allowed-domain/helper evidence | Missing | No typed Python evidence or claim vocabulary exists |
| FR-007 restricted static evaluator without PR execution | Partial / missing delta | No-execution invariant exists; restricted evaluator does not |
| FR-008 per-claim completion | Missing | No `ClaimCompletion` or claim status exists |
| FR-009 versioned canonical bundle and whole-fact caps | Missing / contradicted | No bundle schema/digest/id exists; total cap byte-slices text at `review_context.py:283-290` |
| FR-010 trusted labels and untrusted fenced source | Satisfied baseline invariant | Analyzer lines 27-28 label source untrusted; Codex lines 165-174 place diff/evidence inside the fence |
| FR-011 protect five enforcement-file blob identities | Missing | No protected path manifest, blob comparison, or `protected_enforcement_change` result exists |
| FR-012 one-time bootstrap and consumed authority | Pending implementation/delivery | Process contract exists only in planning; no bootstrap candidate exists |
| FR-013 preserve prompt/caller/workflow/ruleset/timeout behavior | Satisfied starting invariant | Exact base supplies the byte source; T001 must leave the three protected verification targets and excluded regions unchanged |
| FR-014 new analyzer/protected/schema failure taxonomy | Partial | Existing diff-read/top-level failures are non-zero; new adapter/schema/protected-file paths do not exist |
| FR-015 new hermetic structural regressions and red→green proof | Missing | Exact-base test search finds none of the PR #199/claim/protected symbols; existing green tests exercise old behavior |
| FR-016 one RepoInfra layer and no product/data mutation | Satisfied scope precondition only | Empty diff is in scope but delivers no behavior; non-empty delta must remain in reviewed five files |
| FR-017 preserve PR #205 Draft/no-auto-merge evidence | Satisfied external disposition | Owner/Team Lead/PR Manager comments hold PR #205; no branch mutation occurred |
| FR-018 refresh PR #199 only after repair on main | Blocked downstream | Structural repair is not on `main`; refresh is correctly unavailable |
| FR-019 B000 same-base green check | Satisfied scheduling precondition | Actions run `33350742892`, job `99363478423`; proves baseline health, not T001 completion |
| FR-020 named timeout/task-freshness stop rules | Satisfied scope guard | Base behavior remains unchanged; any named recurrence still returns to Team Lead |

### Task-local acceptance summary

Of the eight acceptance bullets persisted on MY-1530, only three are already
baseline invariants: trusted blob-only reading/no execution, existing
Swift/fail-closed coverage, and current untrusted-fence placement. The five
core delivery outcomes are missing: all-path/internal selection, claim-scoped
PR #199 evidence, rejecting mutation behavior, five-file self-protection, and
the no-exemption protected enforcement result.

### Root cause

The implementation delta is real but was misexpressed operationally:

1. T001 said “deepen” existing files without naming mandatory new production
   symbols or exact source transformations.
2. B000 and the exact verification section emphasized green existing tests,
   so a passing baseline looked like delivery evidence.
3. No mandatory test-first selectors had to fail against the base behavior.
4. No sentence said an empty freshly prepared branch is expected and must
   receive a non-empty behavioral delta.

The repair is to retain one RepoInfra task but add exact base-gap proof,
normative production/test deltas, and a mandatory red→green sequence. Splitting
tests into a separate issue would create an unmergeable red commit and is not a
valid vertical slice.

## Dependency classification

| Dependency | Category | Design |
|---|---|---|
| Unified-diff parsing, AST traversal, restricted evaluation, hashing, ordering | In-process | Keep inside the deep evidence module; no exposed adapter |
| Exact-HEAD git blob reads | Local-substitutable | Production `git show` adapter and fixture-map adapter for interface tests |
| Diff-file input | Local-substitutable | CLI filesystem adapter; tests pass fixture text |
| Codex CLI/model | True external, unchanged | Remains outside T001; existing caller/failure handling is preserved |

## Alternative interface designs

### A. Minimal deep evidence module

Keep the existing shell/CLI seam and add Python decision facts behind
`review_context.py`.

- **Depth**: high; one call yields existing Swift facts plus claim-scoped
  Python predicate context.
- **Locality**: evidence discovery, blob reads, caps, and rendering remain in
  one module.
- **Weakness**: without an added preflight, a future PR can still propose
  changes to instruction-producing source and send those proposed words to the
  model as diff data.

### B. Extensible typed evidence adapters

Define a versioned evidence bundle and private adapter registry. Existing Swift
and new Python logic become internal adapters selected by the base-owned
module.

- **Depth**: highest for repeated evidence classes; callers learn no language
  details.
- **Locality**: new evidence classes change one internal registry plus tests.
- **Weakness**: a public plugin interface or PR-selectable adapter would enlarge
  the attack surface and make the module shallow. The registry must stay
  static and private.

### C. Separate trusted Codex instruction loader

Create a new runner that loads base-owned instructions through Codex project
instruction discovery and transports all PR data separately through stdin.

- **Depth**: strong end-to-end gate module; one runner hides provenance,
  evidence transport, model invocation, schema validation, and rendering.
- **Locality**: trust loading becomes explicit.
- **Cost/risk**: changes `codex-review.sh`, Codex invocation semantics,
  instruction-discovery assumptions, result orchestration, and the external
  CLI adapter. It is Codex-specific and substantially larger than the proven
  predicate gap.

## Decision

Select a hybrid of A and B, plus a fail-closed self-protecting enforcement
preflight:

1. Preserve the existing external shell/CLI evidence seam.
2. Move all language selection behind `review_context.py`.
3. Keep Swift and Python analyzers as private adapters.
4. Emit versioned typed Python predicate facts with completion scoped to each
   claim rather than the whole fact.
5. Protect the entire `review_context.py`, `review-common.sh`,
   `codex-review.sh`, `codex-review-target.yml`, and
   `main-protection.json` blobs before model invocation.
6. Leave all reviewer instructions and model invocation byte-unchanged.

This gives the current repair structural evidence and prevents another
self-authorizing wording candidate or a later unprotected edit to the guard
itself. T001 is the one owner-reviewed bootstrap that publishes the protected
chain; its authority is consumed on merge. Design C remains a separately
planned option if the owner later authorizes a general trusted-policy
publication mechanism.

## Exact-revision review findings and resolution

The first structural planning review at
`9b81224c8fd2464d0b435faf60fbe446ea1c2fe2` found two P1 gaps:

1. protecting only prompt-rule functions and the `PROMPT` assignment left
   the detector and its enforcement path model-dependent; and
2. one fact-wide `complete` flag overclaimed the dynamic
   `TIER_DIRECTIVE.search` / `match.group` helper semantics.

The repaired design protects the entire enforcement chain after a one-time
owner-reviewed T001 bootstrap. It also replaces fact-wide resolution with
independent claim completion: the predicate AST and safe RHS allowed domain
can complete, while subject/helper semantics remain unresolved and the
literal fallback is only a syntactic observation.

## Error and completeness decision

- Operational failures—invalid request/ref, required blob read failure,
  selected Python syntax error, adapter exception, invalid typed output, or
  serialization failure—return non-zero before the model.
- Any changed, missing, replaced, or ambiguous protected enforcement blob
  returns `protected_enforcement_change` non-zero.
- Unsupported dynamic/cross-file/cyclic semantics make only the affected
  claim `unresolved`. They do not contaminate an independent safe claim or
  become guessed `complete` conclusions.
- Legitimate deletions and cap omissions are explicit.
- Caps omit whole facts and append deterministic notices; no JSON record is
  silently byte-sliced.

## Verification decision

The public module interface is the test surface:

- PR #199 fixture: partial hunk seed yields complete predicate-structure and
  RHS allowed-domain claims, unresolved regex/group helper semantics, and an
  observation-only literal fallback.
- Rejecting mutation: removal of `| {"production"}` changes the structural
  result.
- Safe-subset coverage: union, normalization, negation, per-claim closure,
  observation-only fallback, and unresolved/cycle behavior.
- Trust coverage: PR-authored imperative text remains serialized data below
  the fence.
- Enforcement fixtures: PR #205 plus one independent blob mutation for every
  other protected file each return non-zero before a model stub can run.
- Stability: exact refs/input/caps produce canonical ordering and explicit
  whole-record omissions.
- Compatibility: PR #171 Swift receiver behavior remains covered.
- Shell integration: all changed paths reach the module; non-zero evidence
  status remains fail closed; prompt helpers and live caller are unchanged.

Implementation verification remains hook-driven:

`scripts/context/run RepoInfra --mode local`

CI runs the corresponding RepoInfra CI gate plus ruff. No App, Swift-package,
or Aidata suite is manually added.

## Pre-dispatch exact-base evidence

The current planning base
`8716846ac42b48bfd89b9a09d5dd05fc4819025d` has a successful
`review-gate (pytest)` result in Actions run `33350742892`, job
`99363478423`. Team Lead must refresh the proof if T001's implementation base
changes.

The two named `run_with_timeout` failures and Homebrew-Bash
`check-tasks-fresh` hang remain explicit stop-and-return red lines outside
T001.
