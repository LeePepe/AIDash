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
4. Base-owned code supplies schema labels, headings, provenance, per-claim
   completion state, ordering, hashes, and omission notices.
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

## Self-protecting enforcement contract

After T001 lands, before model invocation, the base-owned implementation
protects every link that makes the check unavoidable as a whole tracked file:

1. `scripts/ci/review_context.py`;
2. `scripts/ci/review-common.sh`;
3. `scripts/ci/codex-review.sh`;
4. `.github/workflows/codex-review-target.yml`; and
5. `scripts/rulesets/main-protection.json`.

This set contains the detector/manifest/entrypoint, evidence invocation and
non-zero propagation, reviewer instructions, prompt/fence/model/verdict
control flow, workflow event/job/checkout/invocation, and required merge
policy. The trusted base compares base/head blob identity and requires each
path to remain one regular tracked blob. Any changed, missing, replaced, or
ambiguous protected file returns `protected_enforcement_change` non-zero.
The model is not invoked.

Whole-file protection prevents escape through an unlisted helper, alternate
definition/source, early return, workflow condition, or ruleset field. The
preflight reads no allowlist, exemption, attestation, expected hash, or plugin
path from PR data.

PR #205 at `f16e5d503304b7951f995286cdbb0727b6d2472e` is a mandatory
regression fixture: its `review_evidence_rules()` change must be rejected by
the landed preflight without amending or executing the candidate. Independent
fixtures must also mutate each of the other four protected files; each must
fail before a model stub runs.

### One-time T001 bootstrap

T001 is the only bootstrap publication authorized by this contract. Its base
does not yet contain the detector, so bootstrap acceptance comes from all of:

- this exact planning revision and owner option B;
- B000 on the exact implementation base;
- a new branch/worktree distinct from PR #205;
- an implementation diff confined to the reviewed T001 file/region allowlist;
- local HEAD = remote branch OID = PR `headRefOid`;
- all required checks green; and
- fresh exact-SHA Multica AI Reviewer PASS before PR Manager merge.

Once that exact T001 revision reaches `main`, this bootstrap authority is
consumed. A legitimate later policy or enforcement change requires a new
owner decision and separately reviewed trusted-base publication/loading
contract. This contract defines no persistent bypass.

## Python decision-evidence contract

The private Python adapter:

1. Treats unified-diff context as a discovery seed, never as complete evidence.
2. Identifies relevant module bindings represented anywhere in HEAD-side hunk
   lines, including unchanged context.
3. Parses the exact-HEAD blob with Python `ast`.
4. Finds uses of seeded bindings in membership/non-membership and supported
   decision expressions anywhere in the same file.
5. Captures the full enclosing decision expression plus material same-file
   bindings/helpers as separately scoped claims and observations.
6. Evaluates only literal collections, local names bound to them, set union,
   boolean operators, negation, supported comparisons, and literal
   defaults/fallbacks.
7. Records completion per claim. Predicate structure and safely evaluated RHS
   allowed domain may be complete independently; dynamic subject/helper
   semantics are unresolved. A literal fallback is a syntactic observation,
   not proof of runtime selection.
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

Required claim-scoped output:

- `VALID_TIERS` is the hunk-visible anchor.
- The complete predicate is the out-of-hunk
  `_tier_of(name) not in VALID_TIERS | {"production"}` expression.
- The `predicate_structure` claim is complete.
- The independently evaluated RHS `allowed_domain` claim is complete and
  includes `explore` and `production`.
- The `subject_helper_semantics` claim is unresolved because
  `TIER_DIRECTIVE.search` and `match.group` are outside the safe subset.
- The helper's literal `production` fallback is recorded as a syntactic
  observation with unresolved runtime selection, not complete helper meaning.
- Removing `| {"production"}` changes the resolved allowed domain and proves
  that the test checks behavior rather than prompt vocabulary.

## Evidence bundle contract

The bundle contains:

- schema version;
- exact HEAD and full-diff digest;
- canonically ordered/deduplicated facts;
- stable path/spans and evidence ids;
- derivation and `content_trust`;
- an ordered set of independently `complete` or `unresolved` claim records
  plus non-semantic observations; and
- explicit omissions.

There is no fact-wide completion flag. One unresolved claim neither downgrades
nor certifies an independent claim. Same request bytes and caps produce
byte-identical fact/claim ordering. Caps omit whole facts and add an explicit
omission; typed records are never silently sliced.

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
- protected enforcement link change/missing/duplicate/shadow/move/bypass/
  ambiguity;
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

- `scripts/ci/review_context.py` for the one-time bootstrap implementation;
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

The workflow, Codex consumer, and ruleset paths are protected verification
targets but remain byte-unchanged and out of T001 implementation scope.

## Delivery precondition

Before implementation, Team Lead pins the exact T001 base and verifies a
successful same-SHA `review-gate (pytest)` result. A changed base requires new
evidence.

PR #205 remains Draft with auto-merge disabled. T001 starts from a new clean
current-main branch and produces a separate one-time bootstrap PR. After that
exact reviewed revision lands, later protected-chain changes require a new
owner-reviewed publication contract.
