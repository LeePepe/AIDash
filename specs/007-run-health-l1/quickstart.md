# Quickstart: Run-Health L1 Collection

This is the implementation and acceptance guide. Only T004's authorized local acceptance run contacts Multica or configured Copilot files; automated tests and CI use fixtures.

## 1. Configure locally

In ignored `aidata/config_local.py`, configure `MULTICA_RUN_AGENTS`, protected branches/red-line rules, and two neutral `COPILOT_OTEL_STREAMS` slots for the Fullstack and PR Manager exporter files. Real IDs and paths never enter tracked files or evidence. With no configured agents/streams, collection returns zero without error.

## 2. Implement in layer order

1. T001: commit the `AidataFoundation` configuration/source-registration allowlist.
2. T002: commit the `AidataL1L2` adapters, routing metadata, and canned fixtures.
3. T003: commit only the `AidataOps` repository-runner wiring.
4. Keep all three commits in one fixed candidate/PR goal. Do not modify L2 schemas/output, `MERGE_SOURCES`, L3/L4/L5, Swift packages, or UI.

Normal commit hooks select repository gates. Do not bypass or manually repeat the full suite. The installed Hermes runner copy is an authorized post-merge operations sync, not a prepublication task.

## 3. Fixture verification

Fixtures must prove:

- Old-issue run discovery, non-terminal re-read, unknown-status pending, pagination honesty, and compatibility.
- Lifecycle sanitizer ordering across `failure_reason`, `trigger_summary`, and `error`, with raw and normalized sentinel absence.
- Message overlap/replay, canonical hashes/lengths, every red-line positive/near miss, and zero raw content.
- Agent snapshot `A → B → A`, unchanged replay, write failure, and `pending B → crash → live C` retry reproduce B's exact key/time/values before C.
- Empty Multica run/runtime usage stays empty inside a persisted observation wrapper.
- Timeline overlap/truncation markers and PR-link provenance/privacy.
- OTel complete-line emission, partial-tail deferral/completion, offset resume, rotation/truncation generation, malformed/non-chat handling, write failure, and logical replay.
- OTel accepts only tracked `fullstack`/`pr-manager` slots, retains timestamps, conversation ID, model, and five token counters; unknown/duplicate slots fail before file access and response/context/content/path/label sentinels never serialize.
- Same-conversation spans across disjoint/overlapping run windows remain separate and unassigned; L1 performs no join.
- `copilot_otel.normalize() -> 0` creates no clean DB, the source is not mergeable, and runner registry equality holds.
- Automated tests launch no live Multica subprocess and read no private configured stream.

## 4. One real local acceptance run

After T001–T003 local commits and commit-hook success, run the supported collect entry points for `multica_issue`, `multica_comment`, `multica_run`, and `copilot_otel` once with authorized local configuration.

Every family below must have at least one persisted logical row and exactly one sanitized sample. Zero rows block RH-L1-013; do not invent a sample.

| Raw family | Required evidence |
|---|---|
| `multica_run` | positive logical row count; one sample with IDs replaced and sanitized lifecycle fields |
| `multica_run_message` | positive count; sequence, hashes, lengths, and rule name/null without content |
| `multica_agent_snapshot` | positive count; snapshot key/ordinal with IDs replaced |
| `multica_runtime_usage` | positive wrapper count; one sample preserving truthful empty usage when observed |
| `multica_runtime_activity` | positive count; runtime ID replaced |
| `multica_issue_timeline` | positive count; action/truncation with IDs replaced |
| `multica_issue_pr_link` | positive count; issue/source IDs replaced and only a safe normalized public PR URL |
| `copilot_otel` | positive count; key/slot replaced as needed, allowed timestamps/conversation/model/token fields only |

Evidence must exclude body/input/output, unsafe lifecycle source text, OTel prohibited fields, email, private metadata, local path, CLI stderr, and configured IDs/slots.

## 5. Review before publication

Freeze the local candidate HEAD/tree after the real evidence run. The AI Reviewer prepublication package includes:

- exact local SHA and three-commit/changed-path manifest;
- commit-hook evidence and fixture coverage;
- privacy assertions and the eight-family table;
- confirmation that ignored config and downstream/merge files are absent.

Do not push or create/update the PR before explicit PASS/publication permission. A changed tracked byte or SHA invalidates the review and requires another prepublication pass.

## 6. Publish and prove identity

After PASS, run the normal pre-push hook, push only the reviewed SHA, and create/update the non-Draft PR. Then verify local HEAD, remote branch SHA, and PR `headRefOid` byte-for-byte. This equality proof is post-publication evidence.

## Failure handling

- Unknown CLI/page shapes, unknown/duplicate OTel slots, zero-row families, or missing required OTel fields block completeness claims.
- Empty Multica usage is a successful empty payload only when its wrapper row persists.
- Timeline truncation remains successful partial evidence, never full history.
- OTel incomplete tails wait; malformed complete lines may advance; path/content must never be logged as evidence.
- Any need for normalized schema, attribution, cost, queries, metrics, UI, or a new timer returns to Team Lead as separate scope.
