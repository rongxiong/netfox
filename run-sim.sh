#!/bin/bash
#
# run-sim.sh — Build the netfox demo, install it on a booted (or first
# available) iOS simulator and launch it.
#
# Usage:
#   ./run-sim.sh                 # build + install + launch
#   ./run-sim.sh <simulator-id>  # target a specific simulator
#

set -euo pipefail

PROJECT="netfox.xcodeproj"
SCHEME="netfox_ios_demo"
BUNDLE_ID="com.kasketis.netfox-demo-iOS"

cd "$(dirname "$0")"

# 1. Resolve the destination simulator.
UUID_RE='[0-9A-Fa-f-]{36}'

if [[ $# -ge 1 ]]; then
    DEVICE_ID="$1"
else
    DEVICE_ID="$(xcrun simctl list devices available | grep '(Booted)' | grep -oE "$UUID_RE" | head -1 || true)"
    if [[ -z "${DEVICE_ID:-}" ]]; then
        DEVICE_ID="$(xcrun simctl list devices available | grep 'iPhone' | grep -oE "$UUID_RE" | head -1 || true)"
    fi
fi

if [[ -z "${DEVICE_ID:-}" ]]; then
    echo "error: no available iOS simulator found" >&2
    exit 1
fi

echo "==> Target simulator: $DEVICE_ID"

# Boot it if needed (a no-op when already booted).
xcrun simctl bootstatus "$DEVICE_ID" -b >/dev/null 2>&1 || true

# 2. Build.
echo "==> Building $SCHEME ..."
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "id=$DEVICE_ID" \
    -quiet \
    build

# 3. Locate the built .app from the resolved build settings so DerivedData
#    paths never need to be hard-coded.
APP_PATH="$(
    xcodebuild \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -destination "id=$DEVICE_ID" \
        -showBuildSettings 2>/dev/null \
    | awk '/ BUILT_PRODUCTS_DIR =/ {dir=$0; sub(/^.*= /, "", dir)}
           / FULL_PRODUCT_NAME =/ {name=$0; sub(/^.*= /, "", name)}
           END {if (dir != "" && name != "") print dir "/" name}'
)"

if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
    echo "error: built .app not found (got: ${APP_PATH:-<empty>})" >&2
    exit 1
fi

echo "==> Installing $APP_PATH ..."
xcrun simctl install "$DEVICE_ID" "$APP_PATH"

echo "==> Launching $BUNDLE_ID ..."
xcrun simctl launch "$DEVICE_ID" "$BUNDLE_ID"

echo "==> Done."
