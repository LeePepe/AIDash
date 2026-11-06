# ADR-006: Adopt Strata Shared Design System

## Status

Accepted for the Goal C AIDash pilot, subject to the companion constitution
amendment pull request.

## Context

AIDash currently owns `Packages/DesignKit` as its local design-system source.
Goal C adopts the Strata shared-design-system product as the sole design
language for the pilot. Its native products used by AIDash are
`NativeDesignKit` (components and theme surfaces) and `DesignTokens` (token
roles and identifiers). The dependency must be pinned to an exact approved
revision; a competing local source is not permitted.

The pilot also adds Favorites as a peer view to the daily briefing. Favorites
are derived from append-only user events, while rendered card content is kept
as a local SwiftData snapshot so it can remain readable when its source
briefing is unavailable. The snapshot is separate from CloudKit and never
synchronized.

## Decision

- Adopt Strata as AIDash's single design-system dependency, pinned to an exact
  approved version.
- Consume `NativeDesignKit` and `DesignTokens`; colors come from Strata roles
  and token IDs. The product brand role is `strata-blue`.
- Remove local `Packages/DesignKit` in the later migration task. This ADR
  authorizes governance and dependency direction; it does not implement that
  migration.
- Treat Favorites as a peer view to the daily briefing. It is not a history,
  search, detail, or drill-down surface.
- Store favorite card snapshots in one independent local SwiftData store and
  file. The snapshot model is excluded from every CloudKit schema and does
  not sync between devices. CloudKit remains authoritative for user events.

## North-star §11 alignment

The §11 conflict table was supplied by
`/Users/lee/Development/handoff/aidash-design/north-star.md` (sha256
`6c57b00d42201426fa8e9df5e2a4b73c956721e08dbd0408721e7b533c197ab3`). The
constitution's Design System & Tokens section is amended from that table:
geometry, spacing, badge transition behavior, semantic stripe roles, metric
typography, low-priority pill tone, and Strata token-source ownership now
follow its revised values. The principle III row was already handled by the
companion Favorites amendment and is unchanged here.

## Alternatives considered

1. **Keep local DesignKit** — rejected because it leaves two competing design
   languages.
2. **Use Strata without pinning** — rejected because visual and API behavior
   would not be reproducible.
3. **Synchronize favorite snapshots through CloudKit** — rejected because
   snapshots are an owner-approved local-only representation.

## Consequences

- The migration updates package/project dependencies, theme injection, token
  compliance checks, and screenshots in layer-owned tasks.
- Compliance evidence names Strata roles and token IDs, not hard-coded colors.
- Existing briefings, CloudKit records, and user-event semantics require no
  migration from this ADR alone.
- The north-star §11 source and its hash are recorded above; later UI work
  must preserve the row-level transition notes and must not infer a different
  mapping.

## Cost assessment

- **Binary size:** No binary-size measurement was made for this governance
  ADR. The incremental Strata binary impact is unmeasured and will be measured
  by AP2a after the exact dependency pin is integrated; no number is asserted
  here.
- **Build time:** No build-time measurement was made for this governance ADR.
  The dependency-resolution and compile impact is unmeasured and will be
  measured by AP2a with its required build evidence; no number is asserted
  here.
- **Swift 6 concurrency:** This ADR changes no Swift source and introduces no
  concurrency boundary. The integration's Swift 6 strict-concurrency impact
  is unmeasured and will be checked by AP2a's package/app builds; no claim of
  `Sendable` behavior is made here.
