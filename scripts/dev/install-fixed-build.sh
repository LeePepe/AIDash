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
# Signing: ad-hoc ("-"), matching the dev build that already works. No
# Distribution cert, no notarization, no App Sandbox (ENABLE_APP_SANDBOX=NO in
# Release). ad-hoc means no entitlements → CloudKit is unavailable and the app
# falls back to a local-only container (current behavior; XPC/push don't need
# CloudKit).
#
# Idempotent: safe to re-run. Each run rebuilds, reinstalls, and re-points XPC.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT" || { echo "[install-fixed] repo root not found" >&2; exit 1; }

LABEL="com.tianpli.aidash"
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

# --- Atomic install --------------------------------------------------------
# Stop any running fixed app so we can replace the bundle cleanly.
echo "[install-fixed] stopping any running AIDash"
pkill -x AIDash 2>/dev/null || true
sleep 1

echo "[install-fixed] installing app → $APP_DST"
rm -rf "$APP_DST"
ditto "$APP_SRC" "$APP_DST" || { echo "[install-fixed] ERROR: app install failed" >&2; exit 1; }

echo "[install-fixed] installing CLI → $BIN_DST"
mkdir -p "$BIN_DIR"
install -m 755 "$BIN_SRC" "$BIN_DST" || { echo "[install-fixed] ERROR: CLI install failed" >&2; exit 1; }

# --- Repoint XPC to the fixed app ------------------------------------------
# Reuse the existing recovery path: bootout stale job + drop old plist, then
# launch the fixed app so LaunchdAgentInstaller writes a fresh plist whose
# Program points at /Applications/AIDash.app and bootstraps it.
echo "[install-fixed] resetting XPC LaunchAgent"
bash "$REPO_ROOT/scripts/dev/reset-xpc.sh"

echo "[install-fixed] launching fixed app to (re)register LaunchAgent"
open "$APP_DST"

# --- Self-check ------------------------------------------------------------
# Wait for the app process, then poll the real XPC round-trip. The LaunchAgent
# install completes asynchronously in the app's init, so give it a few seconds.
echo "[install-fixed] waiting for XPC to come up…"
ok=0
for i in $(seq 1 20); do
  sleep 1
  if launchctl print "gui/$UID_N/$LABEL" >/dev/null 2>&1 \
     && "$BIN_DST" schema list --quiet >/dev/null 2>&1; then
    ok=1
    break
  fi
done

echo
if [ "$ok" = "1" ]; then
  PROG="$(/usr/libexec/PlistBuddy -c 'Print :Program' "$HOME/Library/LaunchAgents/$LABEL.plist" 2>/dev/null)"
  echo "[install-fixed] ✅ done — XPC healthy on the fixed build"
  echo "    app     : $APP_DST"
  echo "    cli     : $BIN_DST"
  echo "    plist   : $PROG"
  echo "    job     : LOADED, schema list exit 0"
  exit 0
else
  echo "[install-fixed] ❌ XPC did NOT come up on the fixed build." >&2
  echo "    Diagnostics:" >&2
  echo "    - launchctl print gui/$UID_N/$LABEL:" >&2
  launchctl print "gui/$UID_N/$LABEL" 2>&1 | head -5 >&2 || echo "      (job not loaded)" >&2
  echo "    - last push-error lines:" >&2
  tail -3 "$REPO_ROOT/.aidash-state/aidash-push-errors.log" 2>/dev/null >&2 || true
  exit 1
fi
