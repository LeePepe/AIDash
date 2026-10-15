# Research: Dev Team Run-Health L0 Collection

## Decision 1: Extend existing scheduled adapters

**Decision**: Keep `multica_issue`, `multica_run`, and `multica_comment` as the only scheduled source names. Let them write additive raw sub-families.

**Rationale**: The current runner already invokes these sources and its registry-equality test protects that wiring. The feature is raw collection, not a new independently normalized source. This keeps the schedule unchanged and avoids a second collection pass over the same Multica objects.

**Alternatives considered**:

- Register six new sources: rejected because each would require runner wiring and duplicate CLI discovery while providing no L2 normalizer.
- Create a separate daemon: rejected because it expands operations and ownership beyond this L0 feature.

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

**Rationale**: L0-only scope forbids a new normalized schema but does not authorize breaking the current one. The adapter can change how records are found while keeping the clean table contract stable.

**Alternatives considered**:

- Rewrite the clean schema for the new task payload: rejected as L2 scope.
- Drop legacy per-issue token columns: rejected because current downstream consumers may rely on them.

## Decision 5: Project and sanitize before raw persistence

**Decision**: Build explicit persistence DTOs from CLI payloads. Canonicalize strings as UTF-8 and structured values as sorted compact JSON, then store full lowercase SHA-256 and canonical byte length. Never pass a whole agent-task or run-message payload to `write_raw`.

**Rationale**: `rawio` redaction is a useful secondary defense but it is not a reason to persist high-risk message bodies, email addresses, paths, or trigger payloads. A DTO with no raw-content member makes the privacy invariant structural and sentinel-testable.

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

**Decision**: CI and unit tests inject canned responses and forbid live subprocess calls. After implementation, one local configured run records sanitized counts/samples for all seven raw families.

**Rationale**: Hermetic CI is a repository red line. A single live acceptance run is still needed to prove current CLI shapes and end-to-end wiring, but its evidence must not expose machine-local IDs or raw content.

**Alternatives considered**:

- Live Multica in CI: rejected because it depends on credentials, changing remote state, and private data.
- Fixtures only with no live check: rejected because CLI response shape and local wiring would remain unverified.

## Resolved Unknowns

- `agent tasks` advertises `--limit` and `--before`; implementation supports cursor envelopes and treats a full bare list with no cursor as incomplete instead of guessing.
- `issue timeline` has `--activity-only` and `--since`; truncation warnings are emitted on stderr even on success and therefore need a metadata-preserving runner.
- `agent tasks`/`agent get` have no workspace flag; workspace provenance comes from the explicit agent configuration pair.
- Copilot empty usage is a valid source result, not an error and not a zero-token measurement.

No unresolved clarification remains for implementation.
