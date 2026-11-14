#!/bin/bash
# Build a signed Termcast.app into build/Termcast-<version>.dmg. Usage: build-dmg.sh [version]
set -euo pipefail

cd "$(dirname "$0")/.." || exit 1
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
IDENTITY="Tinycast Self-Signed"
PRODUCT_NAME="Termcast"
DERIVED="build/DerivedData"

if ! security find-identity -p codesigning | grep -q "$IDENTITY"; then
    echo "✗ '$IDENTITY' code-signing identity not found — create it once (docs/signing.md)." >&2
    exit 1
fi

echo "▸ Building signed ${PRODUCT_NAME}.app (Release)…"
xcodebuild -project Tinycast.xcodeproj -scheme Tinycast -configuration Release \
    -derivedDataPath "$DERIVED" \
    PRODUCT_NAME="$PRODUCT_NAME" \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" OTHER_CODE_SIGN_FLAGS="--timestamp=none" \
    ${1:+MARKETING_VERSION="$1"} \
    build

APP="$DERIVED/Build/Products/Release/${PRODUCT_NAME}.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="build/${PRODUCT_NAME}-${VERSION}.dmg"

echo "▸ Packaging ${DMG}"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/${PRODUCT_NAME}.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
diskutil image create from "$STAGE" --format UDZO --volumeName "$PRODUCT_NAME" "$DMG" >/dev/null

echo "✓ $DMG"