# Data Model: Trusted Exact-HEAD Decision Evidence

This feature introduces no persisted application, warehouse, or configuration
data and requires no migration.

The internal evidence module uses transient typed concepts for one required
review run.

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
| `facts` | ordered `EvidenceFact[]` | Canonically sorted and deduplicated |
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
| `dependencies` | ordered dependency list | Material same-file bindings/helpers and literal fallbacks |
| `resolution` | `complete` or `unresolved` | `complete` only after supported bounded closure |
| `derivation` | closed enum | Base-owned adapter that derived the structure |
| `content_trust` | constant | Always `untrusted_pr` for exact-HEAD source |
| `evidence_id` | stable digest | Derived from kind/path/span/head/blob digest |

Source excerpts may be quoted as JSON strings, but their trust remains
`untrusted_pr`. Only the base-owned labels, spans, AST relationships,
resolution state, ordering, and hashes are trusted derivation.

## Python predicate structure

For the supported subset:

| Field | Meaning |
|---|---|
| `operator` | Membership/non-membership or supported comparison operator |
| `expression_source` | Exact complete expression, quoted as untrusted data |
| `allowed_literals` | Canonically sorted literals resolved from safe local collection expressions |
| `negated` | Whether supported negation changes interpretation |
| `literal_fallbacks` | Literal defaults/fallbacks found in material local helpers |
| `closure_complete` | True only if every material supported same-file name/helper closes |

Dynamic imports, reflection, cross-file dependencies, recursion/cycles, or
unsupported nodes never produce a fabricated allowed domain. They produce an
`unresolved` fact or explicit omission according to the error contract.

## EvidenceOmission

| Field | Type | Contract |
|---|---|---|
| `path` | path or null | Source affected, if any |
| `kind` | closed reason | `deleted`, `unsupported`, `cycle`, `file_cap`, `fact_cap`, or `total_cap` |
| `span` | optional lines | Coordinates when known |
| `detail` | base-owned text | No PR-authored instruction prose |

Caps omit whole facts and add an omission. They never byte-slice a typed record.

## ProtectedInstructionChange

This is a pre-model failure record, not review evidence:

| Field | Contract |
|---|---|
| `path` | `scripts/ci/review-common.sh` or `scripts/ci/codex-review.sh` |
| `region` | `review_evidence_rules`, `review_security_notice`, or `codex_prompt` |
| `reason` | changed, missing, duplicated, or ambiguous |
| `result` | `protected_instruction_change` with non-zero exit |

No exception/allowlist field exists in PR-controlled input. Legitimate policy
publication requires a separate owner-reviewed contract.

## Lifetime and compatibility

All records live only for one gate invocation. There is no database, retained
artifact requirement, product schema, or cross-version migration. Existing
Swift evidence remains behavior-compatible through schema version 1.
