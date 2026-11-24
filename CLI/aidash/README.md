# Action Items bridge commands

`aidash --json job-actions snapshot` returns the versioned action snapshot, including recorded entries and safe per-job source diagnostics. Missing source files are not healthy-empty results. Receipts match the exact job, action, `scheduledPulse` card type and `acknowledgeJobAction` event action.

`aidash --json job-actions present --stdin` accepts one UTF-8 JSON proposal of at most 16 KiB with exactly `requestID`, `jobID`, `actionID`, `revision` and `responses`. Use the opaque revision from a successful snapshot and one `{controlID,value}` response per declared control. Confirm is `确认`; single-select values match declared options; multi-select values are Swift-sorted comma-joined options; text is bounded by the declaration and 80 graphemes. Reuse a request UUID only for the identical proposal.

Present uses XPC only and stages native App review. `awaitingNativeConfirmation` is not a recorded receipt. Only explicit native confirmation can append the existing UserEvent. Later snapshots expose the actual saved receipt; recording does not mean the underlying job executed. No confirmation, event-write, callback URL or executable-path option exists.

Both bridge commands emit the existing JSON success envelope. Local validation errors exit 1, transport failures exit 2, and server failures exit 3 with the existing stderr error envelope. There is no direct store fallback. The CLI's existing App-launch transport behavior is unchanged.
