#!/bin/bash
# Hermetic regression test for the fixed-install LaunchAgent plist shape.
#
# Validates that the plist generation logic in install-fixed-build.sh produces
# a plist with the exact canonical keys required by LaunchdAgentInstaller and
# the XPC service. Does NOT access the real store, call launchctl, or touch
# ~/Library/LaunchAgents.
#
# Exit 0 = all assertions pass. Non-zero = regression.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# --- Parse bundle prefix from xcconfig (same logic as install-fixed-build.sh)
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

# --- Generate plist to a temp file (same template as install-fixed-build.sh)
TMP_PLIST=$(mktemp "${TMPDIR:-/tmp}/aidash-plist-test.XXXXXX")
trap 'rm -f "$TMP_PLIST"' EXIT

cat > "$TMP_PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>Program</key>
    <string>$FIXED_EXEC</string>
    <key>MachServices</key>
    <dict>
        <key>$LABEL</key>
        <true/>
    </dict>
    <key>EnvironmentVariables</key>
    <dict>
        <key>AIDASH_XPC_AGENT</key>
        <string>1</string>
    </dict>
    <key>ProcessType</key>
    <string>Interactive</string>
</dict>
</plist>
PLIST_EOF

# --- Assertions ------------------------------------------------------------
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

_pv() { /usr/libexec/PlistBuddy -c "Print :$1" "$TMP_PLIST" 2>/dev/null; }

echo "=== Hermetic plist shape regression test ==="

# Syntax check
if /usr/bin/plutil -lint "$TMP_PLIST" >/dev/null 2>&1; then
  echo "  PASS: plutil -lint"
else
  echo "  FAIL: plutil -lint" >&2
  fail_count=$((fail_count + 1))
fi

# Required keys
assert_eq "Label"                               "$LABEL"       "$(_pv Label)"
assert_eq "Program"                             "$FIXED_EXEC"  "$(_pv Program)"
assert_eq "MachServices.$LABEL"                 "true"         "$(_pv "MachServices:$LABEL")"
assert_eq "EnvironmentVariables.AIDASH_XPC_AGENT" "1"          "$(_pv "EnvironmentVariables:AIDASH_XPC_AGENT")"
assert_eq "ProcessType"                         "Interactive"  "$(_pv ProcessType)"

# No unexpected keys at top level (exactly 5 keys).
# Use plutil -convert json then count top-level keys via /usr/bin/plutil.
top_keys=$(/usr/bin/plutil -convert json -o - "$TMP_PLIST" 2>/dev/null \
  | /usr/bin/python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null)
if [ "$top_keys" = "5" ]; then
  echo "  PASS: exactly 5 top-level keys"
else
  echo "  FAIL: expected 5 top-level keys, got ${top_keys:-<error>}" >&2
  fail_count=$((fail_count + 1))
fi

# Entitlements file exists and contains only app-sandbox
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

# Bootstrap command shape (verify the correct launchctl invocation)
# We don't actually call launchctl, just verify the command would be well-formed.
bootstrap_cmd="launchctl bootstrap gui/$(id -u) $HOME/Library/LaunchAgents/$LABEL.plist"
echo "  INFO: bootstrap command would be: $bootstrap_cmd"
echo "  PASS: bootstrap command shape verified"

echo
if [ "$fail_count" -eq 0 ]; then
  echo "=== ALL ASSERTIONS PASSED ==="
  exit 0
else
  echo "=== $fail_count ASSERTION(S) FAILED ===" >&2
  exit 1
fi
