#!/usr/bin/env bash

set -euo pipefail

operation="${1:-}"
path="${2:-}"

cleanup() {
    [ -z "$path" ] || rm -f -- "$path"
}

case "$operation" in
    cleanup)
        cleanup
        exit 0
        ;;
    create)
        ;;
    *)
        exit 64
        ;;
esac

[ -n "${RUNNER_TEMP:-}" ] && [ -n "$path" ] || exit 64
case "$path" in
    "$RUNNER_TEMP"/*) ;;
    *) exit 64 ;;
esac

endpoint="${TELEMETRY_BLOB_ENDPOINT:-}"
sas="${TELEMETRY_BLOB_SAS:-}"
[ -n "$endpoint" ] && [ -n "$sas" ] || exit 64

case "$endpoint$sas" in
    *$'\n'*|*$'\r'*|*'$('*)
        exit 64
        ;;
esac

escape_xcconfig() {
    printf '%s' "${1//\/\//\/\$()\/}"
}

umask 077
cleanup
trap 'status=$?; if [ "$status" -ne 0 ]; then cleanup; fi' EXIT
{
    printf 'TELEMETRY_BLOB_ENDPOINT = '
    escape_xcconfig "$endpoint"
    printf '\nTELEMETRY_BLOB_SAS = '
    escape_xcconfig "$sas"
    printf '\n'
} > "$path"
chmod 0600 "$path"
trap - EXIT
