# Contract: Complete-Predicate Evidence Discipline

## Purpose

Prevent a required automated reviewer from claiming that a value is invalid or
rejected from an incomplete diff hunk while keeping direct defects, explicit
test/CI failures, and tool failures fail closed.

## Trusted instruction contract

The shared `review_evidence_rules()` prompt text MUST state that:

1. A blocking claim that a value is invalid or rejected cites and evaluates the
   complete deciding predicate available in the diff or supplied evidence.
2. Evaluation includes material unions, fallbacks/defaults, normalization,
   negation, and helper qualifiers.
3. An isolated constant or partial hunk is not proof of rejection.
4. When the complete predicate is absent, this class of claim cannot become a
   blocker; uncertainty may be a note.
5. A complete predicate that directly proves a critical/high defect remains a
   blocker; direct test or CI failure output remains independent evidence.

The contract is placed before the untrusted-data fence and is consumed by the
live Codex gate through the existing shared helper.

## Regression example

The deterministic regression MUST pin the prompt's abstention behavior for this
semantic shape:

```python
VALID_TIERS = {"explore"}

if tier not in VALID_TIERS | {"production"}:
    reject(tier)
```

Required interpretation:

- The complete expression accepts `production`.
- A hunk containing only `VALID_TIERS = {"explore"}` cannot prove otherwise,
  so the reviewer must abstain from a rejection blocker.
- A value outside the full union remains rejected and may support a blocker
  when that complete predicate is supplied.

The regression verifies the trusted prompt rule and its live shared-helper
consumption. It does not claim to make a nondeterministic model response into a
hermetic assertion.

## Preserved contracts

- `codex-review-target` remains required.
- Trusted-base checkout and untrusted PR-data fencing are unchanged.
- Critical/high directly proven defects still block.
- Evidence generation, timeout, model, parse, and schema failures still exit
  non-zero.
- No admin bypass path is added.
