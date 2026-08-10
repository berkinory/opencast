#!/bin/bash
# Build release archives. Usage: ./build-dmg.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

IDENTITY="${DEVELOPER_ID_IDENTITY:-Developer ID Application}"
TEAM_ID="${DEVELOPMENT_TEAM:-Z66C58Z3RC}"
NOTARY_PROFILE="${NOTARY_PROFILE:-opencast-notary}"
NOTARY_AUTH="${NOTARY_AUTH:-profile}"
DISPLAY_NAME="${DISPLAY_NAME:-Opencast}"
DERIVED_DATA="${DERIVED_DATA:-build/DerivedData}"
OUTPUT_DIR="${OUTPUT_DIR:-build}"
SKIP_SIGNING="${SKIP_SIGNING:-0}"
SKIP_NOTARIZATION="${SKIP_NOTARIZATION:-0}"
VERSION="$(sed -n 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"\([^"]*\)".*/\1/p' project.yml | head -n1)"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "error: project.yml must define MARKETING_VERSION as x.y.z; got '$VERSION'" >&2
    exit 1
fi

if [[ "$SKIP_SIGNING" == "1" ]]; then
    echo "▸ Building unsigned ${DISPLAY_NAME}.app (Release)…"
    SKIP_NOTARIZATION=1
    BUILD_SETTINGS=(
        CODE_SIGNING_ALLOWED=NO
        CODE_SIGN_STYLE=Manual
    )
else
    if ! security find-identity -p codesigning | grep -q "$IDENTITY"; then
        echo "error: '$IDENTITY' code-signing identity not found — create it in the Apple Developer portal." >&2
        exit 1
    fi
    echo "▸ Building Developer ID-signed ${DISPLAY_NAME}.app (Release)…"
    BUILD_SETTINGS=(
        CODE_SIGNING_ALLOWED=YES
        CODE_SIGN_STYLE=Manual
        CODE_SIGN_IDENTITY="$IDENTITY"
        DEVELOPMENT_TEAM="$TEAM_ID"
        OTHER_CODE_SIGN_FLAGS="--timestamp"
    )
fi

BUILD_VERSION_SETTINGS=(MARKETING_VERSION="$VERSION")
if [[ -n "${BUILD_NUMBER:-}" ]]; then
    BUILD_VERSION_SETTINGS+=(CURRENT_PROJECT_VERSION="$BUILD_NUMBER")
fi

xcodebuild -project Opencast.xcodeproj -scheme Opencast -configuration Release \
    -derivedDataPath "$DERIVED_DATA" \
    "${BUILD_VERSION_SETTINGS[@]}" \
    ONLY_ACTIVE_ARCH=NO \
    "${BUILD_SETTINGS[@]}" \
    build

APP="$DERIVED_DATA/Build/Products/Release/${DISPLAY_NAME}.app"
STAGE="$(mktemp -d)"
mkdir -p "$OUTPUT_DIR"
DMG="$OUTPUT_DIR/${DISPLAY_NAME}-${VERSION}.dmg"
ARCHIVE_ZIP="$OUTPUT_DIR/${DISPLAY_NAME}-${VERSION}.zip"
RAW_DMG="$STAGE/${DISPLAY_NAME}-raw.dmg"
MOUNT_POINT="/Volumes/${DISPLAY_NAME}"
DMG_DEVICE=""

cleanup() {
    if [[ -n "$DMG_DEVICE" ]]; then
        hdiutil detach "$DMG_DEVICE" -force >/dev/null 2>&1 || true
    fi
    rm -rf "$STAGE"
}
trap cleanup EXIT

if [[ "$SKIP_SIGNING" != "1" ]]; then
    echo "▸ Re-signing Sparkle helpers…"
    bash Tools/sign-sparkle.sh "$APP" "$IDENTITY"

    BINARY="$APP/Contents/MacOS/${DISPLAY_NAME}"
    ARCHS="$(lipo -archs "$BINARY")"
    echo "▸ Release architectures: $ARCHS"
    [[ "$ARCHS" == *arm64* && "$ARCHS" == *x86_64* ]] || {
        echo "error: release binary is not universal: $ARCHS" >&2
        exit 1
    }
fi

notarize_with_api_key() {
    local key_path="$1"
    local zip_path="$2"
    local submit_json="$STAGE/notary-submit.json"
    local wait_json="$STAGE/notary-wait.json"

    if ! xcrun notarytool submit "$zip_path" \
        --key "$key_path" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" \
        --output-format json > "$submit_json" 2>&1; then
        cat "$submit_json"
        echo "error: notarytool upload failed before a submission was created" >&2
        exit 1
    fi
    cat "$submit_json"

    local submission_id
    submission_id="$(sed -nE 's/.*"id"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$submit_json" | head -n1)"
    if [[ -z "$submission_id" ]]; then
        echo "error: notarytool did not return a submission id" >&2
        exit 1
    fi
    echo "Submission ID: $submission_id"

    if ! xcrun notarytool wait "$submission_id" \
        --key "$key_path" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" \
        --timeout 25m --output-format json > "$wait_json" 2>&1; then
        cat "$wait_json"
        echo "error: notarization did not finish within 25 minutes; fetching the submission log" >&2
        xcrun notarytool log "$submission_id" \
            --key "$key_path" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" || true
        exit 1
    fi
    cat "$wait_json"

    local status
    status="$(sed -nE 's/.*"status"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$wait_json" | head -n1)"
    if [[ "$status" != "Accepted" ]]; then
        echo "error: notarization finished with status: ${status:-unknown}" >&2
        xcrun notarytool log "$submission_id" \
            --key "$key_path" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" || true
        exit 1
    fi
}

if [[ "$SKIP_NOTARIZATION" != "1" ]]; then
    codesign --verify --deep --strict --verbose=2 "$APP"
    echo "▸ Submitting app for notarization…"
    NOTARIZATION_ZIP="$STAGE/notarize.zip"
    ditto -c -k --sequesterRsrc --keepParent "$APP" "$NOTARIZATION_ZIP"

    if [[ "$NOTARY_AUTH" == "api" ]]; then
        if [[ -z "${NOTARY_KEY_ID:-}" || -z "${NOTARY_ISSUER_ID:-}" ]]; then
            echo "error: NOTARY_KEY_ID and NOTARY_ISSUER_ID are required for API-key notarization" >&2
            exit 1
        fi
        if [[ -z "${NOTARY_KEY_PATH:-}" ]]; then
            if [[ -z "${NOTARY_KEY_BASE64:-}" ]]; then
                echo "error: NOTARY_KEY_PATH or NOTARY_KEY_BASE64 is required for API-key notarization" >&2
                exit 1
            fi
            NOTARY_KEY_PATH="$STAGE/AuthKey_${NOTARY_KEY_ID}.p8"
            printf '%s' "$NOTARY_KEY_BASE64" | base64 --decode > "$NOTARY_KEY_PATH"
        fi
        [[ -f "$NOTARY_KEY_PATH" ]] || {
            echo "error: notarization key not found at '$NOTARY_KEY_PATH'" >&2
            exit 1
        }
        notarize_with_api_key "$NOTARY_KEY_PATH" "$NOTARIZATION_ZIP"
    elif [[ "$NOTARY_AUTH" == "profile" ]]; then
        xcrun notarytool submit "$NOTARIZATION_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait --timeout 1h
    else
        echo "error: NOTARY_AUTH must be 'profile' or 'api'; got '$NOTARY_AUTH'" >&2
        exit 1
    fi

    xcrun stapler staple "$APP"
    xcrun stapler validate "$APP"
else
    echo "⚠ signing or notarization skipped; do not distribute this artifact"
fi

echo "▸ Packaging ${DISPLAY_NAME} archives"
rm -f "$DMG" "$ARCHIVE_ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE_ZIP"
hdiutil create -size 200m -fs HFS+ -volname "$DISPLAY_NAME" "$RAW_DMG" >/dev/null
DMG_DEVICE="$(hdiutil attach "$RAW_DMG" -readwrite -mountpoint "$MOUNT_POINT" | awk '/\/dev\/disk/ { print $1; exit }')"
cp -R "$APP" "$MOUNT_POINT/"
ln -s /Applications "$MOUNT_POINT/Applications"
cp "$ROOT/Tools/DMG.DS_Store" "$MOUNT_POINT/.DS_Store"

sync
hdiutil detach "$DMG_DEVICE" >/dev/null
DMG_DEVICE=""
hdiutil convert "$RAW_DMG" -format UDZO -o "$DMG" >/dev/null

if [[ "$SKIP_NOTARIZATION" != "1" ]]; then
    spctl --assess --type execute --verbose=4 "$APP"
fi

echo "✓ $DMG"
echo "✓ $ARCHIVE_ZIP"
