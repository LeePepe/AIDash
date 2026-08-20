#!/bin/bash
# Sourceable helper for fixed-install LaunchAgent plist authoring and
# bootstrap. Used by both install-fixed-build.sh (production) and
# test-fixed-install-plist.sh (hermetic regression test).
#
# Do NOT execute this file directly; source it:
#   source "$(dirname "$0")/lib-fixed-install-plist.sh"

# render_fixed_plist OUTPUT_FILE JOB_LABEL MACH_SERVICE EXEC_PATH
#
# Writes the canonical LaunchAgent plist to OUTPUT_FILE with exactly 5
# top-level keys: Label, Program, MachServices, EnvironmentVariables,
# ProcessType.
#
# JOB_LABEL is the launchd job label (e.g. com.tianpli.aidash).
# MACH_SERVICE is the XPC service name brokered by launchd
# (e.g. com.tianpli.aidash.xpc.v1). These are intentionally different:
# the job label identifies the launchd job; the mach service name is what
# the CLI connects to via NSXPCConnection.
render_fixed_plist() {
    local output_file=$1 job_label=$2 mach_service=$3 exec_path=$4
    cat > "$output_file" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$job_label</string>
    <key>Program</key>
    <string>$exec_path</string>
    <key>MachServices</key>
    <dict>
        <key>$mach_service</key>
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
}

# validate_fixed_plist PLIST_FILE JOB_LABEL MACH_SERVICE EXEC_PATH
#
# Validates syntax (plutil -lint) and shape (5 required keys with correct
# values). JOB_LABEL and MACH_SERVICE are validated separately — Label must
# equal JOB_LABEL, MachServices must contain MACH_SERVICE (not JOB_LABEL).
# Prints diagnostics to stderr on failure.
# Returns 0 if valid, 1 if any check fails.
validate_fixed_plist() {
    local plist_file=$1 job_label=$2 mach_service=$3 exec_path=$4
    local ok=1

    # Syntax check
    if ! /usr/bin/plutil -lint "$plist_file" >/dev/null 2>&1; then
        echo "FATAL: generated plist failed plutil -lint" >&2
        return 1
    fi

    local _pv
    _pv() { /usr/libexec/PlistBuddy -c "Print :$1" "$plist_file" 2>/dev/null; }

    local v_label v_program v_mach v_env v_ptype
    v_label="$(_pv Label)"
    v_program="$(_pv Program)"
    v_mach="$(_pv "MachServices:$mach_service")"
    v_env="$(_pv "EnvironmentVariables:AIDASH_XPC_AGENT")"
    v_ptype="$(_pv ProcessType)"

    [ "$v_label"   = "$job_label" ]  || { echo "FATAL: plist Label mismatch: got '$v_label', expected '$job_label'" >&2; ok=0; }
    [ "$v_program" = "$exec_path" ]  || { echo "FATAL: plist Program mismatch: got '$v_program'" >&2; ok=0; }
    [ "$v_mach"    = "true" ]        || { echo "FATAL: plist MachServices.$mach_service mismatch: got '$v_mach'" >&2; ok=0; }
    [ "$v_env"     = "1" ]           || { echo "FATAL: plist EnvironmentVariables.AIDASH_XPC_AGENT mismatch: got '$v_env'" >&2; ok=0; }
    [ "$v_ptype"   = "Interactive" ] || { echo "FATAL: plist ProcessType mismatch: got '$v_ptype'" >&2; ok=0; }

    [ "$ok" = "1" ] && return 0 || return 1
}

# bootstrap_command_args UID_N PLIST_PATH
#
# Returns the exact arguments that should be passed to `launchctl bootstrap`.
# Separated from execution so tests can verify args without calling launchctl.
bootstrap_command_args() {
    local uid_n=$1 plist_path=$2
    echo "gui/$uid_n" "$plist_path"
}
