#!/bin/bash

# Builds a distributable (or, with --adhoc, a local) release DMG.
#
# Distribution builds require a Developer ID Application certificate and
# notarization credentials. The script signs nested code inside-out (never with
# `codesign --deep`), verifies the hardened runtime, submits the app and DMG to
# Apple's notary service, staples the tickets and checks the result with
# `spctl`.
#
# Usage:
#   ./build_release.sh --adhoc        # local ad-hoc build, not notarized
#   ./build_release.sh                # Developer ID build + notarization
#
# Environment:
#   DEVELOPER_ID_APPLICATION   Signing identity name/SHA-1 (default: first
#                              "Developer ID Application" identity in Keychain)
#   NOTARYTOOL_PROFILE         Keychain profile stored with
#                              `xcrun notarytool store-credentials`
#   -- or --
#   NOTARYTOOL_APPLE_ID        Apple ID for notarization
#   NOTARYTOOL_PASSWORD        App-specific password
#   NOTARYTOOL_TEAM_ID         Apple Developer team ID
#   -- or --
#   NOTARYTOOL_KEY             Path to an App Store Connect API key (.p8)
#   NOTARYTOOL_KEY_ID          Key ID
#   NOTARYTOOL_ISSUER          Issuer ID

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_PATH="$ROOT/build/Build/Products/Release/mattermost.client.app"
APP_VERSION="$("$ROOT/version.sh" --full)"
ARTIFACT_DIR="$ROOT/build/Build/Products/Release"
DMG_PATH="$ARTIFACT_DIR/mattermost.client-${APP_VERSION}.dmg"
ENTITLEMENTS="$ROOT/mattermost.client/mattermost_client.entitlements"

ADHOC=0
for arg in "$@"; do
    case "$arg" in
        --adhoc)
            ADHOC=1
            ;;
        -h|--help)
            sed -n '2,33p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "Unknown argument: $arg" >&2
            exit 2
            ;;
    esac
done

fail() {
    echo "Error: $*" >&2
    exit 1
}

notary_args() {
    local args=()
    if [ -n "${NOTARYTOOL_PROFILE:-}" ]; then
        args+=(--keychain-profile "$NOTARYTOOL_PROFILE")
    elif [ -n "${NOTARYTOOL_KEY:-}" ] && [ -n "${NOTARYTOOL_KEY_ID:-}" ] && [ -n "${NOTARYTOOL_ISSUER:-}" ]; then
        args+=(--key "$NOTARYTOOL_KEY" --key-id "$NOTARYTOOL_KEY_ID" --issuer "$NOTARYTOOL_ISSUER")
    elif [ -n "${NOTARYTOOL_APPLE_ID:-}" ] && [ -n "${NOTARYTOOL_PASSWORD:-}" ] && [ -n "${NOTARYTOOL_TEAM_ID:-}" ]; then
        args+=(--apple-id "$NOTARYTOOL_APPLE_ID" --password "$NOTARYTOOL_PASSWORD" --team-id "$NOTARYTOOL_TEAM_ID")
    else
        fail "no notarization credentials configured (set NOTARYTOOL_PROFILE or the Apple ID/API-key variables; use --adhoc for a local build)"
    fi
    printf '%s\n' "${args[@]}"
}

sign_nested_code() {
    local identity=$1
    local app=$2

    # Sign the deepest bundles first. `--deep` is intentionally not used: Apple
    # documents inside-out signing as the only reliable replacement.
    local frameworks="$app/Contents/Frameworks"
    if [ -d "$frameworks" ]; then
        while IFS= read -r -d '' bundle; do
            codesign --force --timestamp --options runtime --sign "$identity" "$bundle"
        done < <(find "$frameworks" -depth -type d \( -name '*.framework' -o -name '*.app' -o -name '*.xpc' \) -print0)
        while IFS= read -r -d '' binary; do
            codesign --force --timestamp --options runtime --sign "$identity" "$binary"
        done < <(find "$frameworks" -type f \( -name '*.dylib' -o -name '*.so' \) -print0)
    fi

    codesign --force --timestamp --options runtime \
        --entitlements "$ENTITLEMENTS" --sign "$identity" "$app"
}

notarize_and_staple() {
    local path=$1
    local label=$2
    local args=()
    local line

    while IFS= read -r line; do
        args+=("$line")
    done < <(notary_args)

    echo "Submitting $label to Apple notary service..."
    xcrun notarytool submit "$path" "${args[@]}" --wait
    xcrun stapler staple "$path"
    xcrun stapler validate "$path"
}

if [ "$ADHOC" -eq 0 ]; then
    IDENTITY="${DEVELOPER_ID_APPLICATION:-}"
    if [ -z "$IDENTITY" ]; then
        IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null |
            sed -n 's/.*"\(Developer ID Application: [^"]*\)"/\1/p' | head -1)"
    fi
    [ -n "$IDENTITY" ] || fail "no Developer ID Application identity found; install the certificate or pass DEVELOPER_ID_APPLICATION (use --adhoc for a local build)"

    # Fail before the expensive build when notarization credentials are absent.
    notary_args >/dev/null
fi

echo "Building mattermost.client ${APP_VERSION} (Release, universal)..."
rm -rf "$APP_PATH"
xcodebuild -project "$ROOT/mattermost.client.xcodeproj" -scheme mattermost.client \
    -derivedDataPath "$ROOT/build" -configuration Release \
    MARKETING_VERSION="$APP_VERSION" \
    ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
    build

[ -d "$APP_PATH" ] || fail ".app bundle not found at $APP_PATH"

ARCHS="$(lipo -archs "$APP_PATH/Contents/MacOS/mattermost.client")"
echo "Built architectures: $ARCHS"
if ! printf '%s\n' "$ARCHS" | tr ' ' '\n' | grep -qx 'arm64' ||
    ! printf '%s\n' "$ARCHS" | tr ' ' '\n' | grep -qx 'x86_64'; then
    fail "release binary is not universal (got: $ARCHS)"
fi

if [ "$ADHOC" -eq 1 ]; then
    echo "Signing ad-hoc (local build; Gatekeeper will not accept it on another Mac)..."
    sign_nested_code "-" "$APP_PATH"
    codesign --verify --deep --strict --verbose=2 "$APP_PATH"
else
    echo "Signing with: $IDENTITY"
    sign_nested_code "$IDENTITY" "$APP_PATH"
    codesign --verify --strict --verbose=2 "$APP_PATH"
    echo "Checking hardened runtime..."
    codesign -d --verbose=4 "$APP_PATH" 2>&1 | grep -q "flags=.*runtime" ||
        fail "the signed app does not have the hardened runtime flag"

    ZIP_PATH="$ARTIFACT_DIR/mattermost.client-${APP_VERSION}.zip"
    rm -f "$ZIP_PATH"
    ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
    notarize_and_staple "$ZIP_PATH" "app"
    rm -f "$ZIP_PATH"
fi

echo "Creating DMG..."
rm -f "$DMG_PATH"
hdiutil create -volname "mattermost.client" -srcfolder "$APP_PATH" -ov -format UDZO "$DMG_PATH"

if [ "$ADHOC" -eq 0 ]; then
    echo "Signing and notarizing DMG..."
    codesign --force --timestamp --sign "$IDENTITY" "$DMG_PATH"
    notarize_and_staple "$DMG_PATH" "DMG"

    echo "Verifying Gatekeeper assessment..."
    spctl --assess --type execute --verbose=2 "$APP_PATH"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_PATH"
fi

CHECKSUM="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
printf '%s  %s\n' "$CHECKSUM" "$(basename "$DMG_PATH")" > "$DMG_PATH.sha256"

if [ -f "$ROOT/tools/generate_appcast.py" ]; then
    echo "Updating appcast.xml..."
    python3 "$ROOT/tools/generate_appcast.py" \
        --appcast "$ROOT/appcast.xml" \
        --version "$APP_VERSION" \
        --dmg "$DMG_PATH" \
        --sha256 "$CHECKSUM" || true
fi

echo ""
echo "Build succeeded!"
echo "  DMG:      $DMG_PATH"
echo "  SHA-256:  $CHECKSUM"
if [ "$ADHOC" -eq 1 ]; then
    echo "  Signed:   ad-hoc (not for distribution)"
else
    echo "  Signed:   $IDENTITY (hardened runtime, notarized, stapled)"
fi
