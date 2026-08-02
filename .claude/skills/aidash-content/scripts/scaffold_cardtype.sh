#!/usr/bin/env bash
# scaffold_cardtype.sh — print the full anchor checklist + starter stubs for a
# BRAND-NEW CardType. Does NOT edit any files; you place the code yourself,
# matching surrounding idiom. See references/playbooks.md → E.
set -uo pipefail

name="${1:-}"
if [[ -z "$name" ]]; then
  echo "usage: scaffold_cardtype.sh <lowerCamelName>   e.g. scaffold_cardtype.sh riskAlert" >&2
  exit 2
fi
# Uppercase-first for the struct/view symbol.
Name="$(printf '%s%s' "$(tr '[:lower:]' '[:upper:]' <<<"${name:0:1}")" "${name:1}")"

AIDASH="${AIDASH_HOME:-$HOME/Development/AIDash}"
AIDATA="${AIDATA_HOME:-${AIDASH_HOME:-$HOME/Development/AIDash}/aidata}"

cat <<EOF
============================================================================
Scaffold checklist for new CardType: $name  (payload struct: ${Name}Payload)
Edit these anchors IN ORDER (schema first, renderer next, producer last).
Nothing below is written to disk — copy/adapt the stubs.
============================================================================

--- AIDashCore (schema single source; everyone depends on it) ---------------
[ ] NEW  $AIDASH/Packages/AIDashCore/Sources/AIDashCore/Models/Payloads/${Name}Payload.swift
[ ] EDIT $AIDASH/Packages/AIDashCore/Sources/AIDashCore/Models/CardType.swift
         - add:  case $name
         - add a decode arm:  case .$name: return try decoder.decode(${Name}Payload.self, from: data)
[ ] EDIT $AIDASH/Packages/AIDashCore/Sources/AIDashCore/Validation/SchemaValidator.swift   (only if cross-field invariants)
[ ] EDIT $AIDASH/Apps/AIDashApp/Sources/XPCService/XPCHandlers.swift
         - add: schemas[CardType.$name.rawValue] = "..."   (JSON Schema string)
[ ] EDIT $AIDASH/CLI/aidash/Sources/SchemaListRendering.swift   (if it enumerates types)
[ ] TEST CardTypeDecodeTests / CardPayloadRoundTripTests / SchemaValidatorTests   (add cases)

--- AIDashUI (renderer) -----------------------------------------------------
[ ] NEW  $AIDASH/Packages/AIDashUI/Sources/AIDashUI/CardView/${Name}CardView.swift
[ ] EDIT $AIDASH/Packages/AIDashUI/Sources/AIDashUI/CardView/CardRouter.swift
         - add: case let p as ${Name}Payload:
                    ${Name}CardView(payload: p, size: effectiveSize, style: card.style)
[ ] TEST ${Name}CardViewTests + a SnapshotRenderTests case (render to PNG, light+dark)

--- aidata (producer/mapper; LAST — needs the type to exist) -----------------
[ ] EDIT $AIDATA/L5_apps/digest/aidash.py
         - add a _${name}_container(...) builder returning Container(... Card(type="$name" ...))
         - call it from build_briefing(); guard on SourceHealth; degrade to no-container
[ ] EDIT $AIDATA/L5_apps/digest/sources.py   (fetch_* bundle feeding it, if new)
[ ] EDIT $AIDATA/L5_apps/digest/app.py       (wire fetch into _fetch_sources + DigestSources)
[ ] TEST aidata pytest for the new mapper (pure, hermetic; assert card absent when degraded)

--- verify ------------------------------------------------------------------
[ ] bash .claude/skills/aidash-content/scripts/contract_check.sh   (type in all 4 places)
[ ] full verify per references/verify.md (Core + UI snapshot + real push)

============================================================================
STARTER STUBS  (adapt — do not paste verbatim)
============================================================================

--- ${Name}Payload.swift ----------------------------------------------------
import Foundation

public struct ${Name}Payload: Codable, Sendable, CardPayloadProtocol {
    public let title: String
    // TODO: real fields. New OPTIONAL fields keep old app builds compatible.

    public init(title: String) {
        self.title = title
    }

    public func validateInvariants() throws {
        guard !title.isEmpty else {
            throw CardPayloadError.invalid("$name: title must not be empty")
        }
        // TODO: field invariants (e.g. ratio in 0...1).
    }
}

--- CardRouter.swift (add arm) ----------------------------------------------
        case let p as ${Name}Payload:
            ${Name}CardView(payload: p, size: effectiveSize, style: card.style)

--- payloadSchemas entry (XPCHandlers.swift) --------------------------------
        schemas[CardType.$name.rawValue] = """
        {"type":"object","required":["title"],"properties":{"title":{"type":"string","minLength":1}}}
        """

--- aidash.py mapper (builder) ----------------------------------------------
def _${name}_container(mmdd: str, bundle) -> "Container | None":
    """One $name card, or None when the source is degraded/empty."""
    if bundle is None or bundle.health.state != "ok":
        return None
    payload = {"title": bundle.title}  # TODO: real fields, optional-when-missing
    return Container(_cuid(mmdd, N), "TODO 标题", ORDER,
                     (Card(_kuid(mmdd, M), "$name", "wide", payload),),
                     layout="auto")
# then in build_briefing():
#   c = _${name}_container(mmdd, getattr(sources, "<field>", None))
#   if c: containers.append(c)
============================================================================
EOF
