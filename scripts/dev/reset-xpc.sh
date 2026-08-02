#!/bin/bash
# Reset AIDash's XPC LaunchAgent to a clean slate.
#
# Use when the mach service is wedged (CLI hangs / "app_unavailable") or after
# switching away from the old SMAppService registration. Boots out any launchd
# job for the agent and removes the installer-owned plist; the next app launch
# re-installs a fresh one pointing at the current build.
set -uo pipefail
UID_N="$(id -u)"
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

echo "[reset-xpc] bootout gui/$UID_N/$LABEL"
launchctl bootout "gui/$UID_N/$LABEL" 2>/dev/null || true

PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
if [ -f "$PLIST" ]; then
  echo "[reset-xpc] removing $PLIST"
  rm -f "$PLIST"
fi

echo "[reset-xpc] done — relaunch AIDash to reinstall the LaunchAgent for the current build."
