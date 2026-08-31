# Requirements Checklist: Trusted Exact-HEAD Decision Evidence

**Purpose**: Validate structural redesign readiness before independent review.

**Created**: 2026-08-31

**Feature**: `specs/006-codex-gate-false-positive/spec.md`

## Outcome and authority

- [x] CHK001 Owner option B is explicit: stop wording-only repair, no merge or
  bypass of PR #205, preserve fail-closed behavior.
- [x] CHK002 PR #205 exact SHA, Multica PASS, same-SHA required-gate failure,
  Draft/no-auto-merge hold, and superseded handoff are recorded.
- [x] CHK003 PR #199 and MY-1496 remain downstream dependencies rather than
  hidden cross-layer work.

## Trust and architecture

- [x] CHK004 Trusted-base execution and exact-HEAD blob-only reads are
  explicit.
- [x] CHK005 PR-authored bytes stay below the existing untrusted-data fence.
- [x] CHK006 The entire landed enforcement chain—including detector module,
  entrypoint, invocation/propagation, Codex fence consumer, trusted-base
  workflow invocation, ruleset entry, and instruction regions—fails before
  model invocation when changed; no PR-controlled exception exists.
- [x] CHK007 The external evidence seam remains one call; Swift/Python adapters
  and git fixture/production adapters remain internal.
- [x] CHK008 Prompt helpers, Codex prompt/caller, workflow, ruleset, severity,
  schema/parser, timeouts, and product/data behavior are preserved.

## Structural evidence

- [x] CHK009 Hunk context is a seed and exact-HEAD AST use discovery supplies
  the complete out-of-hunk predicate.
- [x] CHK010 Completion is per claim: predicate structure and safe RHS domain
  can complete while dynamic subject/helper semantics remain unresolved and a
  literal fallback remains observation-only.
- [x] CHK011 The typed bundle defines schema/provenance/trust, stable ordering,
  evidence ids, diff digest, and whole-record caps.
- [x] CHK012 The PR #199 accepting fixture and genuinely rejecting mutation
  test behavior rather than vocabulary.
- [x] CHK013 PR #171 Swift behavior and existing fail-closed paths remain
  required coverage.
- [x] CHK028 The one-time T001 bootstrap evidence and the consumed-on-merge
  authority rule are explicit; every later protected change needs a new
  owner-reviewed publication contract.

## Scope and tasks

- [x] CHK014 The implementation is one atomic `RepoInfra` task with concrete
  paths and region-level exclusions.
- [x] CHK015 T001 excludes every workflow, ruleset, prompt function, timeout,
  hook, Swift/App/CLI, Aidata, and preserved PR branch outside its contract.
- [x] CHK016 Every functional requirement maps to US1/T001, B000, or an
  explicit downstream delivery edge.
- [x] CHK017 Every executable task has one owning layer, exact files,
  interface impact, acceptance, dependencies, and an exact verification
  command.
- [x] CHK018 The graph is acyclic and contains no hidden cross-layer Fullstack
  task.

## Verification and delivery

- [x] CHK019 The exact hook-driven RepoInfra local command and CI/ruff evidence
  are declared.
- [x] CHK020 B000 requires successful same-SHA `review-gate (pytest)` evidence
  on the actual implementation base and a new branch distinct from PR #205.
- [x] CHK021 Named timeout/process-group and task-freshness failures are
  stop-and-return red lines, not scope expansion.
- [x] CHK022 Exact local/remote/PR HEAD equality, all required checks, and
  fresh same-SHA AI Reviewer PASS authorize only the exact T001 bootstrap
  implementation revision.
- [x] CHK023 PR #199 refresh is ordered after the structural repair reaches
  `main`.

## Readiness

- [x] CHK024 No `NEEDS CLARIFICATION` marker remains.
- [x] CHK025 No unresolved product, content, or authority decision remains.
- [x] CHK026 Spec, plan, research, data model, contract, quickstart, tasks, and
  checklist agree on terminology, scope, trust, and verification.
- [x] CHK027 The larger trusted Codex instruction-loader design is explicitly
  deferred to a separate owner-reviewed contract.
