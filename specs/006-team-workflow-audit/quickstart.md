# Quickstart: Verify the Team Workflow Audit Slice

This quickstart is for implementation verification with neutral fixtures. It
does not run a real audit, use personal evidence, or contact CloudKit.

## 1. Confirm context ownership

Resolve every changed path before editing:

```bash
scripts/context/contexts <changed-path>
```

Expected implementation leaves are RepoInfra, AidataFoundation,
AidataL1L2, AidataL3, AidataL4, AidataL5, AIDashCore, DesignKit, AIDashUI,
and AIDashApp. CLI source, project wiring, aidata scripts/cron, generated data,
and external audit sources are out of scope.

## 2. Exercise the manual boundary with fixtures

Configure the git-ignored Team Audit import directory to a neutral fixture
bundle and explicitly select the manual source:

```bash
./aidata/cli.py collect --source team_audit_snapshot
./aidata/cli.py normalize --source team_audit_snapshot
./aidata/cli.py merge
```

The default commands without `--source team_audit_snapshot` must exclude this
source. Missing configuration must report zero records without failure. No
command in this flow invokes Team Workflow Audit.

## 3. Verify layer-owned behavior

Use resolver-declared gates; do not manually run the repository's broad test
suites:

```bash
scripts/context/run AidataFoundation --mode local
scripts/context/run AidataL1L2 --mode local
scripts/context/run AidataL3 --mode local
scripts/context/run AidataL4 --mode local
scripts/context/run AidataL5 --mode local
scripts/context/run AIDashCore --mode local
scripts/context/run DesignKit --mode local
scripts/context/run AIDashUI --mode local
scripts/context/run RepoInfra --mode local
scripts/context/audit
```

Normal commit and push hooks rerun affected local gates. AIDashApp and aidash
heavy build gates are CI-only. Never run the host-based AIDashApp test target
locally; use the hostless `AIDashAppLogicTests` target only when a focused App
logic question cannot be answered by hooks.

## 4. Required neutral fixture proofs

- Baseline and incremental overview parts render different cohort/cursor
  sections and independent axes.
- Replay and overlap records deduplicate by stable identity; hash collision
  never overwrites.
- All six finding states and all locked verdicts round-trip.
- Unsafe artifact/grill URLs are text; valid HTTPS URLs are actionable.
- Acknowledgement and approval produce one append-only receipt each and leave
  the source snapshot unchanged.
- No-op UI environments, write failure, missing source, and missing artifact
  cases degrade without crash.
- Spies observe no audit invocation, cron registration, source mutation,
  issue/run mutation, agent dispatch, or remediation execution.

## 5. CI evidence

The implementation PR must obtain the repository-required CI checks, including
macOS/iOS App builds, CLI build, Core/package tests, aidata pytest + ruff, and
the repository review target. CI, not a local host-based test, is the source of
truth for assembled App/CLI build compatibility.
