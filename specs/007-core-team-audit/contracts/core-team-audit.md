# Contract: AIDashCore teamAudit

## Registration and coordinated advertisement

- The exact CardType wire value is teamAudit.
- CardType.teamAudit decodes TeamAuditPayload through the existing single-decode
  CardType.validate interface.
- All four authored CardSize values, small, medium, wide, and hero, pass
  through both EffectiveCardSize resolver paths unchanged, including when
  collapse-to-list is enabled.
- The ten existing card types and their behavior remain unchanged.
- AIDashApp adds one real JSON schema whose discriminator and fields match the
  public model. Both schema-list builders advertise the same eleven card types
  and eleven payload schemas.
- aidash card put help derives or proves its type vocabulary against
  CardType.allCases, and a teamAudit request remains a generic shared-Core
  validation request. No audit-specific CLI validator is introduced.
- Core registration, App schema adaptation, and CLI help/consumer adaptation
  are one coordinated publication unit. None may be published or merged alone.

## Normative public wire surface

TeamAuditPayload and every nested value needed for a complete fixture are
public, Codable, Equatable, and Sendable with public memberwise initializers.
The exact field names, types, optionality, enum raw values, and reconciliation
equations are defined in ../data-model.md.

The envelope always contains snapshotID, capturedAt, scope, mode, section,
partIndex, partCount, contentSHA256, artifactSidecarID,
artifactSidecarSHA256, and referenceCatalog.

Exactly one selected body key is present and non-null:

    overview | findings | caseTimelines | individualMetrics |
    feedbackLineage | agentRepeatMetrics | importObservations | artifacts

The other seven keys are absent. A null, empty selected collection, unrelated
body key, or discriminator/body mismatch rejects. Unknown locked enum values
use the existing structured decode/schema failure and are never coerced.

## Referential and reconciliation contract

Every selected-body case, event, evidence, subject, finding, revision, and
artifact reference resolves exactly once in SnapshotReferenceCatalog.
Catalog identities are trimmed and unique; artifact entries preserve kind,
ID, hash, raw URL, and sidecar binding without presentation bodies.

The mandatory equations and relationships include:

- baseline has a cohort and no cursors; incremental has no cohort and has one
  or more unique-source cursors;
- available evidence plus missing evidence equals required evidence, and
  redacted evidence does not exceed available evidence;
- exactly one Workflow Conformance, Workflow Fitness, and Outcome Integrity
  summary exists; each count triple equals its total;
- each shared insufficientEvidence value decodes only inside its already
  decoded enclosing axis;
- Task Effectiveness is separate and its five counts equal totalEvaluated;
- all four publication required/published pairs match independently; a chain
  cannot satisfy a finding and a report cannot satisfy a mandatory pair;
- timeline identity arrays exactly equal their embedded event/attempt order
  and every embedded value binds to the same case;
- finding evidence arrays and repeat supporting subject/event arrays are
  non-empty, unique, and catalog-resolved;
- feedback lineage ID is lowercase SHA-256 of the trimmed
  problem/origin/delivery tuple joined by U+001F; a merge OID is lowercase
  40-hex;
- every role-specific repeat tag matches actorRole, all counters are
  non-negative, all breakdown equations hold, every primary round total is no
  greater than attemptsTotal, and zero attempts has zero repeat/round/max
  counters;
- a collision has the envelope parent ID/hash, unequal accepted/rejected
  hashes, the sole locked disposition, and no rejected body.

All focused positive and one-field negative proofs are mandatory in
core-acceptance-matrix.md.

## Artifact caseID contract

An ArtifactManifestEntry caseID has three distinct states:

- omitted is valid;
- present, trimmed, and non-empty is valid only when it resolves exactly once
  through referenceCatalog.caseIDs;
- blank, dangling, or multiply resolved rejects.

Both direct card validation and the production schema-validation path prove
all states.

## Full-report and externalization contract

A FullReportReference is accepted only when exactly one ArtifactReference
matches all six dimensions:

| Dimension | Relationship |
|---|---|
| kind | exactly fullReport |
| artifact ID | exact equality |
| content SHA-256 | exact equality |
| raw URL | exact equality |
| sidecar ID | exact equality and envelope equality |
| sidecar SHA-256 | exact equality and envelope equality |

The same rule applies from overview publication coverage, ArtifactSection,
and ExternalizedEntityReference. Every dimension, absence, and duplication has
an isolated negative fixture.

Externalization has only these optional kinds:

    p2Finding | infoFinding | caseTimeline | individualMetric |
    feedbackLineage | agentRepeatMetric | importObservation | optionalArtifact

Each reference has a non-empty stableID, encodedByteCount greater than zero,
reason exactly exceedsInlinePayloadLimit, envelope-equal sidecar fields, and a
full report exactly equal to the section report. Mandatory-shaped and unknown
kinds have no enum case.

## URL and byte seams

Models treats URL fields as exact opaque strings. It enforces presence and
equality only and contains no URLPolicy or Validation-role reference.

TeamAuditPayloadValidation.swift supplies validateInvariants, first running
the structural helper and then the unchanged central URL policy for:

- every full-report URL;
- every mandatory artifact URL;
- every present feedback-lineage PR URL.

Optional artifact and grill strings remain exact non-actionable data even when
unsafe. SchemaValidator.swift, URLPolicy.swift, CardPayloadProtocol.swift, and
their interfaces remain unchanged.

The existing received-data limit remains 262,144 UTF-8 bytes. An otherwise
valid teamAudit payload at exactly 262,144 received bytes passes; an
otherwise-valid mandatory payload at exactly 262,145 bytes fails. The
production path measures received Data.count and does not decide from semantic
re-encoding.

## Existing behavior reused unchanged

- Existing structured errors, URL policy, ten payloads, and generic UI
  fallback stay accepted.
- The baseline DesignKit Classification.teamAudit token already exists with
  light #E6294D and dark #FF375F and existing golden/contrast coverage. It is
  reused unchanged; this successor creates no DesignKit work.
- Validation is deterministic and side-effect-free. It performs no storage,
  network, publication, issue, dispatch, or remediation action.
