# Quickstart: Verify the Hidden Core Residual Slice

This quickstart is for the later Fullstack implementation after an exact
planning PASS and Team Lead handoff. It does not authorize implementation from
the Planner run.

## 1. Confirm the immutable base

Use the exact planning commit named by the PASS verdict, or an approved
descendant whose reviewed planning blobs are byte-identical. Confirm the task
branch starts there and the initial worktree is clean.

The review-machinery item named in the handoff is a later merge dependency
only. It does not add an implementation path or authorize a broader base diff.

## 2. Read the owning context

Resolve both allowed paths through the repository context tools. Both must
resolve to the AIDashCore leaf:

```text
CONTEXT.md
  → Packages/CONTEXT.md
    → Packages/AIDashCore/CONTEXT.md
```

Read `Packages/AIDashCore/tech-context.md`. Do not modify context or routing.

## 3. Keep the exact two-path boundary

Allowed:

```text
Packages/AIDashCore/Sources/AIDashCore/Models/Payloads/TeamAuditPayload.swift
Packages/AIDashCore/Tests/AIDashCoreTests/TeamAuditPayloadInvariantTests.swift
```

If any other path appears necessary, stop and return to Team Lead. Do not add
`CardType.teamAudit`, change the count tripwire, edit Validation, or touch a
consumer layer.

## 4. Use neutral matrix fixtures

Use invented identities such as `case-atlas-001`, deterministic 64-character
lowercase hashes, and `https://example.com/audit/full-report.json` raw URLs.
Cover every row in `contracts/core-residual-matrix.md`:

- nil/valid/blank/dangling case bindings and duplicate catalog identities;
- positive overview and artifact-section report resolution;
- independent kind, ID, hash, URL, sidecar ID, and sidecar hash mutations;
- resolved-versus-externalized report mutations;
- positive, zero, and negative encoded byte counts;
- fixed reason, eight exact optional-only kinds, unknown decoding, and absence
  of mandatory kinds.

## 5. Let hooks verify the package

Commit and push normally with `core.hooksPath=scripts/hooks`. The hooks resolve
the two changed paths and run the AIDashCore SwiftPM build/test gates. Do not
manually repeat the suite and do not run `xcodebuild`; this is a Packages-only
change.

After hook success, confirm the implementation diff is exactly the two paths
and that local HEAD, pushed branch SHA, and PR head SHA are identical before
implementation review.

## 6. Completion evidence

The handoff records the approved planning base, exact implementation SHA,
two-path diff, hook result, CR-001–CR-022 proof mapping, unchanged ten-card
registration, and absence of removed/weakened tests.
