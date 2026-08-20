#!/bin/bash
# Hermetic regression test for the fixed-install LaunchAgent plist.
#
# Sources the REAL lib-fixed-install-plist.sh helper (the same code path used
# by install-fixed-build.sh in production) to render, validate, and bootstrap.
# Injects a fake launchctl via FIXED_LAUNCHCTL_CMD to capture and assert the
# exact argv without touching the real launchd job or store.
#
# Exit 0 = all assertions pass. Non-zero = regression.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

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
MACH_SERVICE="$LABEL.xpc.v1"
UID_N="$(id -u)"

# --- Create fake launchctl that records argv ---------------------------------
FAKE_LAUNCHCTL_LOG=$(mktemp "${TMPDIR:-/tmp}/fake-launchctl-log.XXXXXX")
FAKE_LAUNCHCTL_BIN=$(mktemp "${TMPDIR:-/tmp}/fake-launchctl.XXXXXX")
chmod +x "$FAKE_LAUNCHCTL_BIN"
cat > "$FAKE_LAUNCHCTL_BIN" <<'FAKE_EOF'
#!/bin/bash
# Fake launchctl: record all argv (one per line) then exit 0
for arg in "$@"; do
  printf '%s\n' "$arg"
done > "$FAKE_LAUNCHCTL_LOG_PATH"
exit 0
FAKE_EOF
# The fake reads its log path from env — inject it
export FAKE_LAUNCHCTL_LOG_PATH="$FAKE_LAUNCHCTL_LOG"

# Inject the fake into the helper via FIXED_LAUNCHCTL_CMD
export FIXED_LAUNCHCTL_CMD="$FAKE_LAUNCHCTL_BIN"

# --- Source the shared helper (production code path) -------------------------
source "$SCRIPT_DIR/lib-fixed-install-plist.sh"

# --- Temp plist (cleaned up on exit) -----------------------------------------
TMP_PLIST=$(mktemp "${TMPDIR:-/tmp}/aidash-plist-test.XXXXXX")
trap 'rm -f "$TMP_PLIST" "$FAKE_LAUNCHCTL_LOG" "$FAKE_LAUNCHCTL_BIN"' EXIT

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
assert_neq() {
  local desc=$1 val_a=$2 val_b=$3
  if [ "$val_a" != "$val_b" ]; then
    echo "  PASS: $desc ('$val_a' != '$val_b')"
  else
    echo "  FAIL: $desc — values should differ but both are '$val_a'" >&2
    fail_count=$((fail_count + 1))
  fi
}

echo "=== Hermetic plist shape regression test ==="
echo "  (exercises the real lib-fixed-install-plist.sh helper)"

# --- 1. Render plist via the shared helper -----------------------------------
render_fixed_plist "$TMP_PLIST" "$LABEL" "$MACH_SERVICE" "$FIXED_EXEC"
if [ -s "$TMP_PLIST" ]; then
  echo "  PASS: render_fixed_plist produced non-empty output"
else
  echo "  FAIL: render_fixed_plist produced empty file" >&2
  fail_count=$((fail_count + 1))
fi

# --- 2. Validate plist via the shared helper ---------------------------------
if validate_fixed_plist "$TMP_PLIST" "$LABEL" "$MACH_SERVICE" "$FIXED_EXEC"; then
  echo "  PASS: validate_fixed_plist succeeded"
else
  echo "  FAIL: validate_fixed_plist returned non-zero" >&2
  fail_count=$((fail_count + 1))
fi

# --- 3. Verify exact 5-key shape --------------------------------------------
_pv() { /usr/libexec/PlistBuddy -c "Print :$1" "$TMP_PLIST" 2>/dev/null; }

assert_eq "Label"                               "$LABEL"        "$(_pv Label)"
assert_eq "Program"                             "$FIXED_EXEC"   "$(_pv Program)"
assert_eq "MachServices.$MACH_SERVICE"          "true"          "$(_pv "MachServices:$MACH_SERVICE")"
assert_eq "EnvironmentVariables.AIDASH_XPC_AGENT" "1"           "$(_pv "EnvironmentVariables:AIDASH_XPC_AGENT")"
assert_eq "ProcessType"                         "Interactive"   "$(_pv ProcessType)"

# Count top-level keys (exactly 5)
top_keys=$(/usr/bin/plutil -convert json -o - "$TMP_PLIST" 2>/dev/null \
  | /usr/bin/python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null)
assert_eq "top-level key count" "5" "${top_keys:-<error>}"

# --- 4. Assert Label != MachServices key (they MUST differ) ------------------
assert_neq "Label differs from MachServices key" "$LABEL" "$MACH_SERVICE"

# MachServices must NOT contain Label as a key (only MACH_SERVICE)
mach_label_val=$(/usr/libexec/PlistBuddy -c "Print :MachServices:$LABEL" "$TMP_PLIST" 2>/dev/null)
if [ -z "$mach_label_val" ]; then
  echo "  PASS: MachServices does NOT contain Label key '$LABEL'"
else
  echo "  FAIL: MachServices contains Label key '$LABEL' (should only have '$MACH_SERVICE')" >&2
  fail_count=$((fail_count + 1))
fi

# --- 5. Bootstrap via shared helper with fake launchctl ----------------------
# Call the SAME bootstrap_fixed_launchagent helper that production uses.
# FIXED_LAUNCHCTL_CMD points to our fake, which records argv.
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"
bootstrap_fixed_launchagent "$UID_N" "$PLIST_PATH"
bootstrap_rc=$?
assert_eq "bootstrap_fixed_launchagent exit code" "0" "$bootstrap_rc"

# Assert the fake launchctl received exactly 3 argv: bootstrap gui/<uid> <plist>
argv_line1=$(sed -n '1p' "$FAKE_LAUNCHCTL_LOG" 2>/dev/null)
argv_line2=$(sed -n '2p' "$FAKE_LAUNCHCTL_LOG" 2>/dev/null)
argv_line3=$(sed -n '3p' "$FAKE_LAUNCHCTL_LOG" 2>/dev/null)
argv_count=$(wc -l < "$FAKE_LAUNCHCTL_LOG" 2>/dev/null | tr -d ' ')

assert_eq "launchctl argv count" "3" "$argv_count"
assert_eq "launchctl argv[0]" "bootstrap" "$argv_line1"
assert_eq "launchctl argv[1]" "gui/$UID_N" "$argv_line2"
assert_eq "launchctl argv[2]" "$PLIST_PATH" "$argv_line3"

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
