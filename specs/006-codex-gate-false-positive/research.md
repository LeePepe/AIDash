# Research: Complete-Predicate Review Evidence

## Incident evidence

- PR #199 exact HEAD `6cefdd4ac8b00dc8b896014cca3ba38ec6dcff17`
  was evaluated twice by `codex-review-target` in Actions run `33326353325`.
- Both attempts produced one blocker claiming that
  `-- aidata-tier: production` conflicts with
  `VALID_TIERS = {"explore"}`.
- At that exact PR HEAD, the validator checks membership in
  `VALID_TIERS | {"production"}` and the tier helper also defaults an absent
  marker to `production`. The alleged invalid value is therefore accepted.
- The same-head `aidata (pytest + ruff)` check passed. The exact-SHA Multica AI
  Reviewer also passed the two-file AidataL4 surface.

## Repository control-path findings

- `.github/workflows/codex-review-target.yml` checks out the trusted base and
  invokes `scripts/ci/codex-review.sh`.
- `scripts/ci/codex-review.sh` assembles the live prompt and calls the shared
  `review_evidence_rules()` helper before the untrusted-data fence.
- `scripts/ci/review-common.sh` owns the shared trusted evidence and security
  prompt interfaces.
- `scripts/ci/tests/test_review_shell.py` already exercises the real helper and
  pins earlier false-positive repairs.
- Python changes do not produce Swift `SCOPE_EVIDENCE`; the incomplete hunk
  remained the only semantic context for the tier claim.

## Precedents

- The Swift receiver incident added exact-HEAD evidence plus a rule that
  forbids blockers when receiver ownership is unresolved.
- The review-token incident replaced literal-token matching with an
  intent-based rule and pinned the shared helper contract.

Both precedents repaired a repeatable false inference while preserving the
trusted-base boundary and fail-closed execution.

## Decision

Extend the existing shared evidence discipline with a generic
complete-predicate requirement and pin the PR #199 predicate shape in the
existing deterministic test module. This is the smallest seam that addresses
the proven failure without changing product code or merge policy.

## Alternatives

| Alternative | Decision | Reason |
|---|---|---|
| One-time admin bypass | Reject | Owner selected fail-closed repair; recurrence remains |
| Add `production` to the isolated set | Reject | It is already accepted by the full union; would mutate Aidata to mask a gate bug |
| Change tier marker to `explore` | Reject | Changes the reviewed L4 contract and is semantically wrong |
| Supply complete source for every changed non-Swift file | Defer | Broader evidence generator, prompt-volume, and failure-surface change than this incident requires |
| New language-specific Python analyzer | Reject | Over-engineered for a generic evidence-discipline defect |
| Duplicate a new rule in `codex-review.sh` | Reject | Creates prompt drift; existing shared helper is the correct interface |

## Verification decision

The implementation is proven by the resolver-declared RepoInfra local gate
through normal hooks:

`scripts/context/run RepoInfra --mode local`

The gate expands to the repository CI/context pytest suite and hook syntax.
CI runs the corresponding RepoInfra CI gate and ruff. No App or Aidata suite is
manually added to this layer task.
