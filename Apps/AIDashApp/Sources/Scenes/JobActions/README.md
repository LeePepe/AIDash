# Native Action Items review

`job-actions.snapshot` reads registered job actions and exact job/action acknowledgement receipts through App-owned adapters. Missing, malformed, oversized and unavailable sources remain per-job diagnostics; an unrelated missing file does not disable a valid action. No bridge command starts a scheduler, edits a source or writes a UserEvent.

`job-actions.present` validates one proposal and opens the native `JobActionsReviewView`. The in-memory coordinator retains at most 16 proposals for five minutes. Request IDs are idempotent while retained; changing a proposal requires a new UUID. Cancel, close and expiry write nothing. Native confirmation revalidates the action revision and receipt, then calls the throwing `UserEventWriter` save path. A failed save keeps the proposal visible and retryable; recorded state follows successful persistence only.

New receipts retain current-main encoding: `scheduled-pulse/<jobID>`, `acknowledgeJobAction`, `scheduledPulse`, and `<jobID>:<actionID>|<JSON responses>`. Legacy unprefixed receipts are read-compatible only under exact card/job scoping and without reinterpreting a recognized job prefix. Receipt recording does not mean downstream execution.

Hostless tests inject source, clock, presenter and persistence adapters. Production adapters refuse live home/store access in an XCTest process. Native UI is created only after explicit valid presentation. No new event schema, store, network channel or telemetry is introduced.
