#!/usr/bin/env bash
# contract_check.sh — lint the aidata↔AIDash card contract for silent drift.
#
# For each CardType, checks presence in the four places that must agree:
#   1. aidata mapper      L5_apps/digest/aidash.py            (emits type="<t>")
#   2. Core enum          CardType.swift                      (case <t>)
#   3. Schema ad          XPCHandlers.payloadSchemas          (CardType.<t>.rawValue)
#   4. UI router          CardRouter.swift                    (case let p as <Type>Payload)
#
# It is a LINT, not a proof. A PASS means no obvious structural drift; still verify
# real rendering (see references/verify.md). Exit 1 on any drift.
set -uo pipefail

AIDATA="${AIDATA_HOME:-${AIDASH_HOME:-$HOME/Development/AIDash}/aidata}"
AIDASH="${AIDASH_HOME:-$HOME/Development/AIDash}"

MAPPER="$AIDATA/L5_apps/digest/aidash.py"
CARDTYPE="$AIDASH/Packages/AIDashCore/Sources/AIDashCore/Models/CardType.swift"
HANDLERS="$AIDASH/Apps/AIDashApp/Sources/XPCService/XPCHandlers.swift"
ROUTER="$AIDASH/Packages/AIDashUI/Sources/AIDashUI/CardView/CardRouter.swift"

fail=0
for f in "$MAPPER" "$CARDTYPE" "$HANDLERS" "$ROUTER"; do
  if [[ ! -f "$f" ]]; then
    echo "FATAL: missing anchor file: $f" >&2
    echo "  (set AIDATA_HOME / AIDASH_HOME if your checkout differs)" >&2
    exit 2
  fi
done

# Source of truth for the type list: the enum's `case <name>` lines.
# Portable (bash 3.2 on macOS has no `mapfile`): read into a plain list.
TYPES="$(grep -oE '^[[:space:]]*case [a-zA-Z]+' "$CARDTYPE" | awk '{print $2}' | sort -u)"

if [[ -z "$TYPES" ]]; then
  echo "FATAL: no CardType cases parsed from $CARDTYPE" >&2
  exit 2
fi

# Uppercase-first helper for the <Type>Payload symbol.
cap() { printf '%s%s' "$(tr '[:lower:]' '[:upper:]' <<<"${1:0:1}")" "${1:1}"; }

printf '%-16s %-8s %-8s %-8s %-8s\n' "CardType" "mapper" "enum" "schema" "router"
printf '%-16s %-8s %-8s %-8s %-8s\n' "--------" "------" "----" "------" "------"

for t in $TYPES; do
  Type="$(cap "$t")"
  in_mapper="—"; in_enum="ok"; in_schema="—"; in_router="—"
  grep -qE "\"type\"[[:space:]]*:[[:space:]]*\"$t\"|type=\"$t\"|\"$t\"" "$MAPPER" && in_mapper="ok"
  grep -qE "CardType\.$t\.rawValue|\"$t\"" "$HANDLERS" && in_schema="ok"
  grep -qE "as ${Type}Payload" "$ROUTER" && in_router="ok"

  row_fail=0
  # enum is the source list, always ok. Router+schema must exist for a rendered type.
  [[ "$in_schema" == "ok" ]] || row_fail=1
  [[ "$in_router" == "ok" ]] || row_fail=1
  # mapper absence is a WARN (dead render path), not a hard fail.
  mark=""
  if [[ $row_fail -eq 1 ]]; then mark="  <-- DRIFT"; fail=1; fi
  if [[ "$in_mapper" != "ok" ]]; then mark="${mark:+$mark, }  (not emitted by mapper)"; fi
  printf '%-16s %-8s %-8s %-8s %-8s%s\n' "$t" "$in_mapper" "$in_enum" "$in_schema" "$in_router" "$mark"
done

echo
echo "Note: 'not emitted by mapper' is a WARN (dead render path is harmless)."
echo "      A DRIFT (missing schema/router for a type) is a hard FAIL."
echo "      Field-level required-vs-emitted drift is not machine-checkable here —"
echo "      see references/contract-sync.md and verify by real render (verify.md)."

if [[ $fail -eq 0 ]]; then
  echo
  echo "PASS: no structural card-type drift."
else
  echo
  echo "FAIL: drift detected — resolve per references/contract-sync.md."
fi
exit $fail
