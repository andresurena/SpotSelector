#!/bin/bash
# Builds "SpotSelector.app" into ./build. Pass --install to also copy it
# to /Applications and launch it.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="SpotSelector"
APP="build/$APP_NAME.app"

# Universal binary so it runs on both Apple Silicon and Intel Macs.
BUILD_FLAGS=(-c release --arch arm64 --arch x86_64)
swift build "${BUILD_FLAGS[@]}"
BIN="$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)/SpotSelector"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/SpotSelector"
cp Resources/Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# A real signing identity keeps the "control Spotify" permission across
# rebuilds; ad-hoc signing works but macOS re-asks after every build.
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')}"
codesign --force --sign "${IDENTITY:--}" "$APP"

echo "Built $APP (signed with: ${IDENTITY:-ad-hoc})"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x SpotSelector 2>/dev/null || true
    pkill -x SpotifyQuality 2>/dev/null || true
    rm -rf "/Applications/Spotify Quality.app"
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP" "/Applications/$APP_NAME.app"
    open "/Applications/$APP_NAME.app"
    echo "Installed to /Applications and launched."
fi
