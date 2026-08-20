#!/bin/bash
# Build a Release AIDash + aidash CLI and install them to FIXED paths outside
# Xcode's DerivedData, then point the XPC LaunchAgent at the fixed app.
#
# Why: app + CLI normally live under
# ~/Library/Developer/Xcode/DerivedData/AIDash-*/Build/Products/Debug/, which
# gets churned by every rebuild / `xcodebuild clean` / DerivedData purge. That
# churn boots the launchd-brokered mach service out from under the daily 04:00
# push, so the dashboard silently stops updating. A fixed install path gives the
# mach service a stable Program to broker to, decoupled from dev-time builds.
#
# Signing (ADR-003): build unsigned (CODE_SIGNING_ALLOWED=NO), then post-build
# ad-hoc codesign with AIDashApp.macOS.fixed.entitlements (app-sandbox only, no
# CloudKit). This makes the fixed install sandboxed so it can access the
# canonical container store path on macOS 26, while keeping CloudKit unavailable
# (the app falls back to local-only — current behavior).
#
# Idempotent: safe to re-run. Each run rebuilds, reinstalls, and re-points XPC.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT" || { echo "[install-fixed] repo root not found" >&2; exit 1; }

# Bundle ID / launchd label —— 从 Configs/Identity.xcconfig(+ 可选的本地覆盖)
# 解析,所以改了配置这里自动跟随。AIDASH_BUNDLE_ID 的约定是 <prefix>.aidash。
_xcc_val() {  # $1 = 变量名;后出现的定义覆盖先出现的(与 xcconfig 语义一致)
  local v=""
  for f in Configs/Identity.xcconfig Configs/Identity.local.xcconfig; do
    [ -f "$f" ] || continue
    local hit
    hit="$(sed -nE "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*(.*[^[:space:]])[[:space:]]*$/\\1/p" "$f" | tail -1)"
    [ -n "$hit" ] && v="$hit"
  done
  printf '%s' "$v"
}
LABEL="$(_xcc_val AIDASH_BUNDLE_PREFIX).aidash"
if [ "$LABEL" = ".aidash" ]; then
  echo "[dev] 无法从 Configs/Identity.xcconfig 解析 AIDASH_BUNDLE_PREFIX" >&2
  exit 1
fi
UID_N="$(id -u)"
APP_DST="/Applications/AIDash.app"
BIN_DIR="$HOME/.local/bin"
BIN_DST="$BIN_DIR/aidash"
TMP_DD="$(mktemp -d "${TMPDIR:-/tmp}/aidash-fixed-build.XXXXXX")"
PRODUCTS="$TMP_DD/Build/Products/Release"

cleanup() { rm -rf "$TMP_DD"; }
trap cleanup EXIT

# Shared xcodebuild flags: ad-hoc sign, no Distribution cert, no sandbox churn.
COMMON_FLAGS=(
  -project AIDash.xcodeproj
  -configuration Release
  -destination 'generic/platform=macOS'
  -derivedDataPath "$TMP_DD"
  CODE_SIGN_IDENTITY=-
  CODE_SIGN_STYLE=Manual
  CODE_SIGNING_REQUIRED=NO
  CODE_SIGNING_ALLOWED=NO
)

echo "[install-fixed] building Release AIDashApp (ad-hoc) → $TMP_DD"
if ! xcodebuild "${COMMON_FLAGS[@]}" -scheme AIDashApp build; then
  echo "[install-fixed] ERROR: app build failed" >&2
  exit 1
fi

echo "[install-fixed] building Release aidash CLI (ad-hoc)"
if ! xcodebuild "${COMMON_FLAGS[@]}" -scheme aidash build; then
  echo "[install-fixed] ERROR: CLI build failed" >&2
  exit 1
fi

APP_SRC="$PRODUCTS/AIDash.app"
BIN_SRC="$PRODUCTS/aidash"
[ -d "$APP_SRC" ] || { echo "[install-fixed] ERROR: built app missing at $APP_SRC" >&2; exit 1; }
[ -x "$BIN_SRC" ] || { echo "[install-fixed] ERROR: built CLI missing at $BIN_SRC" >&2; exit 1; }

# --- Post-build ad-hoc codesign (ADR-003) -----------------------------------
# Embed app-sandbox entitlement via deterministic inside-out signing. The build
# is unsigned (CODE_SIGNING_ALLOWED=NO); we sign post-build so entitlements are
# embedded exactly as specified, with no dependency on team ID or provisioning.
ENTITLEMENTS="$REPO_ROOT/Apps/AIDashApp/AIDashApp.macOS.fixed.entitlements"
[ -f "$ENTITLEMENTS" ] || { echo "[install-fixed] ERROR: fixed entitlements file missing at $ENTITLEMENTS" >&2; exit 1; }

echo "[install-fixed] signing app bundle (inside-out, app-sandbox only)"

# Phase 1: sign leaf Mach-O executables/dylibs (regular files only)
# Materialize find output to a temp file; fail closed on find error.
p1_list=$(mktemp)
find "$APP_SRC/Contents" -type f \( -perm +111 -o -name "*.dylib" \) \
  ! -path "$APP_SRC/Contents/MacOS/AIDash" \
  -print0 > "$p1_list" \
  || { echo "FATAL: find failed enumerating leaf executables"; exit 1; }

signed_count=0
while IFS= read -r -d '' leaf; do
    # Capture file type without a pipe — avoids pipefail/SIGPIPE
    filetype=$(/usr/bin/file -b "$leaf") || {
        echo "FATAL: /usr/bin/file failed on $leaf"; exit 1; }
    case "$filetype" in *Mach-O*) ;; *) continue ;; esac
    codesign --force --sign - --entitlements "$ENTITLEMENTS" "$leaf" \
      || { echo "FATAL: codesign failed on $leaf"; exit 1; }
    signed_count=$((signed_count + 1))
done < "$p1_list"
rm -f "$p1_list"

# Phase 2: sign nested code bundles depth-first (post-order traversal)
# Materialize find output to a temp file; fail closed on find error.
p2_list=$(mktemp)
find "$APP_SRC/Contents" -depth -type d \
  \( -name "*.xpc" -o -name "*.appex" -o -name "*.app" \) \
  -print0 > "$p2_list" \
  || { echo "FATAL: find failed enumerating nested bundles"; exit 1; }

while IFS= read -r -d '' bundle; do
    codesign --force --sign - --entitlements "$ENTITLEMENTS" "$bundle" \
      || { echo "FATAL: codesign failed on $bundle"; exit 1; }
    signed_count=$((signed_count + 1))
done < "$p2_list"
rm -f "$p2_list"

# Phase 3: sign the outer app bundle last
codesign --force --sign - --entitlements "$ENTITLEMENTS" "$APP_SRC" \
  || { echo "FATAL: codesign failed on outer app bundle"; exit 1; }

echo "[install-fixed] signed $signed_count inner target(s) + outer app bundle"

# --- Post-sign verification gate (fail-closed) --------------------------------

# 1. Deep signature integrity (covers all nested signatures)
codesign --verify --deep --strict "$APP_SRC" \
  || { echo "FATAL: codesign --verify --deep --strict failed"; exit 1; }

# Helper: capture-first entitlement check (no grep -q pipeline)
check_sandbox_entitlement() {
    local target=$1
    local ent_out
    ent_out=$(codesign -d --entitlements :- "$target" 2>&1) || {
        echo "FATAL: codesign -d failed on $target"; exit 1; }
    case "$ent_out" in
        *com.apple.security.app-sandbox*) ;;
        *) echo "FATAL: app-sandbox entitlement missing on $target"; exit 1 ;;
    esac
}

# 2. Verify app-sandbox entitlement on the main executable
check_sandbox_entitlement "$APP_SRC/Contents/MacOS/AIDash"

# 3. Verify app-sandbox entitlement on every target signed in Phases 1/2
if [ "$signed_count" -gt 0 ]; then
    # Re-enumerate leaf targets (materialized + verified find)
    v1_list=$(mktemp)
    find "$APP_SRC/Contents" -type f \( -perm +111 -o -name "*.dylib" \) \
      ! -path "$APP_SRC/Contents/MacOS/AIDash" \
      -print0 > "$v1_list" \
      || { echo "FATAL: find failed in verification (leaf)"; exit 1; }
    while IFS= read -r -d '' target; do
        filetype=$(/usr/bin/file -b "$target") || {
            echo "FATAL: /usr/bin/file failed on $target"; exit 1; }
        case "$filetype" in *Mach-O*) ;; *) continue ;; esac
        check_sandbox_entitlement "$target"
    done < "$v1_list"
    rm -f "$v1_list"

    # Re-enumerate nested bundles (materialized + verified find)
    v2_list=$(mktemp)
    find "$APP_SRC/Contents" -depth -type d \
      \( -name "*.xpc" -o -name "*.appex" -o -name "*.app" \) \
      -print0 > "$v2_list" \
      || { echo "FATAL: find failed in verification (bundles)"; exit 1; }
    while IFS= read -r -d '' target; do
        check_sandbox_entitlement "$target"
    done < "$v2_list"
    rm -f "$v2_list"
fi

echo "[install-fixed] signature verification passed"

# --- Atomic install --------------------------------------------------------
# Stop any running fixed app so we can replace the bundle cleanly.
echo "[install-fixed] stopping any running AIDash"
pkill -x AIDash 2>/dev/null || true
sleep 1

echo "[install-fixed] installing app → $APP_DST"
# Truly atomic: ditto into a sibling staging dir, then swap by rename. A failed
# copy leaves the existing install untouched instead of a half-deleted bundle.
APP_STAGE="${APP_DST}.staging.$$"
rm -rf "$APP_STAGE"
if ! ditto "$APP_SRC" "$APP_STAGE"; then
  echo "[install-fixed] ERROR: app copy failed (existing install left intact)" >&2
  rm -rf "$APP_STAGE"
  exit 1
fi
rm -rf "$APP_DST"
if ! mv "$APP_STAGE" "$APP_DST"; then
  echo "[install-fixed] ERROR: app swap failed" >&2
  rm -rf "$APP_STAGE"
  exit 1
fi

echo "[install-fixed] installing CLI → $BIN_DST"
mkdir -p "$BIN_DIR"
install -m 755 "$BIN_SRC" "$BIN_DST" || { echo "[install-fixed] ERROR: CLI install failed" >&2; exit 1; }

# --- Repoint XPC to the fixed app ------------------------------------------
# Reuse the existing recovery path: bootout stale job + drop old plist, then
# launch the fixed app so LaunchdAgentInstaller writes a fresh plist whose
# Program points at /Applications/AIDash.app and bootstraps it.
echo "[install-fixed] resetting XPC LaunchAgent"
if ! bash "$REPO_ROOT/scripts/dev/reset-xpc.sh"; then
  echo "[install-fixed] ERROR: reset-xpc.sh failed — stale job may still be registered" >&2
  exit 1
fi

echo "[install-fixed] launching fixed app to (re)register LaunchAgent"
open "$APP_DST"

# --- LaunchAgent validation -------------------------------------------------
# Wait for the LaunchAgent to come up brokered to the FIXED build. Poll for
# job loaded + plist Program == fixed exec.
FIXED_EXEC="$APP_DST/Contents/MacOS/AIDash"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
echo "[install-fixed] waiting for LaunchAgent to register on the fixed build…"
la_ok=0
prog=""
for i in $(seq 1 20); do
  sleep 1
  prog="$(/usr/libexec/PlistBuddy -c 'Print :Program' "$PLIST" 2>/dev/null)"
  if launchctl print "gui/$UID_N/$LABEL" >/dev/null 2>&1 \
     && [ "$prog" = "$FIXED_EXEC" ]; then
    la_ok=1
    break
  fi
done

if [ "$la_ok" != "1" ]; then
  echo "[install-fixed] FATAL: LaunchAgent did not register on fixed build within 20 s" >&2
  echo "    Required: job LOADED + plist Program == $FIXED_EXEC" >&2
  echo "    Observed plist Program: ${prog:-<unreadable>}" >&2
  if [ -n "$prog" ] && [ "$prog" != "$FIXED_EXEC" ]; then
    echo "    XPC is still pointed at a NON-fixed build (stale DerivedData?)." >&2
  fi
  echo "    Diagnostics:" >&2
  echo "    - launchctl print gui/$UID_N/$LABEL:" >&2
  launchctl print "gui/$UID_N/$LABEL" 2>&1 | head -5 >&2 || echo "      (job not loaded)" >&2
  echo "    - last push-error lines:" >&2
  tail -3 "$REPO_ROOT/.aidash-state/aidash-push-errors.log" 2>/dev/null >&2 || true
  exit 1
fi

echo "[install-fixed] LaunchAgent registered: Program == $FIXED_EXEC"

# --- Store-dependent self-check (ADR-003) ------------------------------------
# Two probes validate XPC operation: store-independent (schema availability)
# and store-dependent (container read under sandbox). Both use the exact
# installed CLI binary ($BIN_DST) with a synchronous /usr/bin/perl timeout
# runner — no GNU timeout, no async signals.

# run_with_timeout SECONDS STDOUT_FILE STDERR_FILE CMD [ARGS...]
# Writes child stdout/stderr to the named files.
# Returns: child exit status, or 124 on timeout.
run_with_timeout() {
    /usr/bin/perl -e '
use strict;
use warnings;
use POSIX qw(WNOHANG WIFEXITED WEXITSTATUS WIFSIGNALED WTERMSIG);
use Time::HiRes qw(time);

my $limit    = shift @ARGV or die "usage: run_with_timeout LIMIT OUT ERR CMD...\n";
my $out_file = shift @ARGV or die "missing stdout file\n";
my $err_file = shift @ARGV or die "missing stderr file\n";
@ARGV or die "missing command\n";

open(my $out_fh, ">", $out_file) or die "open $out_file: $!\n";
open(my $err_fh, ">", $err_file) or die "open $err_file: $!\n";

my $pid = fork();
defined $pid or die "fork: $!\n";

if ($pid == 0) {
    open(STDOUT, ">&", $out_fh) or die "dup stdout: $!\n";
    open(STDERR, ">&", $err_fh) or die "dup stderr: $!\n";
    exec @ARGV or die "exec $ARGV[0]: $!\n";
}

close $out_fh;
close $err_fh;

my $deadline  = time() + $limit;
my $timed_out = 0;
my $rc;

while (1) {
    my $w = waitpid($pid, WNOHANG);
    if ($w == $pid) {
        # Child exited — capture status and break
        if    (WIFEXITED($?))   { $rc = WEXITSTATUS($?); }
        elsif (WIFSIGNALED($?)) { $rc = 128 + WTERMSIG($?); }
        else                    { $rc = 255; }
        last;
    }
    if ($w == -1) {
        die "waitpid($pid, WNOHANG) returned -1 unexpectedly: $!\n";
    }
    # $w == 0: child still running
    if (time() >= $deadline) {
        # Timeout: kill the still-owned unreaped child
        kill("KILL", $pid) or die "kill $pid: $!\n";
        my $w2 = waitpid($pid, 0);
        $w2 == $pid or die "post-kill waitpid: expected $pid, got $w2: $!\n";
        $timed_out = 1;
        $rc = 124;
        last;
    }
    select(undef, undef, undef, 0.05);  # 50 ms poll interval
}

exit $rc;
' "$@"
}

# probe_fail PROBE_NAME COMMAND_STRING EXIT_CODE STDERR_FILE
probe_fail() {
    local name=$1 cmd=$2 rc=$3 err_file=$4
    echo "FATAL: $name failed"
    echo "  command: $cmd"
    echo "  exit:    $rc"
    echo "  stderr:  $(cat "$err_file" 2>/dev/null)"
    exit 1
}

# validate_json_key FILE KEY EXPECTED_VALUE
# Uses /usr/bin/plutil to check a top-level key in a JSON file.
# Returns 0 if key exists and value matches (or EXPECTED_VALUE is empty
# for existence-only check), 1 otherwise.
validate_json_key() {
    local file=$1 key=$2 expected=$3
    local val
    val=$(/usr/bin/plutil -extract "$key" raw -o - "$file" 2>/dev/null) \
      || return 1
    if [ -n "$expected" ] && [ "$val" != "$expected" ]; then
        return 1
    fi
    return 0
}

# Probe 1 — store-independent (schema availability)
echo "[install-fixed] probe 1: schema list (30 s timeout)…"
p1_cmd="$BIN_DST schema list --quiet"
p1_out=$(mktemp) p1_err=$(mktemp)
run_with_timeout 30 "$p1_out" "$p1_err" "$BIN_DST" schema list --quiet
p1_rc=$?
if [ "$p1_rc" -eq 124 ]; then
    probe_fail "probe 1 (timeout)" "$p1_cmd" "$p1_rc" "$p1_err"
fi
if [ "$p1_rc" -ne 0 ]; then
    probe_fail "probe 1" "$p1_cmd" "$p1_rc" "$p1_err"
fi
rm -f "$p1_out" "$p1_err"
echo "[install-fixed] probe 1 passed: schema list exit 0"

# Probe 2 — store-dependent (container read under sandbox)
echo "[install-fixed] probe 2: briefing get (30 s timeout)…"
p2_cmd="$BIN_DST briefing get --date today --json"
p2_out=$(mktemp) p2_err=$(mktemp)
run_with_timeout 30 "$p2_out" "$p2_err" "$BIN_DST" briefing get --date today --json
p2_rc=$?
if [ "$p2_rc" -eq 124 ]; then
    probe_fail "probe 2 (timeout)" "$p2_cmd" "$p2_rc" "$p2_err"
fi

case "$p2_rc" in
    0)
        # Must be a valid success envelope: ok=true, data present, requestId present
        if ! validate_json_key "$p2_out" "ok" "true"; then
            probe_fail "probe 2 (ok!=true)" "$p2_cmd" "$p2_rc" "$p2_err"
        fi
        if ! validate_json_key "$p2_out" "data" ""; then
            probe_fail "probe 2 (missing data)" "$p2_cmd" "$p2_rc" "$p2_err"
        fi
        if ! validate_json_key "$p2_out" "requestId" ""; then
            probe_fail "probe 2 (missing requestId)" "$p2_cmd" "$p2_rc" "$p2_err"
        fi
        ;;
    3)
        # Must be a valid briefing.not_found error envelope on STDERR:
        # ok=false, error.code=briefing.not_found, error.requestId present,
        # root requestId ABSENT (error envelopes carry requestId inside error)
        if ! validate_json_key "$p2_err" "ok" "false"; then
            probe_fail "probe 2 exit 3 (ok!=false)" "$p2_cmd" "$p2_rc" "$p2_err"
        fi
        if ! validate_json_key "$p2_err" "error.code" "briefing.not_found"; then
            probe_fail "probe 2 exit 3 (error.code mismatch)" "$p2_cmd" "$p2_rc" "$p2_err"
        fi
        if ! validate_json_key "$p2_err" "error.requestId" ""; then
            probe_fail "probe 2 exit 3 (missing error.requestId)" "$p2_cmd" "$p2_rc" "$p2_err"
        fi
        if validate_json_key "$p2_err" "requestId" ""; then
            probe_fail "probe 2 exit 3 (unexpected root requestId)" "$p2_cmd" "$p2_rc" "$p2_err"
        fi
        ;;
    *)
        probe_fail "probe 2" "$p2_cmd" "$p2_rc" "$p2_err"
        ;;
esac
rm -f "$p2_out" "$p2_err"
echo "[install-fixed] probe 2 passed: briefing get exit $p2_rc (store reachable)"

# --- Success ----------------------------------------------------------------
echo
echo "[install-fixed] done — XPC healthy, brokered to fixed build, store reachable"
echo "    app     : $APP_DST"
echo "    cli     : $BIN_DST"
echo "    plist   : $prog"
echo "    sandbox : app-sandbox entitlement verified"
echo "    probe 1 : schema list exit 0"
echo "    probe 2 : briefing get exit $p2_rc (store opened under sandbox)"
exit 0
