# Contract: Product Blob Reader Authorization and Configuration

## Status

Superseded by [`manual-batch-collector.md`](manual-batch-collector.md).

The former `DefaultAzureCredential`, hand-built LIST/GET, page/object budget,
custom byte-cap, and checkpoint contract never shipped and is no longer
implementation authority. The replacement contract exclusively defines the
direct Azure CLI identity boundary, exact manual batch invocation, privacy,
staging, completion-directory semantics, output, tests, and T7 evidence.

Producer authorization and Blob wire behavior remain governed by
[`blob-wire.md`](blob-wire.md) and ADR-004; this pointer does not supersede
either producer contract.
