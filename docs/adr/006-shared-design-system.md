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

## North-star conflict-table boundary

The referenced design source `/workspace/aidash-design/north-star.md`,
including its §11 conflict table, was unavailable when this ADR was written.
This ADR therefore records only directly confirmed rules: the two Strata
products, the `strata-blue` brand role, token-only color consumption, and
compliance evidence by Strata role/token ID. The §11 table's individual rows,
precedence decisions, and migration dispositions remain explicit follow-up
input and must be copied into the UI migration spec before those rows are
claimed as resolved.

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
- The missing north-star §11 source remains a documentation gap and must not
  be silently resolved by implementation inference.
