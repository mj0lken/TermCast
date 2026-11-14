#!/bin/bash
# Build, verify, publish a GitHub Release, and bump mj0lken/homebrew-tap.
# Usage: ./Scripts/publish-release.sh <version> [stable|beta] [--no-tap]
set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

REPO="mj0lken/TermCast"
TAP_REPO="${HOMEBREW_TAP_REPO:-mj0lken/homebrew-tap}"
VERSION=""
CHANNEL="stable"
UPDATE_TAP=1

for arg in "$@"; do
    case "$arg" in
        stable|beta) CHANNEL="$arg" ;;
        --no-tap) UPDATE_TAP=0 ;;
        -h|--help)
            echo "Usage: ./Scripts/publish-release.sh <version> [stable|beta] [--no-tap]"
            echo "  Example: ./Scripts/publish-release.sh 0.1.1"
            echo "  Example: ./Scripts/publish-release.sh 0.2.0 beta"
            exit 0
            ;;
        -*)
            echo "✗ Unknown option: $arg" >&2
            exit 2
            ;;
        *)
            if [ -z "$VERSION" ]; then
                VERSION="$arg"
            else
                echo "✗ Unexpected argument: $arg" >&2
                exit 2
            fi
            ;;
    esac
done

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "✗ Pass a clean base semver (MAJOR.MINOR.PATCH), e.g.: ./Scripts/publish-release.sh 0.1.1" >&2
    exit 2
fi

if [ -n "$(git status --porcelain)" ]; then
    echo "✗ Working tree has uncommitted changes. Commit and push to main before releasing." >&2
    exit 1
fi

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [ "$BRANCH" != "main" ]; then
    echo "✗ Releases must be cut from 'main' (currently on '$BRANCH')." >&2
    exit 1
fi

git fetch origin main --quiet
LOCAL_SHA="$(git rev-parse HEAD)"
REMOTE_SHA="$(git rev-parse origin/main)"
if [ "$LOCAL_SHA" != "$REMOTE_SHA" ]; then
    echo "✗ Local main ($LOCAL_SHA) does not match origin/main ($REMOTE_SHA). Pull or push first." >&2
    exit 1
fi

./Scripts/check-migrations.sh
if grep -rln 'import AppKit\|import SwiftUI\|import Cocoa' Tinycast/Features/*/Model/ >/dev/null; then
    echo "✗ Model/ layer imports AppKit/SwiftUI/Cocoa." >&2
    exit 1
fi

if [ -z "${DEVELOPER_DIR:-}" ]; then
    XCODE_PATH="$(find -E /Applications -maxdepth 1 -type d -regex '.*/Xcode_27(\.[0-9]+)*\.app' | sort -V | tail -n1 || true)"
    if [ -z "$XCODE_PATH" ] && [ -d /Applications/Xcode.app ]; then
        XCODE_PATH="/Applications/Xcode.app"
    fi
    export DEVELOPER_DIR="${XCODE_PATH:?No Xcode installation found in /Applications}/Contents/Developer"
fi

SDK_MAJOR="$(xcrun --sdk macosx --show-sdk-version 2>/dev/null | cut -d. -f1 || echo 0)"
if [ "${SDK_MAJOR:-0}" -lt 27 ]; then
    echo "✗ Xcode 27+ SDK required (found macOS SDK ${SDK_MAJOR} in $DEVELOPER_DIR)." >&2
    exit 1
fi

IDENTITY="${SIGNING_IDENTITY:-Tinycast Self-Signed}"
if ! security find-identity -p codesigning | grep -Fq "$IDENTITY"; then
    echo "✗ Code-signing identity '$IDENTITY' not found in Keychain (see docs/signing.md)." >&2
    exit 1
fi

NOTARIZE=0
TEAM="${DEVELOPMENT_TEAM:-}"
SIGN_FLAGS=(--timestamp=none)
if [[ "$IDENTITY" == Developer\ ID\ Application:* ]]; then
    if [ -z "$TEAM" ]; then
        TEAM="$(printf '%s\n' "$IDENTITY" | sed -n 's/.*(\([A-Z0-9]\{10\}\))$/\1/p')"
    fi
    SIGN_FLAGS=(--timestamp)
    if [ -n "${NOTARY_KEY_P8_BASE64:-}" ] && [ -n "${NOTARY_KEY_ID:-}" ] &&
       [ -n "${NOTARY_ISSUER_ID:-}" ] && [ -n "${UPDATE_SIGNING_KEY:-}" ]; then
        NOTARIZE=1
    fi
fi

if [ "$CHANNEL" = "beta" ]; then
    LAST_BETA="$(gh release list --repo "$REPO" --limit 100 --json tagName --jq \
        "[.[].tagName | select(startswith(\"v${VERSION}-beta.\")) | split(\"-beta.\")[1] | tonumber] | max // 0")"
    NEXT_BETA=$((LAST_BETA + 1))
    FULL_VERSION="${VERSION}-beta.${NEXT_BETA}"
    DISPLAY_NAME="Termcast Beta"
    BUNDLE_ID="com.mj0lken.termcast.beta"
    CASK="termcast@beta"
    PRERELEASE="true"
else
    FULL_VERSION="$VERSION"
    DISPLAY_NAME="Termcast"
    BUNDLE_ID="com.mj0lken.termcast"
    CASK="termcast"
    PRERELEASE="false"
fi

TAG="v${FULL_VERSION}"
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    echo "✗ Release $TAG already exists on $REPO." >&2
    exit 1
fi

BUILD_NUMBER="$(git rev-list --count HEAD)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/dist"

build_and_package() {
    local variant="$1"
    local archs="$2"
    local dmg_out="$3"
    local zip_out="$4"
    local derived="$WORK/DerivedData-${variant}"

    echo "▸ Building ${DISPLAY_NAME} ${FULL_VERSION} (${variant}: ${archs})…"
    xcodebuild -project Tinycast.xcodeproj -scheme Tinycast -configuration Release \
        -derivedDataPath "$derived" \
        ARCHS="$archs" ONLY_ACTIVE_ARCH=NO \
        CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" DEVELOPMENT_TEAM="$TEAM" \
        OTHER_CODE_SIGN_FLAGS="${SIGN_FLAGS[*]}" \
        PRODUCT_NAME="$DISPLAY_NAME" TINYCAST_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
        MARKETING_VERSION="$FULL_VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
        -quiet build

    local app="$derived/Build/Products/Release/${DISPLAY_NAME}.app"
    for bin in "$app/Contents/MacOS/${DISPLAY_NAME}" \
               "$app/Contents/Helpers/ClipboardTextHelper" \
               "$app/Contents/Helpers/FileIndexHelper" \
               "$app/Contents/Helpers/Tinycast Dictation.app/Contents/MacOS/Tinycast Dictation"; do
        local slices
        slices="$(lipo -archs "$bin")"
        for expected in $archs; do
            case " $slices " in
                *" $expected "*) ;;
                *) echo "✗ ${bin##*/}: missing slice '$expected' (found '$slices')" >&2; exit 1 ;;
            esac
        done
    done
    codesign --verify --deep --strict "$app"

    if [ "$NOTARIZE" -eq 1 ]; then
        ./Scripts/verify-signature.sh "$app"
        SIGNING_IDENTITY="$IDENTITY" ./Scripts/package-release.sh "$app" "$dmg_out" "$zip_out"
    else
        local stage="$WORK/stage-${variant}"
        mkdir -p "$stage"
        ditto "$app" "$stage/${DISPLAY_NAME}.app"
        ln -s /Applications "$stage/Applications"
        if [ -f "$app/Contents/Resources/tinycast.icns" ]; then
            cp "$app/Contents/Resources/tinycast.icns" "$stage/.VolumeIcon.icns"
            xcrun SetFile -a C "$stage"
        fi
        diskutil image create from "$stage" --format UDZO --volumeName "$DISPLAY_NAME" "$dmg_out" >/dev/null
        codesign -s "$IDENTITY" "${SIGN_FLAGS[@]}" "$dmg_out"
        ditto -c -k --keepParent --sequesterRsrc "$app" "$zip_out"
    fi
    echo "✓ Packaged $(basename "$dmg_out") + $(basename "$zip_out")"
}

THIN_DMG="$WORK/dist/Termcast-${FULL_VERSION}.dmg"
THIN_ZIP="$WORK/dist/Termcast-${FULL_VERSION}.zip"
build_and_package "arm64" "arm64" "$THIN_DMG" "$THIN_ZIP"

if [ "$CHANNEL" = "stable" ]; then
    UNI_DMG="$WORK/dist/Termcast-Universal-${FULL_VERSION}.dmg"
    UNI_ZIP="$WORK/dist/Termcast-Universal-${FULL_VERSION}.zip"
    build_and_package "universal" "arm64 x86_64" "$UNI_DMG" "$UNI_ZIP"
fi

REPO="$REPO" CHANNEL="$CHANNEL" TAG="$TAG" SHA="$LOCAL_SHA" VERSION="$FULL_VERSION" \
    DISPLAY_NAME="$DISPLAY_NAME" BUNDLE_ID="$BUNDLE_ID" CASK="$CASK" TAP_REPO="$TAP_REPO" \
    ./Scripts/release-notes.sh "$WORK/notes.md" "$WORK/discord.md"

if [ "$NOTARIZE" -eq 0 ]; then
    cat >> "$WORK/notes.md" <<'EOF'

> **Note:** Termcast isn't notarized by Apple yet. On first launch, if macOS blocks it, click **Done**, open **System Settings → Privacy & Security**, and click **Open Anyway** (only needed once).
EOF
fi

CREATE_ARGS=(--repo "$REPO" --target "$LOCAL_SHA" --title "${DISPLAY_NAME} ${FULL_VERSION}" --notes-file "$WORK/notes.md")
if [ "$PRERELEASE" = "true" ]; then
    CREATE_ARGS+=(--prerelease)
fi
THIN_ASSETS=("$THIN_DMG" "$THIN_ZIP")
[ -f "${THIN_ZIP}.sig" ] && THIN_ASSETS+=("${THIN_ZIP}.sig")

echo "▸ Publishing GitHub Release ${TAG}…"
gh release create "$TAG" "${CREATE_ARGS[@]}" "${THIN_ASSETS[@]}"

if [ "$CHANNEL" = "stable" ]; then
    UNI_ASSETS=("$UNI_DMG" "$UNI_ZIP")
    [ -f "${UNI_ZIP}.sig" ] && UNI_ASSETS+=("${UNI_ZIP}.sig")
    gh release upload "$TAG" --repo "$REPO" "${UNI_ASSETS[@]}"
fi

if [ "$CHANNEL" = "stable" ] && [ "$UPDATE_TAP" -eq 1 ]; then
    echo "▸ Updating ${TAP_REPO} (Casks/termcast.rb)…"
    ARM_SHA="$(shasum -a 256 "$THIN_DMG" | awk '{print $1}')"
    INTEL_SHA="$(shasum -a 256 "$UNI_DMG" | awk '{print $1}')"
    gh repo clone "$TAP_REPO" "$WORK/tap" -- --depth 1 --quiet
    CASK_FILE="$WORK/tap/Casks/termcast.rb"
    sed -i '' -E "s|^  version \".*\"|  version \"${FULL_VERSION}\"|" "$CASK_FILE"
    sed -i '' -E "s|^(  sha256 arm:[[:space:]]+)\"[0-9a-f]+\"|\\1\"${ARM_SHA}\"|" "$CASK_FILE"
    sed -i '' -E "s|^(         intel:[[:space:]]+)\"[0-9a-f]+\"|\\1\"${INTEL_SHA}\"|" "$CASK_FILE"
    ruby -c "$CASK_FILE" >/dev/null
    git -C "$WORK/tap" add Casks/termcast.rb
    if ! git -C "$WORK/tap" diff --cached --quiet; then
        git -C "$WORK/tap" commit -m "termcast ${FULL_VERSION}" --quiet
        git -C "$WORK/tap" push origin HEAD --quiet
        echo "✓ Updated ${TAP_REPO} Casks/termcast.rb -> ${FULL_VERSION}"
    fi
fi

echo "✓ Released ${DISPLAY_NAME} ${FULL_VERSION}: https://github.com/${REPO}/releases/tag/${TAG}"
