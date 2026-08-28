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

# bootstrap_fixed_launchagent UID_N PLIST_PATH
#
# Executes the launchctl bootstrap command with exact argv:
#   <launchctl> bootstrap gui/<uid> <plist>
#
# The launchctl binary is controlled by FIXED_LAUNCHCTL_CMD (default:
# /bin/launchctl). Tests inject a shell script fake via this variable to
# capture and assert the exact invocation without touching the real job.
#
# Returns the exit code of the launchctl command.
bootstrap_fixed_launchagent() {
    local uid_n=$1 plist_path=$2
    local cmd="${FIXED_LAUNCHCTL_CMD:-/bin/launchctl}"
    "$cmd" bootstrap "gui/$uid_n" "$plist_path"
}

# provision_fixed_launchagent PLIST_DIR JOB_LABEL MACH_SERVICE EXEC_PATH UID_N
#
# Complete provisioning seam: render → validate → atomic install → bootstrap.
# This is the single production entry point for LaunchAgent provisioning.
# Both install-fixed-build.sh and the hermetic test call this function.
#
# Injectable seams:
#   FIXED_LAUNCHCTL_CMD — launchctl binary (default /bin/launchctl)
#   PLIST_DIR — target directory (production: ~/Library/LaunchAgents;
#               test: a temp directory)
#
# Returns 0 on success, non-zero on any step failure.
provision_fixed_launchagent() {
    local plist_dir=$1 job_label=$2 mach_service=$3 exec_path=$4 uid_n=$5
    local plist_path="$plist_dir/$job_label.plist"
    local staging="${plist_path}.staging.$$"

    mkdir -p "$plist_dir" || { echo "FATAL: cannot create $plist_dir" >&2; return 1; }

    render_fixed_plist "$staging" "$job_label" "$mach_service" "$exec_path"

    if ! validate_fixed_plist "$staging" "$job_label" "$mach_service" "$exec_path"; then
        cat "$staging" >&2
        rm -f "$staging"
        return 1
    fi

    mv -f "$staging" "$plist_path" || { echo "FATAL: plist install failed" >&2; return 1; }

    bootstrap_fixed_launchagent "$uid_n" "$plist_path"
}

# validate_json_key FILE KEY EXPECTED_VALUE
#
# Checks a key in a JSON file via /usr/bin/plutil.
#
# When EXPECTED_VALUE is empty (existence-only check): uses
# `plutil -extract KEY xml1 -o /dev/null` which succeeds for any JSON value
# type (objects, arrays, scalars, nested paths). The `raw` format only works
# for scalars; the `json` format only works for top-level objects/arrays.
# `xml1` handles everything.
#
# When EXPECTED_VALUE is non-empty (scalar comparison): uses
# `plutil -extract KEY raw -o -` and compares the literal string.
#
# Returns 0 if the key exists (and value matches when expected is given),
# 1 otherwise.
validate_json_key() {
    local file=$1 key=$2 expected=$3
    if [ -z "$expected" ]; then
        # Existence-only: xml1 format handles any value type and nested paths
        /usr/bin/plutil -extract "$key" xml1 -o /dev/null "$file" 2>/dev/null
    else
        # Scalar comparison: raw format for literal string match
        local val
        val=$(/usr/bin/plutil -extract "$key" raw -o - "$file" 2>/dev/null) \
          || return 1
        [ "$val" = "$expected" ]
    fi
}

# validate_briefing_not_found_envelope FILE
#
# Production validator for the CLI's briefing.not_found error envelope.
# Required fields:
#   - ok = false
#   - error.code = briefing.not_found
#   - error.message exists and is non-empty
#   - root requestId is ABSENT (error envelopes do not carry root requestId)
#
# Optional fields (must not cause rejection):
#   - error.requestId — currently omitted by the central-catch envelope;
#     after MY-1455 restores the contract, a non-empty nested requestId
#     will be present. Both shapes must pass.
#   - Unknown additional error fields are not rejected.
#
# Returns 0 if the envelope is valid, 1 otherwise.
# Both the installer exit-3 branch and the hermetic test call this function.
validate_briefing_not_found_envelope() {
    local file=$1

    # Required: ok=false
    validate_json_key "$file" "ok" "false" || return 1

    # Required: error.code=briefing.not_found
    validate_json_key "$file" "error.code" "briefing.not_found" || return 1

    # Required: error.message exists and is non-empty
    local msg
    msg=$(/usr/bin/plutil -extract "error.message" raw -o - "$file" 2>/dev/null) || return 1
    [ -n "$msg" ] || return 1

    # Required: root requestId must be ABSENT
    if /usr/bin/plutil -extract "requestId" xml1 -o /dev/null "$file" 2>/dev/null; then
        return 1
    fi

    return 0
}
