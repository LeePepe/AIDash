# Contract Pointer: Manual-Batch T7 Evidence

## Status

The former cross-product E2E-05 reader path through per-object L1 state, L3,
and L4 is superseded for this feature by
[`manual-batch-collector.md`](manual-batch-collector.md) MB-017. That contract is
the sole authority for the later private batch/Blob-scoped T7 evidence and its
public privacy boundary.

Existing producer, consent, event-wire, and rollback acceptance remains governed
by [`aidash-events.md`](aidash-events.md) and the producer/lifecycle sections of
[`blob-wire.md`](blob-wire.md); this pointer changes none of it. Generic
`python3.14 aidata/cli.py collect`, templates, fake traces, and test counts are
not manual Blob-ingestion evidence.

T7 remains a post-merge milestone requiring separate live authorization. This
file authorizes no source change, credential access, Azure role/resource change,
live command, TestFlight operation, or query-product implementation.
