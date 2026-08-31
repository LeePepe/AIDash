# Implementation Plan: Trusted Exact-HEAD Decision Evidence

**Feature**: `006-codex-gate-false-positive` | **Date**: 2026-08-31 |
**Spec**: `specs/006-codex-gate-false-positive/spec.md`

**Input**: Owner decision option B: stop PR #205 and all wording-only retries,
preserve fail-closed behavior, structurally supply the complete predicate from
trusted-base code, and prevent PR-controlled edits from changing active
reviewer instructions.

## Summary

Deepen the existing `scripts/ci/review_context.py` module behind its current
base-owned evidence-building seam. The shell helper will forward every changed
path; the module will keep the existing Swift receiver adapter and add a
  private Python AST adapter that emits claim-scoped same-file decision context
  from exact-HEAD blobs without checking out or executing PR code.

The same trusted preflight will protect its own complete enforcement chain as
well as instruction-producing regions and fail before model invocation. T001
is the one owner-reviewed bootstrap that publishes this chain; after it lands,
any later protected change requires a new reviewed publication contract. The
live prompt text, Codex caller, workflow, ruleset, severity, schema, and timeout
behavior remain unchanged. PR #205 stays Draft with auto-merge disabled as
incident evidence.

## Technical Context

**Language/Version**: Python 3 standard library (`ast`, `hashlib`, `json`,
`pathlib`, `subprocess`); Bash 3.2-compatible shell only for the existing
caller

**Primary Dependencies**: Existing `review_context.py`, `swift_scope.py`,
`review-common.sh`, Python standard library, pytest; no new dependency

**Storage**: No persisted product data; one transient evidence bundle per gate
run

**Testing**: Module-interface pytest fixtures plus the existing shell
integration suite; normal hooks invoke the resolver-declared RepoInfra gate;
CI additionally runs RepoInfra in CI mode and ruff

**Target Platform**: GitHub Actions `pull_request_target` on the trusted base,
using the `aidash-mac` self-hosted runner

**Project Type**: Repository automation / required merge gate

**Performance Goals**: One parse of the full diff; one bounded `git show` blob
read per eligible file; deterministic bounded traversal; no additional model
call

**Constraints**: Fail closed on operational or protected-surface failure; no
PR-head checkout/import/eval/execution; no admin bypass; no prompt/workflow/
ruleset/model/verdict change; PR #205 and PR #199 remain untouched; known
timeout/process-group and task-freshness failures remain outside T001

**Scale/Scope**: One deep RepoInfra evidence module, one shared shell-call
region, two existing regression modules, one operator document, one
implementation task

## Constitution Check

### Before Phase 0 research

- **Scope Discipline**: PASS. Every implementation path resolves uniquely to
  `RepoInfra` through `CONTEXT.md` → `scripts/CONTEXT.md`. T001 has a
  five-file allowlist plus region-level exclusions inside shared files.
- **Testing / hook ownership**: PASS with B000. Team Lead previously proved
  `review-gate (pytest)` green on exact base
  `8716846ac42b48bfd89b9a09d5dd05fc4819025d` in Actions run
  `33350742892`, job `99363478423`. Dispatch must refresh this evidence if the
  implementation base changes.
- **Identity hygiene**: PASS. Fixtures use repository-public incident tokens
  and neutral values; no account, employer, workspace, or machine identity is
  introduced.
- **Dependency direction**: PASS. RepoInfra declares no dependencies. Python
  AST/diff logic is in-process; git blob access is the existing
  local-substitutable internal seam.
- **Security / fail-closed posture**: PASS. Trusted-base execution, the
  untrusted-data fence, required status, severity, and all current tool-error
  paths are preserved. Protected enforcement-chain edits add an earlier
  non-zero preflight after bootstrap.

### After Phase 1 design

- **Interface depth**: PASS. Callers retain one evidence-building interface;
  adapter selection, diff mapping, blob reads, AST traversal, dependency
  closure, caps, canonical rendering, and protected-surface detection remain
  behind it.
- **Adapter discipline**: PASS. The existing Swift receiver analyzer and new
  Python predicate analyzer are private in-process adapters. Git blob access
  has production `git show` and fixture-map test adapters; no new external
  port is exposed.
- **Regression coverage**: PASS. Tests compare claim-scoped structural results
  for the accepting and rejecting predicate variants, prove that dynamic
  helper semantics remain unresolved, exercise every protected enforcement
  link, preserve PR #171 Swift behavior, and exercise live shell
  forwarding/failure.
- **Cross-layer behavior**: PASS. The downstream AidataL4 PR is a delivery
  dependency only. No cross-layer implementation task is created.
- **Durable context**: PASS without `CONTEXT.md` or ADR changes. Layer
  ownership and dependency direction do not change; the feature contract
  records the new internal module behavior.
- **No constitutional exception**: PASS. Complexity Tracking is not required.

## Design

### Existing trusted control path

```text
.github/workflows/codex-review-target.yml (trusted base)
  -> scripts/ci/codex-review.sh (trusted base)
       -> build_scope_evidence() in scripts/ci/review-common.sh
            -> scripts/ci/review_context.py
                 -> exact-HEAD blobs through git show (untrusted data)
       -> trusted prompt rules
       -> PR diff + generated evidence inside untrusted-data fence
       -> fail-closed structured verdict
```

The workflow checkout is already the correct trusted execution source. The
defect is inside the evidence shape and the bootstrap path:

1. `review_context.py` currently selects only Swift and supplies no Python
   decision context.
2. PR #199 therefore exposed `VALID_TIERS = {"explore"}` in hunk context
   without the out-of-hunk union that also admits `production`.
3. Planning revision `8240167` tried to repair the result by editing trusted
   prompt wording.
4. During PR #205's own review, those proposed instructions are PR-controlled
   diff data. Its exact-SHA Multica PASS cannot make them active trusted
   policy, and `codex-review-target` correctly remains fail closed.

### Selected deep module and seam

The external seam remains the existing base-owned evidence invocation:

```text
build_scope_evidence <head_sha> <full_diff_file> <changed_paths>
```

The Python CLI remains:

```text
review_context.py --head-sha <sha> --diff-file <path>
                  --changed-file <path>...
                  --max-file-bytes <n>
                  --max-excerpt-bytes <n>
                  --max-total-bytes <n>
```

Conceptually, the module implements:

```text
build_review_evidence(EvidenceRequest, BlobReader) -> EvidenceBundle
```

`EvidenceRequest` contains the exact HEAD, full diff text, changed paths, and
caps. `EvidenceBundle` contains versioned facts, exact provenance, explicit
omissions, and a diff digest. These conceptual types remain internal; callers
do not learn language adapters or evaluator details.

The module order is:

1. Validate request, exact SHA, diff file, changed paths, and caps.
2. Parse the unified diff once into base/head hunk coordinates, including
   context lines.
3. Run the protected-enforcement preflight before any model call.
4. Read eligible exact-HEAD blobs through `git show HEAD:path` without
   checkout or execution.
5. Dispatch internally to the existing Swift receiver adapter or the new
   Python predicate adapter.
6. Close bounded same-file dependencies, validate typed facts, sort/dedupe,
   apply whole-record caps, and render canonical evidence.
7. Return zero only for a schema-valid bundle; the existing shell caller puts
   it below the untrusted-data fence.

### Python decision-context adapter

The adapter is intentionally conservative:

1. Inspect all HEAD-side lines represented in changed hunks, including context
   lines, and identify module-level bindings used as decision inputs.
2. Parse the exact-HEAD Python blob with `ast`.
3. Find membership/non-membership or related comparison uses of those bindings
   anywhere in the same file.
4. Capture the complete enclosing decision expression and material same-file
   constant/helper definitions as independently scoped claims/observations.
5. Evaluate only a safe static subset: literal collections, names bound to
   them, set union, boolean operators, negation, comparisons, and literal
   defaults/fallbacks.
6. Record completion per claim. The predicate AST structure and safely
   evaluated RHS domain may be `complete`; dynamic imports, calls,
   reflection, cross-file state, cycles, or other unsupported semantics make
   only the affected subject/helper claim `unresolved`.

The PR #199 target record is structurally equivalent to:

```json
{
  "schema_version": 1,
  "kind": "python_validation_predicate",
  "path": "aidata/tests/test_query_tiers.py",
  "anchor": {"symbol": "VALID_TIERS", "line": 37},
  "predicate": {
    "start_line": 81,
    "operator": "not_in",
    "source": "_tier_of(name) not in VALID_TIERS | {\"production\"}"
  },
  "claims": [
    {
      "claim": "predicate_structure",
      "status": "complete",
      "operator": "not_in"
    },
    {
      "claim": "allowed_domain",
      "status": "complete",
      "values": ["explore", "production"]
    },
    {
      "claim": "subject_helper_semantics",
      "status": "unresolved",
      "reason": "dynamic_calls:TIER_DIRECTIVE.search,match.group"
    }
  ],
  "observations": [
    {
      "kind": "literal_fallback",
      "symbol": "_tier_of",
      "value": "production",
      "runtime_selection": "unresolved"
    }
  ],
  "derivation": "trusted_base_python_ast",
  "content_trust": "untrusted_pr"
}
```

The trusted facts are the path/span relationships, AST structure, per-claim
completion, observations, and canonical ordering. The safe RHS proof admits
`production` without claiming that the dynamic regex/group helper is fully
understood. Quoted source strings remain untrusted PR content and never move
above the fence.

### Self-protecting enforcement preflight

After T001 lands, the base-owned analyzer protects the complete path that makes
the preflight unavoidable:

| Protected surface | Protection scope |
|---|---|
| `scripts/ci/review_context.py` | Entire file: protected-surface manifest, detector, diff/blob dependencies, CLI entrypoint, validation, and exit behavior |
| `scripts/ci/review-common.sh` | Entire file: evidence invocation/propagation, reviewer instructions, and shared failure utilities |
| `scripts/ci/codex-review.sh` | Entire file: helper source, evidence/failure path, prompt/fences, model invocation, verdict enforcement, and all control flow |
| `.github/workflows/codex-review-target.yml` | Entire file: event/job conditions, trusted-base checkout, permissions, and gate invocation |
| `scripts/rulesets/main-protection.json` | Entire file: required-status identity and merge policy |

The trusted implementation compares each protected base/head blob identity,
rejects any protected path change before the model, and validates that all
five protected files exist as regular tracked blobs. Whole-file protection
also closes early-exit, alternate-source, trigger/condition, and ruleset
bypasses outside a narrower region map. A changed, missing, replaced, or
ambiguous protected file returns `protected_enforcement_change` non-zero.
The preflight reads no allowlist, exemption, attestation, or expected hash from
the PR head.

Protecting the five entire enforcement files avoids a shallow region manifest
that could be bypassed through an unlisted helper, early return, workflow
condition, or ruleset change. It intentionally freezes their later maintenance
behind a separate reviewed publication contract.

#### One-time bootstrap publication

T001 is the single owner-reviewed bootstrap from a base that lacks this
preflight. Its implementation PR may add the detector and change only the
reviewed evidence-call region because:

1. this exact planning revision authorizes the bootstrap surface;
2. B000 pins a green exact base and a new branch distinct from PR #205;
3. local/remote/PR OIDs must match the exact implementation SHA;
4. all required CI checks and a fresh exact-SHA Multica AI Reviewer PASS are
   mandatory; and
5. PR Manager may merge only that exact reviewed bootstrap revision.

Once T001 is on `main`, no later protected change is authorized by T001.
Every such change requires a new owner decision and separately reviewed
trusted-base publication/loading contract; no PR-controlled bypass exists.

### Error contract

| Condition | Result |
|---|---|
| Usage, invalid SHA/path/cap, or unreadable diff request | non-zero; no model |
| Protected enforcement file blob changed, missing, replaced, or ambiguous | `protected_enforcement_change`; non-zero; no model |
| Required non-deleted exact-HEAD blob unreadable | non-zero; no model |
| Selected changed Python source has a syntax error | non-zero; no model |
| Adapter exception, invalid fact schema, serialization failure | non-zero; no model |
| Legitimate deletion | explicit omission; bundle may succeed |
| Unsupported/dynamic/cyclic semantic form | explicit `unresolved`; no guessed conclusion |
| Per-file/excerpt/total cap | omit whole fact, append explicit omission; never silently slice a record |
| No supported evidence pattern | valid empty bundle |

All existing downstream fetch, model, timeout, parse, verdict-schema, and
pass/blocker-consistency failures remain unchanged and non-zero.

## Design It Twice Comparison

### Design A — Minimal deep evidence module

Keep the shell/CLI seam and deepen `review_context.py` with exact-HEAD Python
predicate facts. This maximizes leverage per entry point and concentrates
semantic evidence in one locality. By itself, it does not deterministically
stop future edits to prompt-producing regions.

### Design B — Extensible typed evidence adapters

Introduce a versioned bundle and private adapter registry for Swift and Python.
This supports future repeated evidence classes without gate-specific caller
changes. A public plugin interface would be shallow and unsafe, so the selected
design keeps the registry and adapters private.

### Design C — Separate trusted Codex instruction loader

Move reviewer policy into a base-owned instruction directory discovered by a
new gate runner and transport all PR data separately through stdin. This gives
the strongest instruction/data separation, but changes `codex-review.sh`,
Codex invocation semantics, schema/result orchestration, and the external CLI
dependency. It is a larger independently valuable migration, not necessary to
supply the missing PR #199 predicate.

### Recommendation

Use a hybrid of A and B plus the self-protecting enforcement preflight:

- one unchanged caller seam;
- typed evidence behind private adapters;
- deterministic rejection of every enforcement-chain edit after the
  owner-reviewed bootstrap, before the model; and
- no prompt, workflow, ruleset, or model-invocation change.

This has the best depth and locality for the proven incident while keeping the
larger trusted-loader migration available as a separate future contract.

## Project Structure

### Documentation (this feature)

```text
specs/006-codex-gate-false-positive/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── review-evidence-discipline.md
├── checklists/
│   └── requirements.md
└── tasks.md
```

### Authorized implementation revision

```text
scripts/ci/review_context.py
scripts/ci/review-common.sh
scripts/ci/tests/test_review_context.py
scripts/ci/tests/test_review_shell.py
docs/ci-gates.md
```

**Structure Decision**: No new public module, directory, dependency, workflow,
or route. `review_context.py` becomes the deep evidence module. The existing
Swift analyzer remains an internal implementation dependency; Python AST logic
is colocated and private.

## Vertical Slice and Layer Graph

| Slice | Outcome | Layer task | Upstream dependency |
|---|---|---|---|
| US1 | Required reviewer receives claim-scoped exact-HEAD predicate evidence, while any protected enforcement-file edit stops before model invocation | T001 · RepoInfra | Exact planning PASS + B000 exact-base green baseline |

T001 is one atomic RepoInfra implementation task because the module behavior,
shared-call forwarding, interface regression, shell integration, and operator
contract must agree in one revision. PR #199 refresh remains a downstream
delivery dependency, not a hidden Aidata task.

## Pre-Dispatch Readiness Gate B000

B000 is Team Lead-owned scheduling evidence, not a Fullstack checkbox:

1. Pin T001's actual `delivery_base_sha` to then-current `main`.
2. Verify that exact commit has a successful GitHub
   `review-gate (pytest)` check.
3. Prepare a new clean RepoInfra delivery branch/worktree; do not reuse
   PR #205 or its branch.
4. If the check is missing/failing, keep T001 blocked and obtain a separate
   RepoInfra prerequisite plan.

The earlier proof for `8716846ac42b48bfd89b9a09d5dd05fc4819025d` is Actions
run `33350742892`, job `99363478423`. It remains usable only if that exact SHA
is the implementation base.

## Delivery Dependency Sequence

1. AI Reviewer passes this exact structural planning revision.
2. Team Lead establishes B000 on the actual current-main base and prepares a
   new delivery branch. PR #205 stays Draft/no-auto-merge and unchanged.
3. Fullstack implements only T001's one-time bootstrap allowlist and
   reviewed file/region contract; this planning authority expires for protected
   changes after the bootstrap reaches `main`.
4. Normal hooks run the RepoInfra local gate. Any named timeout/process-group
   failure or task-freshness hang stops the task without expanding scope.
5. The new repair PR proves local HEAD = remote branch OID = PR `headRefOid`,
   receives all required checks green, and receives exact-SHA Multica AI
   Reviewer PASS.
6. PR Manager merges the structural repair to `main` without bypass.
7. Team Lead refreshes PR #199 from repaired `main` while preserving its
   existing AidataL4 allowlist.
8. PR #199's new exact HEAD receives all checks green and a fresh Multica AI
   Reviewer PASS before PR Manager merge.
9. MY-1496 remains blocked until MY-1495 is proven on `main`.

## Risks and Controls

| Risk | Control |
|---|---|
| Candidate prompt wording self-authorizes | The landed base protects instructions plus the full enforcement chain; T001 does not edit prompt text |
| Guard later edits its own blind spot | All five enforcement files are protected by base/head blob identity; later change needs a new publication contract |
| AST output overclaims arbitrary Python semantics | Completion is per claim; the safe RHS domain may complete while dynamic subject/helper semantics remain `unresolved` |
| PR source escapes the trust fence | Trusted renderer owns labels; source is tagged `untrusted_pr` and shell placement is regression-tested |
| Analyzer silently loses context | Exact-head reads, typed facts, stable spans/digest, whole-record caps, explicit omissions |
| New language evidence spreads through callers | Shell forwards all paths; adapter selection stays private inside the deep module |
| Existing Swift repair regresses | PR #171 interface fixture remains in the required regression set |
| Gate fails open on tool error | Pre-model non-zero on operational/schema/protected-file failure; existing downstream failures unchanged |
| PR #205 is accidentally shipped or reused | Explicit hold/non-reuse contract and separate delivery branch requirement |
| Known baseline flake is absorbed into T001 | B000 and stop-and-return red lines preserve separate planning ownership |

## Complexity Tracking

No constitution violation or complexity exception is required.
