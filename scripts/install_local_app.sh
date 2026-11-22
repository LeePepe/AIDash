#!/usr/bin/env bash
# Build, install, and relaunch local macOS AIDash.app (and AIDashPreviewHost.app when present)
# from the repository root using relative script invocation (`./scripts/install_local_app.sh`).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

APPS_DIR="${AIDASH_APPLICATIONS_DIR:-$HOME/../../Applications}"
APP_DST="$APPS_DIR/AIDash.app"
PREVIEW_HOST_DST="$APPS_DIR/AIDashPreviewHost.app"
DRY_RUN=0
WITH_PREVIEW_HOST="${INSTALL_PREVIEW_HOST:-0}"

usage() {
    cat <<'EOF'
Usage: ./scripts/install_local_app.sh [--dry-run] [--with-preview-host] [--help]

Builds and installs AIDash.app (and optionally AIDashPreviewHost.app) into the
local Applications directory and relaunches the app cleanly.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --with-preview-host)
            WITH_PREVIEW_HOST=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "[install_local_app] unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [ "$DRY_RUN" -eq 1 ]; then
    echo "[install_local_app] dry-run: repo_root=$REPO_ROOT"
    echo "[install_local_app] dry-run: would run ./scripts/dev/install-fixed-build.sh -> $APP_DST"
    if [ "$WITH_PREVIEW_HOST" -eq 1 ]; then
        echo "[install_local_app] dry-run: would build/install AIDashPreviewHost -> $PREVIEW_HOST_DST"
    fi
    exit 0
fi

./scripts/dev/install-fixed-build.sh

if [ "$WITH_PREVIEW_HOST" -eq 1 ]; then
    TMP_PREVIEW_DD="$(mktemp -d "${TMPDIR:-/tmp}/aidash-preview-host.XXXXXX")"
    trap 'rm -rf "$TMP_PREVIEW_DD"' EXIT
    if [ ! -d "AIDash.xcodeproj" ]; then
        xcodegen generate
    fi
    if xcodebuild -project AIDash.xcodeproj -list 2>/dev/null | grep -q "AIDashPreviewHost"; then
        xcodebuild \
            -project AIDash.xcodeproj \
            -scheme AIDashPreviewHost \
            -configuration Debug \
            -destination 'generic/platform=macOS' \
            -derivedDataPath "$TMP_PREVIEW_DD" \
            CONFIGURATION_BUILD_DIR="$TMP_PREVIEW_DD/Products" \
            CODE_SIGNING_ALLOWED=NO \
            build
        if [ -d "$TMP_PREVIEW_DD/Products/AIDashPreviewHost.app" ]; then
            rm -rf "$PREVIEW_HOST_DST"
            ditto "$TMP_PREVIEW_DD/Products/AIDashPreviewHost.app" "$PREVIEW_HOST_DST"
            open -g "$PREVIEW_HOST_DST" 2>/dev/null || true
        fi
    elif [ -d "$APP_DST" ]; then
        rm -rf "$PREVIEW_HOST_DST"
        ditto "$APP_DST" "$PREVIEW_HOST_DST"
        open -g "$PREVIEW_HOST_DST" --args --preview-host 2>/dev/null || true
    fi
fi

echo "[install_local_app] installed and verified: $APP_DST"
