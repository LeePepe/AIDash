#!/bin/bash
# Hermetic regression test for the fixed-install LaunchAgent plist.
#
# Invokes the SAME provision_fixed_launchagent function that production uses
# (from lib-fixed-install-plist.sh), with a temp plist directory and a fake
# launchctl. If production deletes/reorders/changes the provisioning call,
# the structural assertion on the installer source fails.
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
for arg in "$@"; do
  printf '%s\n' "$arg"
done > "$FAKE_LAUNCHCTL_LOG_PATH"
exit 0
FAKE_EOF
export FAKE_LAUNCHCTL_LOG_PATH="$FAKE_LAUNCHCTL_LOG"
export FIXED_LAUNCHCTL_CMD="$FAKE_LAUNCHCTL_BIN"

# --- Source the shared helper (production code path) -------------------------
source "$SCRIPT_DIR/lib-fixed-install-plist.sh"

# --- Temp plist dir (not ~/Library/LaunchAgents) -----------------------------
TMP_PLIST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/aidash-plist-test.XXXXXX")
trap 'rm -rf "$TMP_PLIST_DIR" "$FAKE_LAUNCHCTL_LOG" "$FAKE_LAUNCHCTL_BIN"' EXIT

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
echo "  (invokes the real provision_fixed_launchagent production seam)"

# --- 1. Invoke the production seam with temp dir + fake launchctl ------------
provision_fixed_launchagent "$TMP_PLIST_DIR" "$LABEL" "$MACH_SERVICE" "$FIXED_EXEC" "$UID_N"
provision_rc=$?
assert_eq "provision_fixed_launchagent exit code" "0" "$provision_rc"

# --- 2. Verify the plist was written to the expected path --------------------
PLIST_PATH="$TMP_PLIST_DIR/$LABEL.plist"
if [ -f "$PLIST_PATH" ]; then
  echo "  PASS: plist file exists at expected path"
else
  echo "  FAIL: plist file missing at $PLIST_PATH" >&2
  fail_count=$((fail_count + 1))
fi

# --- 3. Verify exact 5-key shape --------------------------------------------
_pv() { /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST_PATH" 2>/dev/null; }

assert_eq "Label"                               "$LABEL"        "$(_pv Label)"
assert_eq "Program"                             "$FIXED_EXEC"   "$(_pv Program)"
assert_eq "MachServices.$MACH_SERVICE"          "true"          "$(_pv "MachServices:$MACH_SERVICE")"
assert_eq "EnvironmentVariables.AIDASH_XPC_AGENT" "1"           "$(_pv "EnvironmentVariables:AIDASH_XPC_AGENT")"
assert_eq "ProcessType"                         "Interactive"   "$(_pv ProcessType)"

top_keys=$(/usr/bin/plutil -convert json -o - "$PLIST_PATH" 2>/dev/null \
  | /usr/bin/python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null)
assert_eq "top-level key count" "5" "${top_keys:-<error>}"

# --- 4. Assert Label != MachServices key (they MUST differ) ------------------
assert_neq "Label differs from MachServices key" "$LABEL" "$MACH_SERVICE"

mach_label_val=$(/usr/libexec/PlistBuddy -c "Print :MachServices:$LABEL" "$PLIST_PATH" 2>/dev/null)
if [ -z "$mach_label_val" ]; then
  echo "  PASS: MachServices does NOT contain Label key '$LABEL'"
else
  echo "  FAIL: MachServices contains Label key '$LABEL'" >&2
  fail_count=$((fail_count + 1))
fi

# --- 5. Assert fake launchctl received exact 3 argv from bootstrap -----------
argv_line1=$(sed -n '1p' "$FAKE_LAUNCHCTL_LOG" 2>/dev/null)
argv_line2=$(sed -n '2p' "$FAKE_LAUNCHCTL_LOG" 2>/dev/null)
argv_line3=$(sed -n '3p' "$FAKE_LAUNCHCTL_LOG" 2>/dev/null)
argv_count=$(wc -l < "$FAKE_LAUNCHCTL_LOG" 2>/dev/null | tr -d ' ')

assert_eq "launchctl argv count" "3" "$argv_count"
assert_eq "launchctl argv[0]" "bootstrap" "$argv_line1"
assert_eq "launchctl argv[1]" "gui/$UID_N" "$argv_line2"
assert_eq "launchctl argv[2]" "$PLIST_PATH" "$argv_line3"

# --- 6. Structural assertion: installer MUST call provision_fixed_launchagent -
# If production deletes, reorders, or replaces the provisioning call, this
# assertion fails. Greps the installer source for the exact call signature.
INSTALLER="$REPO_ROOT/scripts/dev/install-fixed-build.sh"
if grep -q 'provision_fixed_launchagent "\$PLIST_DIR" "\$LABEL" "\$MACH_SERVICE" "\$FIXED_EXEC" "\$UID_N"' "$INSTALLER"; then
  echo "  PASS: installer calls provision_fixed_launchagent with exact signature"
else
  echo "  FAIL: installer missing provision_fixed_launchagent call with expected args" >&2
  fail_count=$((fail_count + 1))
fi

# --- 7. Entitlements file checks --------------------------------------------
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
