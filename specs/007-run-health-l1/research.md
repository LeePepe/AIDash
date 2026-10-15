# Research: Dev Team Run-Health L1 Collection

## Decision 1: Preserve cadence and add one registered L1 source

**Decision**: Keep the existing timer/cadence, let the three Multica sources write their additive families, and register `copilot_otel` in `config.SOURCES` plus the repository runner. Keep it out of `MERGE_SOURCES`; provide a tested `normalize() -> 0` that creates no clean DB because this issue is L1-only.

**Rationale**: The accepted lead addition explicitly asks for an aidata L1 source. The current runner's registry-equality test requires explicit wiring, while the generic CLI calls `normalize()` for every source. A no-op normalizer satisfies that interface without inventing L2 scope; one existing timer remains authoritative.

**Alternatives considered**:

- Hide OTel collection inside `multica_run`: rejected because it contradicts the requested source boundary and couples local-file progress to Multica collection.
- Give OTel a clean schema/merge path: rejected as unauthorized L2/L3 scope.
- Create a separate daemon: rejected because it expands operations and ownership beyond this L1 feature.

## Decision 2: Use an explicit per-workspace agent allowlist

**Decision**: Configure `(workspace_id, agent_id)` pairs in ignored local configuration. Do not enumerate every workspace agent dynamically.

**Rationale**: `agent tasks` and `agent get` take a globally resolvable agent ID but no workspace flag. The existing aidata design uses explicit allowlists for personal data sources, and tracked defaults must contain no machine/account identifiers. Pairing the IDs preserves workspace provenance without a broad discovery call.

**Alternatives considered**:

- `multica agent list`: rejected because it widens collection scope and was not required.
- Infer agents from old runs: rejected because it cannot discover the first run from a new agent and repeats the staleness problem.

## Decision 3: Agent task history owns run discovery and lifecycle

**Decision**: Use `multica agent tasks <agent>` for every run discovery and retain per-agent pending run IDs until an explicit terminal status is observed.

**Rationale**: The existing issue-number watermark misses new runs on old issues and never refreshes a running observation. Task history supplies queue timestamps, failure/cancellation facts, and run-local usage. A pending set makes lifecycle completion independent of how old the issue is.

**Alternatives considered**:

- Widen the issue-number window: rejected because any finite issue window can still miss an old issue.
- Continue `issue runs` plus revisit recent issues: rejected because age is not a safe lifecycle-completeness signal.
- Treat unknown status as terminal: rejected because it silently makes future statuses stale.

## Decision 4: Preserve existing normalized-run compatibility

**Decision**: Project the legacy raw keys consumed by `multica_run.normalize()` while adding raw-only lifecycle fields. `issue usage` may remain a compatibility enrichment for runs already discovered by agent history, never a discovery source.

**Rationale**: L1-only scope forbids a new normalized schema but does not authorize breaking the current one. The adapter can change how records are found while keeping the clean table contract stable.

**Alternatives considered**:

- Rewrite the clean schema for the new task payload: rejected as L2 scope.
- Drop legacy per-issue token columns: rejected because current downstream consumers may rely on them.

## Decision 5: Project and sanitize before raw persistence

**Decision**: Build explicit persistence DTOs from CLI/file payloads. Canonicalize strings as UTF-8 and structured values as sorted compact JSON, then store full lowercase SHA-256 and canonical byte length. Never pass a whole agent-task, run-message, or OTel span payload to `write_raw`. Permitted run lifecycle text uses a deterministic pre-DTO sanitizer rather than relying on `rawio` alone.

**Rationale**: `rawio` redaction is a useful secondary defense but it neither removes filesystem paths nor justifies persisting high-risk message bodies, email addresses, URLs, paths, or trigger payloads. A DTO with no raw-content member plus path-safe bounded lifecycle text makes the privacy invariant structural and sentinel-testable while preserving normalized-run key/type compatibility.

**Alternatives considered**:

- Store redacted previews: rejected for new message/tool content because redaction cannot prove all business prose or secrets are removed.
- Hash Python `repr`: rejected because mapping order and representation are not a stable cross-run contract.

## Decision 6: Match red-line rules before hashing

**Decision**: Apply one ordered, token-aware rule list to transient tool input and store only the first matched identifier. Rule order is specific before generic.

**Rationale**: Hashing first destroys the evidence needed to classify a command. Storing matching text would violate the same privacy boundary. Token-aware parsing prevents substrings such as `--administrator`, prose mentioning `-f`, or a non-protected force push from becoming false positives.

**Alternatives considered**:

- Regex every raw string: rejected due to false positives and shell quoting ambiguity.
- Store all matching rules: rejected because the issue asks for the matched rule name and a deterministic first match keeps the record compact.
- Turn matches into enforcement: rejected because this collector is read-only observation, not authorization.

## Decision 7: Preserve empty usage as an observation

**Decision**: Wrap runtime usage responses with provenance and collection time even when the response is empty. Run model/token fields remain absent when usage supplies none.

**Rationale**: Copilot-runtime runs legitimately expose empty usage, and `runtime usage` can return nothing. Empty is evidence about source observability; zero tokens or the agent's configured model would be fabricated data.

**Alternatives considered**:

- Default counts to zero: rejected because zero means measured no usage, not unreported usage.
- Fall back to agent model: rejected because agent configuration is not proof of the model used by an individual run.

## Decision 8: Collect activity-only timelines with explicit incompleteness

**Decision**: Use `issue timeline --activity-only`, replay a one-second cursor overlap, and preserve classified truncation warnings from successful stderr.

**Rationale**: Activity-only excludes comment bodies and contains the status history needed later. Timeline reads can be server-truncated; hiding successful stderr would let analysis mistake a partial backfill for full history.

**Alternatives considered**:

- Derive status changes from issue snapshots: rejected because intermediate transitions disappear.
- Store full timeline comments: rejected as duplicate, high-risk content already owned by `multica_comment`.
- Ignore stderr on exit zero: rejected because the CLI documents truncation there.

## Decision 9: Extract PR candidates transiently with provenance

**Decision**: Extract strict GitHub PR URLs from issue metadata and comments while those source objects are in memory, then store only normalized URL and source provenance.

**Rationale**: Later correlation needs evidence of where a link came from, but not the surrounding free text. A strict URL shape avoids treating repository pages, issue URLs, or arbitrary links as pull requests.

**Alternatives considered**:

- Depend only on `github_pr`: rejected because that source cannot recover the Multica issue association.
- Store one URL per issue: rejected because it erases conflicting or multiple-source provenance needed for later deduplication.

## Decision 10: Separate fixture proof from one real acceptance run

**Decision**: CI and unit tests inject canned responses/files and forbid live Multica subprocess calls. Before prepublication implementation review, one local configured run records a nonzero sanitized count and sample for all eight raw families. Remote/PR SHA proof occurs only after that fixed candidate receives PASS/publication permission and is pushed.

**Rationale**: Hermetic CI is a repository red line. A single live acceptance run is still needed to prove current CLI shapes and end-to-end wiring, but its evidence must not expose machine-local IDs or raw content.

**Alternatives considered**:

- Live Multica in CI: rejected because it depends on credentials, changing remote state, and private data.
- Fixtures only with no live check: rejected because CLI/file response shape and local wiring would remain unverified.
- Accept zero rows plus a reason: rejected because it cannot distinguish a genuinely empty source from an unwired/broken family and does not satisfy RH-L1-013.
- Push/create the PR before independent implementation review: rejected because it violates the fixed candidate → prepublication review → publish order.

## Decision 11: Use a transition ordinal for agent snapshots

**Decision**: Persist `transition_ordinal` and a `snapshot_key` derived from `(agent_id, transition_ordinal, config_hash)`. Per-agent state holds committed hash/ordinal plus a durable pending candidate containing the ordinal, hash, first-observed time, and complete canonical allowed snapshot projection; pending is written before raw persistence, replayed as the sole row source, then committed/cleared only after success.

**Rationale**: Hash-only identity collapses the third observation in `A → B → A`. A source update timestamp is not guaranteed by the observed CLI contract. Persisting only the pending hash cannot reconstruct model/runtime/concurrency values if the live source changes before retry. The complete pending projection makes write failure and crash-after-write reuse the same logical key/time/values, while a genuine return to A gets a new ordinal.

**Alternatives considered**:

- `(agent_id, config_hash)`: rejected because it loses recurring configurations.
- `observed_at` in the key: rejected because retry changes collection time and duplicates one transition.
- Source `updated_at`: rejected because the required CLI fields do not guarantee it.

## Decision 12: Collect Copilot OTel as a registered L1-only source

**Decision**: Configure ignored local JSONL paths only against the tracked neutral source-slot allowlist `fullstack` and `pr-manager`; reject unknown or duplicate slots before file access. `copilot_otel.collect()` tracks device/inode/generation/byte offset, consumes only newline-terminated records, projects chat spans to an allowlist, and writes `copilot_otel`. Its required normalizer is an explicit no-op.

**Rationale**: The Owner-selected token source is independent of Multica's truthfully empty usage. Conversation ID equals run `result.session_id`, but sessions can cross run boundaries; preserving source timestamps enables a later L2/L3 window join without fabricating attribution in L1. Registering the source on the existing cadence matches the accepted source boundary without adding a timer.

**Alternatives considered**:

- Fill Multica run/runtime usage from OTel in L1: rejected because it fabricates a source field and performs an out-of-scope join.
- Join on conversation ID alone: rejected because several runs can share one session.
- Advance past an incomplete trailing JSON line: rejected because the exporter may finish that record later.
- Key only by canonical payload: rejected because two genuine identical spans could collapse; the key also uses source slot, stream generation, and line-start offset while never persisting the path.
- Persist response ID, context, content, whole span, or file path: rejected because none is needed for tokens/window correlation and each expands the privacy surface.
- Permit arbitrary locally configured source labels: rejected because a persisted free-form label can itself disclose personal or machine-local identity; the two Owner-selected role labels are sufficient for this scope.

## Resolved Unknowns

- `agent tasks` advertises `--limit` and `--before`; implementation supports cursor envelopes and treats a full bare list with no cursor as incomplete instead of guessing.
- `issue timeline` has `--activity-only` and `--since`; truncation warnings are emitted on stderr even on success and therefore need a metadata-preserving runner.
- `agent tasks`/`agent get` have no workspace flag; workspace provenance comes from the explicit agent configuration pair.
- Copilot empty usage is a valid source result, not an error and not a zero-token measurement.
- The OTel token source remains a separate L1 observation; future attribution requires both conversation ID and a source timestamp inside the run window.
- `copilot_otel` is synchronized to the repository runner before review, but the separately installed `~/.hermes/scripts` copy is deployed only from the merged revision by authorized operations, never from the unreviewed candidate.

No unresolved clarification remains for implementation.
