# Contract: Complete-Predicate Evidence Discipline

## Purpose

Prevent a required automated reviewer from issuing an invalid-value,
test-failure, or CI-failure blocker from an incomplete diff hunk while keeping
direct defects and tool failures fail closed.

## Trusted instruction contract

The shared `review_evidence_rules()` prompt text MUST state that:

1. A blocking validation claim cites and evaluates the complete deciding
   predicate available in the diff or supplied evidence.
2. Evaluation includes material unions, fallbacks/defaults, normalization,
   negation, and helper qualifiers.
3. An isolated constant or partial hunk is not proof of rejection.
4. When the complete predicate is absent, this class of claim cannot become a
   blocker; uncertainty may be a note.
5. A complete predicate that directly proves a critical/high defect remains a
   blocker.

The contract is placed before the untrusted-data fence and is consumed by the
live Codex gate through the existing shared helper.

## Regression example

The deterministic regression MUST pin this semantic shape:

```python
VALID_TIERS = {"explore"}

if tier not in VALID_TIERS | {"production"}:
    reject(tier)
```

Required interpretation:

- `production` is accepted.
- `VALID_TIERS = {"explore"}` alone cannot prove otherwise.
- A value outside the full union remains rejected and may support a blocker
  when that complete predicate is supplied.

## Preserved contracts

- `codex-review-target` remains required.
- Trusted-base checkout and untrusted PR-data fencing are unchanged.
- Critical/high directly proven defects still block.
- Evidence generation, timeout, model, parse, and schema failures still exit
  non-zero.
- No admin bypass path is added.
