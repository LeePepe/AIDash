# Feature Specification: Dev Team Run-Health L0 Collection

**Feature Branch**: `007-run-health-l0`

**Created**: 2026-10-15

**Status**: Draft

**Input**: Collect privacy-safe raw evidence for later Dev Team run-health analysis without implementing analysis, metrics, or UI.

## Existing behavior

- The scheduled `multica_issue`, `multica_run`, and `multica_comment` sources collect through the existing aidata pipeline.
- `multica_run` discovers executions by walking known issues and advances a highest-issue-number watermark. A later execution on an older issue is never discovered, and an execution observed before completion is never refreshed.
- Existing issue, comment, GitHub PR, and normalized run consumers are accepted behavior and must continue to work.
- The repository calls its external append-only raw collection boundary L1 in the physical `L1_collect/raw` layout. This feature's issue-level term “L0” means that same raw observation boundary; it does not rename repository layers or authorize normalized schemas, metrics, queries, cards, or UI.

## Compatibility

- Existing scheduled source names and their cron registration remain unchanged.
- Existing `multica_issue`, `multica_comment`, `github_pr`, and `multica_run` normalized contracts remain compatible. New evidence is additive raw data.
- Repeated collection is idempotent by stable source identity. Missing source values remain missing; an absent or empty usage payload never becomes a zero-token observation.
- No existing test is removed, skipped, or weakened to deliver this feature.

## Removed behavior

- Issue-number-only run discovery and its “collect once, never revisit” lifecycle behavior are removed. The 2026-10-15 lead decision explicitly replaces them with per-agent discovery and non-terminal re-reads.
- No other accepted behavior is removed.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Observe complete execution lifecycles (Priority: P1)

As a later run-health analyst, I can rely on raw execution observations that include newly created runs even when their issue is old and that eventually show how every initially non-terminal run ended.

**Why this priority**: Complete run discovery and lifecycle closure are the minimum trustworthy foundation for any later health analysis.

**Independent Test**: Replay fixtures in which an old issue receives a new run and a run changes from queued or running to a terminal state. Collection stores both observations under one stable run identity, retains queue/failure/cancel facts supplied by the source, and creates no duplicate logical run.

**Acceptance Scenarios**:

1. **US1/AC1** — **Given** an issue whose number is below the former run watermark, **When** a configured agent starts a new run on that issue, **Then** the run is discovered from that agent's task history and persisted.
2. **US1/AC2** — **Given** a run first observed in a non-terminal state, **When** later scheduled collections run, **Then** the run is re-read until a terminal observation supplies its final timestamps and available failure or cancellation facts.
3. **US1/AC3** — **Given** queue, dispatch, start, completion, status, `failure_reason`, `cancelled_by`, usage, or model facts are absent in the source response, **When** the observation is stored, **Then** each absent fact remains absent rather than being inferred from agent configuration or replaced with zero.
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

1. **US3/AC1** — **Given** a configured agent's model, thinking level, runtime ID, or maximum concurrency changes, **When** collection compares its canonical snapshot, **Then** one new snapshot is stored; an unchanged snapshot stores nothing.
2. **US3/AC2** — **Given** a runtime referenced by a configured agent, **When** usage and hourly activity are collected, **Then** the exact source observations are stored once per observation identity, including a truthful empty usage response.
3. **US3/AC3** — **Given** a known issue has status changes, task outcomes, or other activity records, **When** its activity-only timeline is collected incrementally, **Then** each event is persisted idempotently with issue provenance and server truncation is explicitly marked.
4. **US3/AC4** — **Given** issue metadata or a comment contains a valid GitHub pull-request URL, **When** candidate extraction runs transiently, **Then** the normalized URL, issue identity, source kind, source record identity, and observation time are persisted without the surrounding body or metadata.
5. **US3/AC5** — **Given** the existing daily schedule invokes the three Multica sources, **When** collection runs, **Then** all new raw families are produced without registering another scheduled source or changing a downstream layer.

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

## Requirements *(mandatory)*

### Functional Requirements

- **RH-L0-001**: The system MUST preserve the existing collection schedule and MUST limit this feature to append-only raw observations; it MUST NOT add or modify L2/L3/L4/L5 schemas, metrics, queries, cards, or UI.
- **RH-L0-002**: The system MUST discover runs from each explicitly configured agent using `multica agent tasks <agent>` and MUST discover a new run on an issue older than any previous issue-number watermark.
- **RH-L0-003**: The system MUST retain a stable run identity, re-read every non-terminal run until terminal, and project source-supplied created, dispatched, started, completed, status, failure, cancellation, model, and usage facts without inference. The explicit terminal allowlist MUST be fixture-tested; an unknown status MUST remain refreshable.
- **RH-L0-004**: The system MUST collect execution messages incrementally by `(run_id, sequence)` and MUST make replay and cursor overlap idempotent.
- **RH-L0-005**: New message observations MUST NOT persist raw message bodies, tool inputs, or tool outputs. They MUST use full lowercase SHA-256 over canonical UTF-8 bytes and MUST record UTF-8 byte length.
- **RH-L0-006**: Before hashing a tool input, the system MUST apply the enabled ordered red-line rule list from aidata configuration using token-aware matching. It MUST persist only the first matched rule identifier or null. The initial list MUST cover `--admin`, `--no-verify`, force push (`--force`, `--force-with-lease`, or exact `-f`) to a configured protected branch, and `gh pr merge` with a configured bypass flag.
- **RH-L0-007**: The system MUST store agent model, thinking level, runtime ID, and maximum concurrency snapshots only when their canonical value changes, with agent/workspace identity and observation time.
- **RH-L0-008**: The system MUST collect `multica runtime usage <runtime>` and `multica runtime activity <runtime>` for runtimes referenced by configured agents. It MUST preserve empty or missing Copilot usage exactly and MUST NOT fabricate tokens, cost, or model values.
- **RH-L0-009**: The system MUST collect `multica issue timeline <issue> --activity-only` for known issues with per-issue cursor overlap, stable event identity, and explicit truncation metadata sufficient for later status, park/abandon, and done-per-day analysis.
- **RH-L0-010**: The system MUST extract normalized GitHub pull-request URL candidates from issue metadata and comments with issue/workspace/source provenance and MUST NOT persist the surrounding content in the candidate record.
- **RH-L0-011**: The system MUST preserve existing issue, comment, GitHub PR, and normalized run consumers. Additive raw records and the explicitly replaced run-discovery behavior MUST remain idempotent across replays.
- **RH-L0-012**: All Multica access MUST be enforced by an explicit read-only command allowlist. Automated tests and CI MUST use injected canned responses and MUST fail if they attempt a live Multica subprocess.
- **RH-L0-013**: Before handoff, one real local collection MUST report the row count and one privacy-safe sample for each resulting raw family. Evidence MUST show hashes and rule names where available but MUST NOT expose raw message/tool content or machine-local identifiers.

### Key Entities

- **Run Observation**: One source snapshot of an execution keyed by stable run ID, with issue/agent/runtime provenance, lifecycle timestamps, terminal details, and source-supplied usage/model facts.
- **Pending Run**: Collection state identifying a run that must be revisited because its last observed status is not in the explicit terminal allowlist.
- **Run Message Observation**: A sequence-addressed message record containing metadata plus hashes and byte lengths, never the raw body or tool payload.
- **Red-Line Match**: The single configured rule identifier that matched a transient tool input before hashing, or null when no rule matched.
- **Agent Snapshot**: Canonical change-only agent configuration at an observed time.
- **Runtime Usage Observation** and **Runtime Activity Observation**: Exact read-only CLI payloads wrapped only with provenance and collection time.
- **Issue Timeline Event**: A stable activity-only issue event with cursor and truncation provenance.
- **Issue–PR Candidate**: A normalized GitHub PR URL associated with an issue and the exact metadata/comment source that exposed it.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A fixture with a new run on an issue below the former watermark produces one run observation, and a queued-to-completed fixture produces the final observation without duplicate logical run identities.
- **SC-002**: Secret-sentinel tests find zero raw message, tool-input, or tool-output sentinel bytes in every newly serialized raw family.
- **SC-003**: Every initial red-line rule has at least one positive and two near-miss fixtures, with zero substring-only false positives.
- **SC-004**: An empty Copilot run usage and empty runtime usage response remain empty after collection; no test or sample contains an invented zero-token or fallback model value.
- **SC-005**: Replaying all canned task, message, timeline, agent, runtime, and PR-link responses changes zero stable record identities and skips zero new sequences or status events.
- **SC-006**: A command spy observes only approved read-only Multica command prefixes, and fixture tests make zero live Multica calls.
- **SC-007**: Real local evidence reports a non-secret row count and sample for each produced raw family while exposing no raw content or local configured identifier.

## Assumptions

- Configured agent IDs are the authoritative discovery allowlist and are paired with workspace IDs in ignored `config_local.py`; no broad `agent list` enumeration is added.
- Agent IDs are globally resolvable by `agent tasks`/`agent get`; the configured workspace ID is retained as collection provenance because those commands do not accept a workspace flag.
- The terminal run statuses are `completed`, `failed`, and `cancelled` until a fixture-backed source status is intentionally added. Every other value is non-terminal.
- Protected branches default to `main` and `master` and can be overridden in ignored local configuration.
- Red-line matching is an observation signal, not an authorization decision, policy engine, or substitute for branch protection.

## Out of Scope

- Computing health scores, durations, daily metrics, failure taxonomies, or park/abandon decisions.
- Normalized warehouse changes, analytical queries, dashboards, briefing cards, alerts, or UI.
- Mutating Multica issues, agents, runs, runtimes, comments, or configuration.
- Storing raw message bodies, tool inputs, tool outputs, credentials, local paths, email addresses, or whole `agent tasks` response objects.
- Backfilling evidence that the Multica server no longer exposes or claiming a complete history when the server reports truncation.
