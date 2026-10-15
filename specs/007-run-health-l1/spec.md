# Feature Specification: Dev Team Run-Health L1 Collection

**Feature Branch**: `007-run-health-l1`

**Created**: 2026-10-15

**Status**: Draft

**Input**: Collect privacy-safe raw evidence for later Dev Team run-health analysis without implementing analysis, metrics, or UI.

## Existing behavior

- The scheduled `multica_issue`, `multica_run`, and `multica_comment` sources collect through the existing aidata pipeline.
- `multica_run` discovers executions by walking known issues and advances a highest-issue-number watermark. A later execution on an older issue is never discovered, and an execution observed before completion is never refreshed.
- Existing issue, comment, GitHub PR, and normalized run consumers are accepted behavior and must continue to work.
- The repository's external append-only raw collection boundary is L1 at `L1_collect/raw/<family>/<date>.jsonl`. This feature is aidata L1 collect only. No L2 normalization schema, L3 merge, L4 query, L5 app, metric, card, or UI is authorized.
- Copilot-runtime run and runtime usage are currently empty. Separately, the configured Copilot OTel JSONL files expose chat-span token fields whose conversation ID equals the Multica run `result.session_id`; one session can span several runs, so future attribution also needs the span timestamp inside the run's start/completion window.

## Compatibility

- The existing daily cadence remains unchanged. One registered L1 source, `copilot_otel`, is added to `config.SOURCES` and the repository runner; the runner verifier compares ordered lists so duplicates and reordering fail. Repository acceptance uses one authorized manual `cli.py collect` run and does not require an installed-Hermes mutation or live scheduled-run proof. `MERGE_SOURCES` remains unchanged and the source's required `normalize()` is an explicit no-op that creates no clean database.
- Existing `multica_issue`, `multica_comment`, `github_pr`, and `multica_run` normalized contracts remain compatible. New evidence is additive raw data.
- Repeated collection is idempotent by stable source identity. Missing source values remain missing; an absent or empty usage payload never becomes a zero-token observation.
- Copilot OTel spans remain an independent L1 source/family. This feature does not join spans into runs or alter run/runtime usage.
- No existing test is removed, skipped, or weakened to deliver this feature.

## Removed behavior

- Issue-number-only run discovery and its “collect once, never revisit” lifecycle behavior are removed. The 2026-10-15 lead decision explicitly replaces them with per-agent discovery and non-terminal re-reads.
- No other accepted behavior is removed.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Observe complete execution lifecycles (Priority: P1)

As a later run-health analyst, I can rely on raw execution observations that include newly created runs even when their issue is old and that eventually show how every initially non-terminal run ended.

**Why this priority**: Complete run discovery and lifecycle closure are the minimum trustworthy foundation for any later health analysis.

**Independent Test**: Replay fixtures in which an old issue receives a new run and a run changes from queued or running to a terminal state. Collection stores both observations under one stable run identity, retains privacy-safe queue/failure/cancel facts supplied by the source, and creates no duplicate logical run.

**Acceptance Scenarios**:

1. **US1/AC1** — **Given** an issue whose number is below the former run watermark, **When** a configured agent starts a new run on that issue, **Then** the run is discovered from that agent's task history and persisted.
2. **US1/AC2** — **Given** a run first observed in a non-terminal state, **When** later scheduled collections run, **Then** the run is re-read until a terminal observation supplies its final timestamps and available failure or cancellation facts.
3. **US1/AC3** — **Given** queue, dispatch, start, completion, status, `failure_reason`, `cancelled_by`, usage, or model facts are absent in the source response, **When** the observation is stored, **Then** each absent fact remains absent rather than being inferred or zero-filled; every present lifecycle free-text value is deterministically stripped of secrets, emails, URLs, local paths, controls, and over-limit suffixes before persistence while retaining its compatibility key/type.
4. **US1/AC4** — **Given** a Copilot-runtime run has an empty `usage` value and runtime usage returns no rows, **When** collection completes, **Then** those empty observations are recorded as received and no token or model value is fabricated.

---

### User Story 2 - Retain privacy-safe message and command evidence (Priority: P2)

As a later run-health analyst, I can count and correlate execution messages and identify configured red-line command patterns without storing the private raw message, tool input, or tool output content.

**Why this priority**: Message timing and command-risk evidence are valuable only if collection enforces the privacy boundary before persistence.

**Independent Test**: Feed fixtures containing unique secret sentinels and one positive and negative example for every configured rule. Persisted serialized rows contain timestamps, types, tool names, canonical hashes, byte lengths, and at most a matched rule identifier, but contain none of the sentinels or raw content.

**Acceptance Scenarios**:

1. **US2/AC1** — **Given** new messages for a known run, **When** collection starts after its last stored sequence, **Then** every later sequence is persisted once with run identity, sequence, timestamp, type, and available tool name.
2. **US2/AC2** — **Given** a message body, tool input, or tool output, **When** it crosses the persistence boundary, **Then** only its deterministic hash and UTF-8 byte length are stored and its raw content is absent from every new raw record.
3. **US2/AC3** — **Given** a tool input matching an enabled configured red-line rule, **When** the input is evaluated before hashing, **Then** the highest-priority matched rule name is stored and the matching text is not.
4. **US2/AC4** — **Given** `--admin`, `--no-verify`, a force push to a configured protected branch, or `gh pr merge` with a configured bypass flag, **When** positive and near-miss fixtures are evaluated, **Then** only the intended token-aware match is flagged.
5. **US2/AC5** — **Given** collection is replayed or a message query overlaps the prior cursor, **When** the same `(run_id, sequence)` returns again, **Then** no duplicate logical message is created and no sequence is skipped.

---

### User Story 3 - Correlate runs with operating context (Priority: P3)

As a later run-health analyst, I can correlate runs with change-only agent configuration, runtime activity, issue status history, and candidate GitHub PR links while remaining at the raw collection boundary.

**Why this priority**: These observations enable future queue, park/abandon, done-per-day, runtime, and delivery analyses without defining those metrics now.

**Independent Test**: Replay canned agent, runtime, issue timeline, issue metadata, and comment responses. The resulting raw families are idempotent, privacy-safe, provenance-bearing, and contain no normalized health metric.

**Acceptance Scenarios**:

1. **US3/AC1** — **Given** a configured agent's canonical configuration follows `A → B → A`, **When** collection and a crash-equivalent retry run, **Then** three ordered transition observations remain, the retry reuses the third key/time, and an unchanged later snapshot stores nothing.
2. **US3/AC2** — **Given** a runtime referenced by a configured agent, **When** usage and hourly activity are collected, **Then** the exact source observations are stored once per observation identity, including a truthful empty usage response.
3. **US3/AC3** — **Given** a known issue has status changes, task outcomes, or other activity records, **When** its activity-only timeline is collected incrementally, **Then** each event is persisted idempotently with issue provenance and server truncation is explicitly marked.
4. **US3/AC4** — **Given** issue metadata or a comment contains a valid GitHub pull-request URL, **When** candidate extraction runs transiently, **Then** the normalized URL, issue identity, source kind, source record identity, and observation time are persisted without the surrounding body or metadata.
5. **US3/AC5** — **Given** `copilot_otel` is registered in `config.SOURCES` and the repository runner, **When** ordered-list equality is verified and one authorized manual `cli.py collect` run executes with configured inputs, **Then** all eight raw families have persisted observations, the existing daily runner/timer remains otherwise unchanged, and no downstream schema or consumer changes.

---

### User Story 4 - Retain Copilot token evidence safely (Priority: P3)

As a later run-health analyst, I can use privacy-safe Copilot chat-span token evidence that is complete across growing files and sufficient for a later unambiguous run-window join without changing Multica's truthful empty usage.

**Why this priority**: Copilot-runtime roles otherwise have no token source, but local telemetry must remain deterministic, privacy-safe, and separate from later attribution logic.

**Independent Test**: Replay binary JSONL fixtures across complete, partial, resumed, rotated, and truncated file states, including prohibited sentinel attributes and one conversation shared by disjoint run windows. The collector emits each eligible span once, defers unfinished bytes, persists only the allowlist, and performs no run join.

**Acceptance Scenarios**:

1. **US4/AC1** — **Given** a configured Copilot OTel stream grows by newline-terminated spans and one incomplete trailing line, **When** `copilot_otel` collects from its byte cursor, **Then** complete lines are consumed once and the cursor remains at the incomplete line's first byte until it is completed.
2. **US4/AC2** — **Given** a stream rotates or truncates below its saved offset, **When** collection resumes, **Then** a new stream generation starts at byte zero and distinct spans retain replay-safe observation identities.
3. **US4/AC3** — **Given** a chat span contains token/model/conversation/timestamp fields plus response IDs, Copilot context, content, and other attributes, **When** it crosses the L1 boundary, **Then** only the allowed projection and neutral collection provenance are persisted; paths and every prohibited sentinel are absent.
4. **US4/AC4** — **Given** several runs share one Copilot conversation, **When** L1 stores their spans, **Then** conversation ID and source timestamps are retained for a later `conversation_id + span time within run window` join, while L1 assigns no span by conversation ID alone and leaves zero/multiple future matches unresolved.

### Edge Cases

- A configured agent has no tasks, is inaccessible, or has a task-history page shape without a usable continuation cursor.
- A task status is new or unknown. Unknown statuses are treated as non-terminal so collection cannot silently stop refreshing them.
- Multiple usage entries name different models, or usage is an empty list.
- A run message has no body, contains structured input instead of text, repeats a sequence, or arrives with the same timestamp as the current cursor.
- One tool input matches a command-specific rule and a generic flag rule. Only the first rule in configured priority order is recorded.
- A shell-like input cannot be tokenized. It is still hashable but is not assigned a red-line rule by substring guesswork.
- A force flag applies to a non-protected branch, a protected branch name appears only inside an unrelated argument, or `-f` is part of another token.
- A timeline backfill is truncated by the server or returns two events at the same timestamp. Truncation remains visible and overlap replay prevents gaps.
- The same pull-request URL appears in metadata and several comments. Each provenance is retained once; query strings, fragments, and non-PR URLs are not treated as distinct pull requests.
- An exact agent/workspace pair is repeated, one agent is mapped to conflicting workspaces, or several agents share one runtime. Exact pairs and runtime calls are de-duplicated; a conflicting agent mapping is a configuration error.
- An agent configuration follows `A → B → A`, or collection crashes after writing a snapshot but before advancing state. Each real transition retains a distinct ordinal/key while the retry reuses the same pending key.
- A Copilot OTel file is missing, rotates, truncates, contains a newline-terminated malformed/non-chat span, or ends mid-JSON. Missing files degrade to zero; rotation/truncation restarts the configured logical stream safely; complete rejected lines can advance; the unfinished line cannot advance the byte offset.
- Several Multica runs share one Copilot conversation. L1 preserves conversation ID and source timestamps only; it never assigns a span to a run by conversation ID alone.

## Requirements *(mandatory)*

### Functional Requirements

- **RH-L1-001**: The system MUST preserve the existing daily runner/timer, register `copilot_otel` as one additional L1 source, and limit this feature to append-only L1 raw observations; it MUST NOT add or modify L2/L3/L4/L5 schemas, metrics, queries, cards, or UI. The repository runner verifier MUST compare its parsed ordered source list directly with the ordered `config.SOURCES` list so a duplicate, omission, or reorder fails. Repository acceptance MUST NOT depend on mutating or executing an installed Hermes copy. `MERGE_SOURCES` remains unchanged and `copilot_otel.normalize()` is a tested no-op that creates no clean database.
- **RH-L1-002**: The system MUST discover runs from each explicitly configured agent using `multica agent tasks <agent>` and MUST discover a new run on an issue older than any previous issue-number watermark.
- **RH-L1-003**: The system MUST retain a stable run identity, re-read every non-terminal run until terminal, and project source-supplied created, dispatched, started, completed, status, failure, cancellation, model, and usage facts without inference. Every permitted lifecycle free-text field MUST pass the deterministic pre-write lifecycle sanitizer; cancellation actors MUST be projected as stable IDs only. The explicit terminal allowlist MUST be fixture-tested; an unknown status MUST remain refreshable.
- **RH-L1-004**: The system MUST collect execution messages incrementally by `(run_id, sequence)` and MUST make replay and cursor overlap idempotent.
- **RH-L1-005**: New message observations MUST NOT persist raw message bodies, tool inputs, or tool outputs. They MUST use full lowercase SHA-256 over canonical UTF-8 bytes and MUST record UTF-8 byte length.
- **RH-L1-006**: Before hashing a tool input, the system MUST apply the enabled ordered red-line rule list from aidata configuration using token-aware matching. It MUST persist only the first matched rule identifier or null. The initial list MUST cover `--admin`, `--no-verify`, force push (`--force`, `--force-with-lease`, or exact `-f`) to a configured protected branch, and `gh pr merge` with a configured bypass flag.
- **RH-L1-007**: The system MUST store agent model, thinking level, runtime ID, and maximum concurrency snapshots only when their canonical value changes. A per-agent monotonic transition ordinal MUST distinguish `A → B → A`; durable pending state MUST retain the complete canonical allowed snapshot projection and make write failure/crash retry reproduce the same `(agent_id, transition_ordinal, config_hash, first_observed_at)` candidate even when the live source changes before retry.
- **RH-L1-008**: The system MUST collect `multica runtime usage <runtime>` and `multica runtime activity <runtime>` for runtimes referenced by configured agents. It MUST preserve empty or missing Copilot usage exactly and MUST NOT fabricate tokens, cost, or model values.
- **RH-L1-009**: The system MUST collect `multica issue timeline <issue> --activity-only` for known issues with per-issue cursor overlap, stable event identity, and explicit truncation metadata sufficient for later status, park/abandon, and done-per-day analysis.
- **RH-L1-010**: The system MUST extract normalized GitHub pull-request URL candidates from issue metadata and comments with issue/workspace/source provenance and MUST NOT persist the surrounding content in the candidate record.
- **RH-L1-011**: The system MUST preserve existing issue, comment, GitHub PR, and normalized run consumers. Additive raw records and the explicitly replaced run-discovery behavior MUST remain idempotent across replays.
- **RH-L1-012**: All Multica access MUST be enforced by an explicit read-only command allowlist. Automated tests and CI MUST use injected canned responses/files and MUST fail if they attempt a live Multica subprocess or read a configured private OTel path.
- **RH-L1-013**: Before prepublication implementation review, one real local collection MUST report at least one persisted logical row and one privacy-safe sample for each of the eight raw families. An empty Multica runtime usage response MUST still have a persisted observation wrapper/sample. Any zero-row family blocks acceptance; evidence MUST NOT expose raw content or machine-local identifiers.
- **RH-L1-014**: `copilot_otel` MUST collect configured JSONL streams with binary byte offsets, stream generations, and partial-line safety; it MUST handle replay, rotation, and truncation idempotently and its no-op normalizer MUST create no L2 output.
- **RH-L1-015**: `copilot_otel` MUST accept only the tracked neutral source slots `fullstack` and `pr-manager` and persist only that source-slot/key provenance, chat-span timestamps, `gen_ai.conversation.id`, `gen_ai.response.model`, and the five allowed token counters. It MUST reject any other configured slot before reading or writing; it MUST drop response IDs, `github.copilot.context.*`, content attributes, whole spans, and paths; it MUST preserve but not perform the later windowed run join.

### Key Entities

- **Run Observation**: One source snapshot of an execution keyed by stable run ID, with issue/agent/runtime provenance, lifecycle timestamps, terminal details, and source-supplied usage/model facts.
- **Pending Run**: Collection state identifying a run that must be revisited because its last observed status is not in the explicit terminal allowlist.
- **Run Message Observation**: A sequence-addressed message record containing metadata plus hashes and byte lengths, never the raw body or tool payload.
- **Red-Line Match**: The single configured rule identifier that matched a transient tool input before hashing, or null when no rule matched.
- **Agent Snapshot**: Canonical change-only agent configuration at an observed time.
- **Runtime Usage Observation** and **Runtime Activity Observation**: Exact read-only CLI payloads wrapped only with provenance and collection time.
- **Issue Timeline Event**: A stable activity-only issue event with cursor and truncation provenance.
- **Issue–PR Candidate**: A normalized GitHub PR URL associated with an issue and the exact metadata/comment source that exposed it.
- **Copilot OTel Usage Observation**: One projected chat span whose derived key uses neutral source slot, stream generation, line offset, and the allowed projection without persisting the path/offset internals; it retains conversation ID, source time range, model, and source-supplied input/output/cache-read/cache-write/reasoning token counts.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A fixture with a new run on an issue below the former watermark produces one run observation, and a queued-to-completed fixture produces the final observation without duplicate logical run identities.
- **SC-002**: Secret/path sentinel tests find zero raw message, tool-input, tool-output, or unsafe lifecycle-text bytes in projected/serialized raw output and in normalized-run compatibility rows.
- **SC-003**: Every initial red-line rule has at least one positive and two near-miss fixtures, with zero substring-only false positives.
- **SC-004**: An empty Copilot run usage and empty runtime usage response remain empty after collection; no test or sample contains an invented zero-token or fallback model value.
- **SC-005**: Replaying all canned task, message, timeline, agent, runtime, PR-link, and OTel inputs changes zero existing logical identities and skips zero new transitions, sequences, events, or complete spans; `A → B → A` remains three snapshots.
- **SC-006**: A command spy observes only approved read-only Multica command prefixes, and fixture tests make zero live Multica calls.
- **SC-007**: Fixed-candidate real-local evidence reports at least one persisted row and one privacy-safe sample for each of all eight raw families while exposing no raw content or local configured identifier.
- **SC-008**: OTel fixtures prove complete lines emit exactly once across resume, an unfinished line emits only after completion, and rotation/truncation creates a safe new generation without loss or duplicate logical identities.
- **SC-009**: Serialized OTel rows contain all allowed join/token fields supplied by the fixture and zero prohibited response/context/content/path sentinel bytes; same-conversation spans across disjoint run windows remain separate and unassigned in L1.

## Assumptions

- Configured agent IDs are the authoritative discovery allowlist and are paired with workspace IDs in ignored `config_local.py`; no broad `agent list` enumeration is added.
- Agent IDs are globally resolvable by `agent tasks`/`agent get`; the configured workspace ID is retained as collection provenance because those commands do not accept a workspace flag.
- The terminal run statuses are `completed`, `failed`, and `cancelled` until a fixture-backed source status is intentionally added. Every other value is non-terminal.
- Protected branches default to `main` and `master` and can be overridden in ignored local configuration.
- Red-line matching is an observation signal, not an authorization decision, policy engine, or substitute for branch protection.
- Configured Copilot OTel streams use neutral logical source slots plus local-only file paths. The five token counters are `input_tokens`, `output_tokens`, `cache_read.input_tokens`, `cache_write.input_tokens`, and `reasoning.output_tokens`; absent counters remain absent.
- External issue closure is separate from repository delivery: only after the implementation PR merges, the lead's CLI session on the Owner's Mac may synchronize the merged runner to the installed Hermes copy, verify cadence, and post the receipt on MY-1817. That receipt gates MY-1817 closure only—not repository acceptance, implementation review, publication, or PR merge—and no squad agent or prepublication candidate may mutate the host.

## Out of Scope

- Computing health scores, durations, daily metrics, failure taxonomies, or park/abandon decisions.
- Normalized warehouse changes, analytical queries, dashboards, briefing cards, alerts, or UI.
- Mutating Multica issues, agents, runs, runtimes, comments, or configuration.
- Storing raw message bodies, tool inputs, tool outputs, credentials, local paths, email addresses, or whole `agent tasks` response objects.
- Joining Copilot spans to Multica runs, allocating shared-session tokens, normalizing OTel rows, or deriving cost; those require a later L2/L3 design that uses conversation ID and span time inside the run window.
- Backfilling evidence that the Multica server no longer exposes or claiming a complete history when the server reports truncation.
