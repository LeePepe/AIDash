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

- **Depth**: high; one call yields existing Swift facts plus complete Python
  predicate context.
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

Select a hybrid of A and B, plus a fail-closed protected-instruction preflight:

1. Preserve the existing external shell/CLI evidence seam.
2. Move all language selection behind `review_context.py`.
3. Keep Swift and Python analyzers as private adapters.
4. Emit versioned typed Python predicate facts with bounded dependency closure.
5. Detect edits to `review_evidence_rules()`,
   `review_security_notice()`, and the live Codex `PROMPT` assignment before
   model invocation.
6. Leave all reviewer instructions and model invocation byte-unchanged.

This gives the current repair structural evidence and prevents another
self-authorizing wording candidate. Design C remains a separately planned
option if the owner later authorizes a general trusted-policy publication
mechanism.

## Error and completeness decision

- Operational failures—invalid request/ref, required blob read failure,
  selected Python syntax error, adapter exception, invalid typed output, or
  serialization failure—return non-zero before the model.
- Protected instruction changes, missing/ambiguous protected regions, or
  competing definitions return `protected_instruction_change` non-zero.
- Unsupported dynamic/cross-file/cyclic semantics return explicit
  `unresolved` facts. They do not become guessed `complete` conclusions.
- Legitimate deletions and cap omissions are explicit.
- Caps omit whole facts and append deterministic notices; no JSON record is
  silently byte-sliced.

## Verification decision

The public module interface is the test surface:

- PR #199 fixture: partial hunk seed resolves the full out-of-hunk predicate,
  allowed literals, and helper fallback.
- Rejecting mutation: removal of `| {"production"}` changes the structural
  result.
- Safe-subset coverage: union, default/fallback, normalization, negation,
  helper closure, unresolved/cycle behavior.
- Trust coverage: PR-authored imperative text remains serialized data below
  the fence.
- PR #205 fixture: a protected instruction change returns non-zero before a
  model stub can run.
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
