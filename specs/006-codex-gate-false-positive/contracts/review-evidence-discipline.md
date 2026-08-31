# Contract: Trusted Exact-HEAD Decision Evidence

## Purpose

Supply complete decision context structurally from base-owned code, keep every
PR-authored byte as untrusted review data, and stop protected reviewer-policy
changes before model invocation.

This contract supersedes the wording-only prompt contract reviewed at
`82401679541f49f5ee4aa4806759c0e565f78321`.

## Trust contract

1. `pull_request_target` continues to execute only the checked-out trusted
   base.
2. PR-head source is read only as git blobs through
   `git show <HEAD_SHA>:<path>`.
3. PR code is never checked out, imported, evaluated, or executed.
4. Base-owned code supplies schema labels, headings, provenance, resolution
   state, ordering, hashes, and omission notices.
5. PR-authored source/excerpts remain tagged `untrusted_pr` and are rendered
   only below the existing untrusted-data fence.
6. No PR-controlled allowlist, exemption token, expected hash, plugin path, or
   self-attestation may weaken these rules.

## External interface

The live gates retain one shell seam:

```text
build_scope_evidence <head_sha> <full_diff_file> <changed_paths>
```

It invokes one CLI seam:

```text
review_context.py --head-sha <sha> --diff-file <path>
                  --changed-file <path>...
                  --max-file-bytes <n>
                  --max-excerpt-bytes <n>
                  --max-total-bytes <n>
```

The shell forwards every changed path. Adapter selection is private to
`review_context.py`. The interface returns canonical evidence on stdout and
zero, or a diagnostic on stderr and non-zero.

## Protected instruction contract

Before model invocation, the base-owned implementation identifies:

- `review_evidence_rules()` in `scripts/ci/review-common.sh`;
- `review_security_notice()` in `scripts/ci/review-common.sh`; and
- the live Codex `PROMPT` assignment in `scripts/ci/codex-review.sh`.

A changed line intersecting one of these regions, a missing/duplicated region,
or an ambiguous region boundary returns
`protected_instruction_change` non-zero. The model is not invoked.

PR #205 at `f16e5d503304b7951f995286cdbb0727b6d2472e` is the mandatory
regression fixture: its `review_evidence_rules()` change must be rejected by
the preflight without amending or executing the candidate.

A legitimate future policy change requires a separately reviewed owner
contract and trusted-base publication/loading mechanism. This contract defines
no bypass.

## Python decision-evidence contract

The private Python adapter:

1. Treats unified-diff context as a discovery seed, never as complete evidence.
2. Identifies relevant module bindings represented anywhere in HEAD-side hunk
   lines, including unchanged context.
3. Parses the exact-HEAD blob with Python `ast`.
4. Finds uses of seeded bindings in membership/non-membership and supported
   decision expressions anywhere in the same file.
5. Captures the full enclosing decision expression plus material same-file
   bindings/helpers.
6. Evaluates only literal collections, local names bound to them, set union,
   boolean operators, negation, supported comparisons, and literal
   defaults/fallbacks.
7. Emits `complete` only when the bounded supported dependency closure is
   present. Otherwise it emits `unresolved` without a guessed result.
8. Never imports, evaluates, compiles for execution, or runs PR code.

## Required PR #199 interpretation

The deterministic fixture uses:

```python
VALID_TIERS = {"explore"}

def _tier_of(name):
    match = TIER_DIRECTIVE.search(name)
    return match.group(1) if match else "production"

bad = [
    name
    for name in names
    if _tier_of(name) not in VALID_TIERS | {"production"}
]
```

Required structural output:

- `VALID_TIERS` is the hunk-visible anchor.
- The complete predicate is the out-of-hunk
  `_tier_of(name) not in VALID_TIERS | {"production"}` expression.
- The resolved allowed literals include `explore` and `production`.
- The local helper and its `production` fallback are attached as material
  dependencies.
- Removing `| {"production"}` changes the resolved allowed domain and proves
  that the test checks behavior rather than prompt vocabulary.

## Evidence bundle contract

The bundle contains:

- schema version;
- exact HEAD and full-diff digest;
- canonically ordered/deduplicated facts;
- stable path/spans and evidence ids;
- derivation and `content_trust`;
- `complete` or `unresolved` resolution; and
- explicit omissions.

Same request bytes and caps produce byte-identical ordering. Caps omit whole
facts and add an explicit omission; typed records are never silently sliced.

## Adapter and module contract

- Existing Swift receiver behavior remains an internal adapter and must retain
  the PR #171 regression.
- The Python predicate adapter is private and selected only by base-owned code.
- Callers cannot select or install adapters.
- Git blob access is an internal local-substitutable seam with production
  `git show` and fixture-map test adapters.
- No new public module, package, workflow, model call, or dependency is added.

## Failure contract

The gate stops before the model and returns non-zero for:

- invalid request/ref/path/cap or unreadable diff;
- protected instruction change/missing/duplicate/ambiguity;
- unreadable required non-deleted exact-HEAD blob;
- syntax error in a selected changed Python file;
- adapter exception;
- invalid typed evidence;
- serialization failure.

Legitimate deletion, unsupported/dynamic/cyclic semantics, and configured cap
omissions may produce a valid bundle only when explicit and without a
fabricated result.

All existing fetch, evidence, model, timeout, parse, schema, verdict
consistency, severity, and required-status failure paths remain fail closed.

## Preserved source contract

T001 may change:

- `scripts/ci/review_context.py`;
- `scripts/ci/review-common.sh` only inside `build_scope_evidence()` and its
  adjacent evidence-caller explanation;
- `scripts/ci/tests/test_review_context.py`;
- `scripts/ci/tests/test_review_shell.py` only for evidence forwarding,
  preflight, fence placement, and fail-closed integration; and
- `docs/ci-gates.md` only for this structural evidence/preflight incident.

T001 must not change:

- `review_evidence_rules()` or `review_security_notice()`;
- `run_with_timeout` or any timeout/process-group test;
- `scripts/ci/codex-review.sh`, `claude-review.sh`, or `kimi-review.sh`;
- `.github/workflows/**`, `scripts/rulesets/**`, hooks, or
  `scripts/hooks/check-tasks-fresh`;
- `scripts/ci/swift_scope.py`;
- any `aidata/**`, Swift/App/CLI path, PR #199, or PR #205 branch/candidate.

## Delivery precondition

Before implementation, Team Lead pins the exact T001 base and verifies a
successful same-SHA `review-gate (pytest)` result. A changed base requires new
evidence.

PR #205 remains Draft with auto-merge disabled. T001 starts from a new clean
current-main branch and produces a separate repair PR.
