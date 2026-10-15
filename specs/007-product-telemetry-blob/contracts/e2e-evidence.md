# Contract: E2E-05 Sanitized Evidence

This is a post-merge, cross-repository acceptance gate owned by Team Lead. It is not authority for a repository implementer to edit another repository, read credentials, change roles, or run a live canary before OA-003/OA-004 approval.

For each of VitalStride and AIDash, the bounded evidence set must contain:

1. Exact merged repository revision and recorded UTC interval.
2. One allowlisted action canary and one allowlisted performance canary from actual product composition.
3. Product/build plus sanitized object-path fingerprint, ETag or content hash, and observed receipt time.
4. Matching deterministic `aidata` source-event key and L1 completion checkpoint.
5. Matching `fact_product_event` grain/count and bounded L4 query row.
6. Rerun proof with no duplicate fact/query row.
7. One deliberately unsafe event rejected before accepted persistence/network and absent from Blob and L4.
8. Sanitized authorization evidence that each writer is create-only and the reader is read/list-only, without exposing the real endpoint, principal metadata, token, SAS, or account key.

AIDash's expected set contains only its two product canary kinds and zero SDK-owned heartbeat events. Object count is proven by correlated keys, not inferred from event count or `flush()`.

Evidence uses fingerprints/redactions for install IDs and paths. Raw event payloads, personal identifiers, unrestricted endpoints, credentials, and local paths are prohibited.

E2E-05 passes only when both products and both event types correlate through producer, Blob, L1, L3, and L4 and the independent reviewer verifies the exact merged revisions.
