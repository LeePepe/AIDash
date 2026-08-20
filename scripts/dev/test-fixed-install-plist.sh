#!/bin/bash
# Hermetic regression test for the fixed-install LaunchAgent plist.
#
# Sources the REAL lib-fixed-install-plist.sh helper (the same code path used
# by install-fixed-build.sh in production) to render and validate the plist.
# Injects a fake launchctl function to capture and assert the exact bootstrap
# args without touching the real launchd job or store.
#
# Exit 0 = all assertions pass. Non-zero = regression.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source the shared helper — this IS the production code path.
source "$SCRIPT_DIR/lib-fixed-install-plist.sh"

# --- Parse bundle prefix from xcconfig (same as install-fixed-build.sh) ------
_xcc_val() {
  local v=""
  for f in "$REPO_ROOT/Configs/Identity.xcconfig" "$REPO_ROOT/Configs/Identity.local.xcconfig"; do
    [ -f "$f" ] || continue
    local hit
    hit="$(sed -nE "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*(.*[^[:space:]])[[:space:]]*$/\\1/p" "$f" | tail -1)"
    [ -n "$hit" ] && v="$hit"
  done
  printf '%s' "$v"
}
LABEL="$(_xcc_val AIDASH_BUNDLE_PREFIX).aidash"
if [ "$LABEL" = ".aidash" ]; then
  echo "FAIL: cannot parse AIDASH_BUNDLE_PREFIX from xcconfig" >&2
  exit 1
fi

FIXED_EXEC="/Applications/AIDash.app/Contents/MacOS/AIDash"
UID_N="$(id -u)"

# --- Temp plist (cleaned up on exit) -----------------------------------------
TMP_PLIST=$(mktemp "${TMPDIR:-/tmp}/aidash-plist-test.XXXXXX")
trap 'rm -f "$TMP_PLIST"' EXIT

# --- Assertions framework ---------------------------------------------------
fail_count=0
assert_eq() {
  local desc=$1 expected=$2 actual=$3
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $desc"
  else
    echo "  FAIL: $desc — expected '$expected', got '$actual'" >&2
    fail_count=$((fail_count + 1))
  fi
}

echo "=== Hermetic plist shape regression test ==="
echo "  (exercises the real lib-fixed-install-plist.sh helper)"

# --- 1. Render plist via the shared helper -----------------------------------
render_fixed_plist "$TMP_PLIST" "$LABEL" "$FIXED_EXEC"
if [ -s "$TMP_PLIST" ]; then
  echo "  PASS: render_fixed_plist produced non-empty output"
else
  echo "  FAIL: render_fixed_plist produced empty file" >&2
  fail_count=$((fail_count + 1))
fi

# --- 2. Validate plist via the shared helper ---------------------------------
if validate_fixed_plist "$TMP_PLIST" "$LABEL" "$FIXED_EXEC"; then
  echo "  PASS: validate_fixed_plist succeeded"
else
  echo "  FAIL: validate_fixed_plist returned non-zero" >&2
  fail_count=$((fail_count + 1))
fi

# --- 3. Verify exact 5-key shape --------------------------------------------
_pv() { /usr/libexec/PlistBuddy -c "Print :$1" "$TMP_PLIST" 2>/dev/null; }

assert_eq "Label"                               "$LABEL"       "$(_pv Label)"
assert_eq "Program"                             "$FIXED_EXEC"  "$(_pv Program)"
assert_eq "MachServices.$LABEL"                 "true"         "$(_pv "MachServices:$LABEL")"
assert_eq "EnvironmentVariables.AIDASH_XPC_AGENT" "1"          "$(_pv "EnvironmentVariables:AIDASH_XPC_AGENT")"
assert_eq "ProcessType"                         "Interactive"  "$(_pv ProcessType)"

# Count top-level keys (exactly 5)
top_keys=$(/usr/bin/plutil -convert json -o - "$TMP_PLIST" 2>/dev/null \
  | /usr/bin/python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null)
assert_eq "top-level key count" "5" "${top_keys:-<error>}"

# --- 4. Verify bootstrap command args via shared helper ----------------------
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"
bootstrap_args=$(bootstrap_command_args "$UID_N" "$PLIST_PATH")
expected_args="gui/$UID_N $PLIST_PATH"
assert_eq "bootstrap_command_args" "$expected_args" "$bootstrap_args"

# --- 5. Inject fake launchctl and verify exact invocation --------------------
# Override launchctl with a shell function that records args instead of
# touching the real launchd job.
FAKE_LAUNCHCTL_LOG=$(mktemp "${TMPDIR:-/tmp}/fake-launchctl.XXXXXX")
trap 'rm -f "$TMP_PLIST" "$FAKE_LAUNCHCTL_LOG"' EXIT

launchctl() {
  echo "$*" >> "$FAKE_LAUNCHCTL_LOG"
  return 0
}
export -f launchctl 2>/dev/null || true

# Simulate what the installer does: launchctl bootstrap <args>
launchctl bootstrap $(bootstrap_command_args "$UID_N" "$PLIST_PATH")

# Verify the fake launchctl saw the exact expected invocation
recorded=$(cat "$FAKE_LAUNCHCTL_LOG" 2>/dev/null)
assert_eq "fake launchctl args" "bootstrap gui/$UID_N $PLIST_PATH" "$recorded"

# --- 6. Entitlements file checks --------------------------------------------
ENT_FILE="$REPO_ROOT/Apps/AIDashApp/AIDashApp.macOS.fixed.entitlements"
if [ -f "$ENT_FILE" ]; then
  echo "  PASS: fixed entitlements file exists"
else
  echo "  FAIL: fixed entitlements file missing at $ENT_FILE" >&2
  fail_count=$((fail_count + 1))
fi

if /usr/bin/plutil -lint "$ENT_FILE" >/dev/null 2>&1; then
  echo "  PASS: fixed entitlements plutil -lint"
else
  echo "  FAIL: fixed entitlements plutil -lint" >&2
  fail_count=$((fail_count + 1))
fi

ent_sandbox=$(/usr/libexec/PlistBuddy -c "Print :com.apple.security.app-sandbox" "$ENT_FILE" 2>/dev/null)
assert_eq "entitlements app-sandbox" "true" "$ent_sandbox"

# Entitlements must NOT contain CloudKit/iCloud/network keys
for forbidden_key in \
  "com.apple.developer.icloud-services" \
  "com.apple.developer.icloud-container-identifiers" \
  "com.apple.developer.ubiquity-container-identifiers" \
  "com.apple.security.network.client"; do
  if /usr/libexec/PlistBuddy -c "Print :$forbidden_key" "$ENT_FILE" >/dev/null 2>&1; then
    echo "  FAIL: entitlements contains forbidden key $forbidden_key" >&2
    fail_count=$((fail_count + 1))
  else
    echo "  PASS: no $forbidden_key"
  fi
done

# --- Result ------------------------------------------------------------------
echo
if [ "$fail_count" -eq 0 ]; then
  echo "=== ALL ASSERTIONS PASSED ==="
  exit 0
else
  echo "=== $fail_count ASSERTION(S) FAILED ===" >&2
  exit 1
fi
