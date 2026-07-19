#!/bin/bash
# Reset AIDash's XPC LaunchAgent to a clean slate.
#
# Use when the mach service is wedged (CLI hangs / "app_unavailable") or after
# switching away from the old SMAppService registration. Boots out any launchd
# job for the agent and removes the installer-owned plist; the next app launch
# re-installs a fresh one pointing at the current build.
set -uo pipefail
UID_N="$(id -u)"
LABEL="com.tianpli.aidash"

echo "[reset-xpc] bootout gui/$UID_N/$LABEL"
launchctl bootout "gui/$UID_N/$LABEL" 2>/dev/null || true

PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
if [ -f "$PLIST" ]; then
  echo "[reset-xpc] removing $PLIST"
  rm -f "$PLIST"
fi

echo "[reset-xpc] done — relaunch AIDash to reinstall the LaunchAgent for the current build."
