# Contract: AIDash Product Events

This table is the complete AIDash product vocabulary for this feature. LokiKit
owns transport and validation mechanics only; it must not add product events or
properties.

| Event | Trigger | Allowed properties | Sampling and cardinality |
|---|---|---|---|
| `aidash.action` | First appearance of the interactive `.ready(container)` briefing view in an eligible GUI lifecycle | `action_name`: closed string enum whose only case is `briefing_viewed` | 100% (no sampling); at most once per eligible GUI lifecycle |
| `aidash.performance.ready_scene` | The same first-ready callback | `duration_ms`: finite, nonnegative integer | 100% (no sampling); at most once per eligible GUI lifecycle |

An eligible lifecycle is GUI production composition with persisted consent
already true when app initialization reads it and valid producer configuration.
The launch instant is captured before those eligibility checks, then discarded
if they fail. If consent is enabled only after the scene is already ready, the
app emits no retrospective event. Both events are absent if the scene never
becomes ready or consent is revoked before the trigger. The event-envelope
timestamp is UTC at emission.

## Ready-scene timing

- Use Swift `ContinuousClock`; wall-clock adjustment must not affect the value.
- Capture `launchStart` as the first operation at entry to the GUI-production
  branch of `AIDashApp.init`, immediately after the fixed run-mode decision and
  before reading consent/configuration or starting bootstrap/service work.
  Discard the instant for an ineligible lifecycle; do not shift the start
  boundary forward to successful validation.
- Capture `readyEnd` on the first appearance of the interactive
  `.ready(container)` briefing view.
- Calculate `duration_ms` as the count of complete milliseconds in
  `readyEnd - launchStart`: seconds multiplied by 1,000 plus attoseconds divided
  by 10^15. Reject negative or integer-overflow results rather than clamping or
  emitting them.

## Property boundary

The two keys above are the entire property allowlist. No install ID, consent
state, endpoint, file path, free text, user-entered value, briefing/UserEvent
content, device/hardware identity, raw clock value, or additional property is
allowed. An unknown key/value, non-finite number, or non-enum action rejects the
whole event before accepted persistence or network transmission.
