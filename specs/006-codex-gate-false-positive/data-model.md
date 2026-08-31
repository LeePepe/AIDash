# Data Model: Trusted Exact-HEAD Decision Evidence

This feature introduces no persisted application, warehouse, or configuration
data and requires no migration.

The internal evidence module uses transient typed concepts for one required
review run.

## Exact-base type gap

Exact base `8716846` defines only the Swift-oriented `FileEvidence`
tuple and renders free-form receiver text. It has no `EvidenceRequest`,
`EvidenceBundle`, `ClaimCompletion`, Python predicate fact, stable evidence
id/diff digest, or `ProtectedEnforcementChange`. The types below are mandatory
new implementation, not names for existing base structures.

## EvidenceRequest

| Field | Type | Contract |
|---|---|---|
| `head_sha` | 40-character commit id | Exact PR head already fetched and verified by the trusted caller |
| `diff_text` / `diff_digest` | UTF-8 text / SHA-256 | Full unified diff is the coordinate source; digest binds output to input |
| `changed_paths` | ordered path list | Derived by the trusted caller; normalized and validated by the module |
| `caps` | positive integer set | Maximum file, excerpt/fact, dependency-walk, and total output sizes |

The base is the checked-out trusted execution source. PR code is never checked
out, imported, evaluated, or executed.

## EvidenceBundle

| Field | Type | Contract |
|---|---|---|
| `schema_version` | integer | Starts at `1`; rejects unknown internal output shapes |
| `head_sha` | commit id | Matches the request exactly |
| `diff_sha256` | digest | Matches the full diff used for coordinate parsing |
| `facts` | ordered `EvidenceFact[]` | Canonically sorted and deduplicated; each fact owns ordered claim records |
| `omissions` | ordered `EvidenceOmission[]` | Every deletion, cap, or unsupported coverage gap that must be visible |

For identical request bytes and caps, serialization is byte-identical.

## EvidenceFact

| Field | Type | Contract |
|---|---|---|
| `kind` | closed enum | Existing `swift_receiver` or new `python_validation_predicate` |
| `path` | repository-relative path | Exact source blob location |
| `span` | start/end lines | Complete source span used for the structural fact |
| `anchor` | symbol + line | Hunk-visible seed that led to the fact |
| `structure` | typed object | Receiver relationship or predicate AST relationship |
| `claims` | ordered `ClaimCompletion[]` | Independent provable assertions; no fact-wide completion flag |
| `observations` | ordered observation list | Syntactic facts such as a literal fallback, without claiming runtime selection |
| `dependencies` | ordered dependency list | Material same-file bindings/helpers referenced by one or more claims |
| `derivation` | closed enum | Base-owned adapter that derived the structure |
| `content_trust` | constant | Always `untrusted_pr` for exact-HEAD source |
| `evidence_id` | stable digest | Derived from kind/path/span/head/blob digest |

Source excerpts may be quoted as JSON strings, but their trust remains
`untrusted_pr`. Only the base-owned labels, spans, AST relationships,
claim status, ordering, and hashes are trusted derivation.

## ClaimCompletion

| Field | Type | Contract |
|---|---|---|
| `claim` | closed enum | For example `predicate_structure`, `allowed_domain`, `subject_helper_semantics`, or `receiver_attachment` |
| `status` | `complete` or `unresolved` | Applies only to this claim |
| `value` | optional typed value | Present only when the supported proof closes |
| `proof_spans` | ordered source spans | Exact AST/source inputs used by the claim |
| `reason` | optional closed diagnostic | Required when `status=unresolved` |

One unresolved claim does not downgrade or certify another. There is no
fact-level `resolution` or `closure_complete` shortcut.

## Python predicate structure

For the supported subset:

| Field | Meaning |
|---|---|
| `operator` | Membership/non-membership or supported comparison operator |
| `expression_source` | Exact complete expression, quoted as untrusted data |
| `allowed_literals` | Canonically sorted literals resolved from safe local collection expressions |
| `negated` | Whether supported negation changes interpretation |
| `literal_fallbacks` | Syntactic observations of literal branches; runtime selection remains separately scoped |
| `claims` | Independent completion for predicate structure, allowed domain, and subject/helper semantics |

For PR #199, `predicate_structure` and `allowed_domain` are complete
because the comparison and RHS union are inside the safe subset.
`subject_helper_semantics` is unresolved because
`TIER_DIRECTIVE.search(name)` and `match.group(1)` are dynamic calls. The
literal `production` fallback is recorded only as an observation with
unresolved runtime selection.

Dynamic imports, reflection, cross-file dependencies, recursion/cycles, or
unsupported nodes never produce a fabricated claim value. They make the
affected claim unresolved or create an explicit omission according to the
error contract.

## EvidenceOmission

| Field | Type | Contract |
|---|---|---|
| `path` | path or null | Source affected, if any |
| `kind` | closed reason | `deleted`, `unsupported`, `cycle`, `file_cap`, `fact_cap`, or `total_cap` |
| `span` | optional lines | Coordinates when known |
| `detail` | base-owned text | No PR-authored instruction prose |

Caps omit whole facts and add an omission. They never byte-slice a typed record.

## ProtectedEnforcementChange

This is a pre-model failure record, not review evidence:

| Field | Contract |
|---|---|
| `path` | One of the five protected enforcement files |
| `base_blob_oid` | Trusted-base blob identity |
| `head_blob_oid` | Exact-head blob identity or missing marker |
| `reason` | changed, missing, replaced, or ambiguous |
| `result` | `protected_enforcement_change` with non-zero exit |

The protected set is the complete `review_context.py`,
`review-common.sh`, `codex-review.sh`, `codex-review-target.yml`, and
`main-protection.json` files.

No exception/allowlist field exists in PR-controlled input. T001 is the one
owner-reviewed bootstrap publication; legitimate later enforcement/policy
publication requires a new separately reviewed contract.

## Lifetime and compatibility

All records live only for one gate invocation. There is no database, retained
artifact requirement, product schema, or cross-version migration. Existing
Swift evidence remains behavior-compatible through schema version 1.
