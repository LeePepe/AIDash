# Quickstart: Run-Health L1 Collection

This is the implementation and repository-acceptance guide. Within repository implementation and acceptance, only T004's single authorized prepublication `cli.py collect` run contacts Multica or configured Copilot files; automated tests and CI use fixtures.

## 1. Configure locally

In ignored `aidata/config_local.py`, configure `MULTICA_RUN_AGENTS`, protected branches/red-line rules, and two neutral `COPILOT_OTEL_STREAMS` slots for the Fullstack and PR Manager exporter files. Real IDs and paths never enter tracked files or evidence. With no configured agents/streams, collection returns zero without error.

## 2. Implement in layer order

1. T001: commit the `AidataFoundation` configuration/source-registration allowlist.
2. T002: commit the `AidataL1L2` adapters, routing metadata, and canned fixtures.
3. T003: commit the `AidataOps` repository-runner wiring and its ordered-list registry verifier.
4. Keep all three commits in one fixed candidate/PR goal. Do not modify L2 schemas/output, `MERGE_SOURCES`, L3/L4/L5, Swift packages, or UI.

Normal commit hooks select repository gates. Do not bypass or manually repeat the full suite. Installed-Hermes synchronization and scheduled-run proof are outside repository acceptance, implementation review, publication, and PR merge; no prepublication or squad-agent step mutates the host.

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
- `copilot_otel.normalize() -> 0` creates no clean DB, the source is not mergeable, and the runner parser's ordered list equals `list(config.SOURCES)` directly so omissions, duplicates, and reordering fail.
- Automated tests launch no live Multica subprocess and read no private configured stream.

## 4. One real local acceptance run

After T001–T003 local commits and commit-hook success, execute exactly one manual `python3 aidata/cli.py collect` invocation with no `--source` filter and with authorized local configuration. Do not replace this with separate per-source invocations.

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

## 7. External post-merge issue closure (not repository acceptance)

This section is not a task, repository gate, implementation-review condition, publication condition, or PR merge condition. Only after the implementation PR merges, the Owner-authorized lead CLI session on the Owner's Mac may synchronize `aidata/scripts/aidata_digest_run.sh` from the merged revision to `~/.hermes/scripts/aidata_digest_run.sh`, verify cadence, and post the privacy-safe receipt on MY-1817. That receipt gates MY-1817 closure only. No squad agent performs or delegates the host mutation, and the installed copy is never changed from a prepublication candidate or unmerged PR head.

## Failure handling

- Unknown CLI/page shapes, unknown/duplicate OTel slots, zero-row families, or missing required OTel fields block completeness claims.
- Empty Multica usage is a successful empty payload only when its wrapper row persists.
- Timeline truncation remains successful partial evidence, never full history.
- OTel incomplete tails wait; malformed complete lines may advance; path/content must never be logged as evidence.
- A missing or failed external cadence receipt blocks MY-1817 closure only; it does not invalidate repository acceptance or block implementation review, publication, or PR merge. Do not let a squad agent repair the host.
- Any need for normalized schema, attribution, cost, queries, metrics, UI, or a new timer returns to Team Lead as separate scope.
