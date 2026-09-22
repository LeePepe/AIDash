# Contract: Owner Decision Events

## Locked actions

| Meaning | `UserEventAction.rawValue` |
|---|---|
| Acknowledgement receipt | `auditFindingAcknowledged` |
| Approval receipt for separately governed remediation | `auditFindingRemediationApproved` |

Both actions are additive to existing `done`, `undone`, and `star` behavior.
Unknown historical/future actions are never coerced into these cases.

## Event target

```json
{
  "id": "<uuid>",
  "timestamp": "<utc-iso8601>",
  "device": "<existing-device-id>",
  "cardId": "<deterministic-findings-card-id>",
  "action": "auditFindingAcknowledged",
  "itemRef": "<stable-finding-fingerprint>",
  "cardType": "teamAudit"
}
```

The finding fingerprint is the semantic decision target. The card ID preserves
the exact published context in which the decision was made.

## Write and display semantics

- AIDashUI exposes two optional intent closures and two receipt sets through
  environment values. Default values are nil/empty and degrade to no-op.
- AIDashApp is the only writer. It appends a `UserEventModel` and never updates
  or deletes a prior event.
- Repeated local taps are idempotent per `(cardId, itemRef, action)`.
- Displayed receipt state collapses persisted events by `(itemRef, action)`;
  it does not replace `AuditFinding.state`.
- Persistence failure leaves the receipt unconfirmed and never crashes or
  claims success.
- The aidata event adapter preserves both action raw values, `itemRef`, and
  `cardType` so a later explicitly run audit can observe the decision lineage.

## aidashCLI consumer

`aidash events pull --action` advertises and accepts every canonical
`UserEventAction.rawValue`, including both camel-case audit values. Parsing is
case-insensitive but must compare against the canonical cases; it must not
lowercase the input and then attempt raw-value construction. Unknown-action
errors derive their `allowed` array from `UserEventAction.allCases`, and JSONL
output preserves the canonical camel-case raw value unchanged.

## Authority denial

Neither action may invoke an audit, execute remediation, create or update an
issue, mutate a run, choose an implementation owner, dispatch an agent, or
claim a finding resolved. The approval label and accessibility copy must say
that approval is recorded for a separate workflow.

## Verification contract

- Core round-trip tests lock raw values and factory output.
- UI intent-spy tests prove exact fingerprint/action targeting and no-op
  defaults.
- App in-memory writer tests prove append-only idempotency and receipt
  derivation without CloudKit/network access.
- Boundary spies prove that decision actions call only the injected writer.
- aidata adapter tests prove new actions do not normalize to null/unknown.
- aidashCLI tests prove help/validation/filter/JSONL behavior for both audit
  actions while preserving `done`, `undone`, and `star`.
