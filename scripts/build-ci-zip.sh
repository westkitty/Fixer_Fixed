#!/usr/bin/env bash
set -euo pipefail

APP_NAME="1132 Fixer"
EXECUTABLE_NAME="1132 Fixer"
TARGET_NAME="1132Fixer"
BUNDLE_ID="${BUNDLE_ID:-com.1132fixer.1132-Fixer}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_FILE="$ROOT_DIR/VERSION"
MIN_MACOS_FILE="$ROOT_DIR/MIN_MACOS_VERSION"
DIST_DIR="$ROOT_DIR/dist"
ENTITLEMENTS_FILE="$ROOT_DIR/Sources/1132Fixer/1132Fixer.entitlements"
TEMP_BUILD_ROOT="$ROOT_DIR/.build/ci-release"
ARM64_BUILD_DIR="$TEMP_BUILD_ROOT/arm64"
X64_BUILD_DIR="$TEMP_BUILD_ROOT/x86_64"
UNIVERSAL_DIR="$TEMP_BUILD_ROOT/merged"
APP_BUNDLE_DIR="$DIST_DIR/$APP_NAME.app"
SCAN_SCRIPT="$ROOT_DIR/scripts/scan-release-artifact.sh"

APP_VERSION="${APP_VERSION:-}"
APP_BUILD="${APP_BUILD:-1}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
NOTARIZE="${NOTARIZE:-0}"
APPLE_ID="${APPLE_ID:-}"
APPLE_PASSWORD="${APPLE_PASSWORD:-}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-}"
APPLE_CERTIFICATE="${APPLE_CERTIFICATE:-}"
APPLE_CERTIFICATE_PASSWORD="${APPLE_CERTIFICATE_PASSWORD:-}"

MIN_MACOS="${MIN_MACOS:-}"
if [[ -z "$MIN_MACOS" && -f "$MIN_MACOS_FILE" ]]; then
  MIN_MACOS="$(tr -d '[:space:]' < "$MIN_MACOS_FILE")"
fi
if [[ -z "$MIN_MACOS" ]]; then
  echo "MIN_MACOS is empty. Set MIN_MACOS or populate $MIN_MACOS_FILE." >&2
  exit 1
fi

if [[ -z "$APP_VERSION" && -f "$VERSION_FILE" ]]; then
  APP_VERSION="$(tr -d '\n\r' < "$VERSION_FILE")"
fi
if [[ -z "$APP_VERSION" ]]; then
  echo "APP_VERSION is empty. Set APP_VERSION or populate $VERSION_FILE." >&2
  exit 1
fi

decode_base64_to_file() {
  local destination="$1"

  if printf '%s' "$APPLE_CERTIFICATE" | base64 --decode > "$destination" 2>/dev/null; then
    return 0
  fi

  if printf '%s' "$APPLE_CERTIFICATE" | base64 -D > "$destination" 2>/dev/null; then
    return 0
  fi

  echo "Failed to decode APPLE_CERTIFICATE." >&2
  exit 1
}

CERTIFICATE_P12_FILE=""
KEYCHAIN_PATH=""
KEYCHAIN_PASSWORD=""
SIGN_IDENTITY_HASH=""
ORIGINAL_KEYCHAINS=()
cleanup_build_resources() {
  if [[ -n "$CERTIFICATE_P12_FILE" && -f "$CERTIFICATE_P12_FILE" ]]; then
    rm -f "$CERTIFICATE_P12_FILE"
  fi
  if [[ "${#ORIGINAL_KEYCHAINS[@]}" -gt 0 ]]; then
    security list-keychains -d user -s "${ORIGINAL_KEYCHAINS[@]}" >/dev/null 2>&1 || true
  fi
  if [[ -n "$KEYCHAIN_PATH" && -f "$KEYCHAIN_PATH" ]]; then
    security delete-keychain "$KEYCHAIN_PATH" >/dev/null 2>&1 || true
  fi
}
trap cleanup_build_resources EXIT

artifact_label="unsigned"
if [[ -n "$SIGN_IDENTITY" || ( -n "$APPLE_CERTIFICATE" && -n "$APPLE_CERTIFICATE_PASSWORD" ) ]]; then
  artifact_label="signed"
fi
ZIP_PATH="$DIST_DIR/1132.Fixer-v$APP_VERSION-local-safe-ci-$artifact_label.zip"
ZIP_BASENAME="$(basename "$ZIP_PATH")"

rm -rf "$DIST_DIR" "$TEMP_BUILD_ROOT"
mkdir -p "$DIST_DIR" "$UNIVERSAL_DIR"

if [[ "$artifact_label" == "signed" ]]; then
  if [[ -z "$SIGN_IDENTITY" ]]; then
    CERTIFICATE_P12_FILE="$(mktemp -t fixer-signing-certificate.XXXXXX.p12)"
    decode_base64_to_file "$CERTIFICATE_P12_FILE"

    KEYCHAIN_PATH="$TEMP_BUILD_ROOT/build-signing.keychain-db"
    KEYCHAIN_PASSWORD="$(uuidgen | tr -d '-')"
    KEYCHAIN_PASSWORD="${KEYCHAIN_PASSWORD:0:32}"

    echo "==> Importing signing certificate into temporary keychain"
    security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
    security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
    security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
    while IFS= read -r existing_keychain; do
      existing_keychain="${existing_keychain//\"/}"
      [[ -n "$existing_keychain" ]] && ORIGINAL_KEYCHAINS+=("$existing_keychain")
    done < <(security list-keychains -d user)
    security import "$CERTIFICATE_P12_FILE" \
      -f pkcs12 \
      -k "$KEYCHAIN_PATH" \
      -P "$APPLE_CERTIFICATE_PASSWORD" \
      -T /usr/bin/codesign \
      -T /usr/bin/security >/dev/null
    security list-keychains -d user -s "$KEYCHAIN_PATH" "${ORIGINAL_KEYCHAINS[@]}" >/dev/null
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" >/dev/null

    SIGN_IDENTITY_HASH="$(security find-identity -v -p codesigning "$KEYCHAIN_PATH" | awk '/Developer ID Application: / { print $2; exit }')"
    SIGN_IDENTITY="$(security find-identity -v -p codesigning "$KEYCHAIN_PATH" | awk -F'"' '/Developer ID Application: / { print $2; exit }')"
  fi

  if [[ -z "$SIGN_IDENTITY" ]]; then
    echo "No Developer ID Application identity available for signed build." >&2
    exit 1
  fi
else
  SIGN_IDENTITY="-"
  NOTARIZE=0
fi

echo "==> Building arm64 release binary"
swift build -c release --arch arm64 --scratch-path "$ARM64_BUILD_DIR" \
  -Xswiftc -debug-prefix-map -Xswiftc "$ROOT_DIR=/src"

echo "==> Building x86_64 release binary"
swift build -c release --arch x86_64 --scratch-path "$X64_BUILD_DIR" \
  -Xswiftc -debug-prefix-map -Xswiftc "$ROOT_DIR=/src"

ARM64_BIN="$ARM64_BUILD_DIR/release/$EXECUTABLE_NAME"
X64_BIN="$X64_BUILD_DIR/release/$EXECUTABLE_NAME"
UNIVERSAL_BIN="$UNIVERSAL_DIR/$EXECUTABLE_NAME"
ARM64_RELEASE_DIR="$(dirname "$ARM64_BIN")"
X64_RELEASE_DIR="$(dirname "$X64_BIN")"
EXPECTED_RESOURCE_BUNDLE="${EXECUTABLE_NAME}_${TARGET_NAME}.bundle"
SOURCE_INFO_PLIST="$ROOT_DIR/Sources/1132Fixer/Info.plist"
SOURCE_APP_ICON="$ROOT_DIR/Sources/1132Fixer/Resources/AppIcon.png"

[[ -f "$ARM64_BIN" ]] || { echo "arm64 binary not found: $ARM64_BIN" >&2; exit 1; }
[[ -f "$X64_BIN" ]] || { echo "x86_64 binary not found: $X64_BIN" >&2; exit 1; }
[[ -f "$SOURCE_INFO_PLIST" ]] || { echo "Missing Info.plist: $SOURCE_INFO_PLIST" >&2; exit 1; }
[[ -f "$ENTITLEMENTS_FILE" ]] || { echo "Missing entitlements file: $ENTITLEMENTS_FILE" >&2; exit 1; }

echo "==> Creating universal binary"
lipo -create -output "$UNIVERSAL_BIN" "$ARM64_BIN" "$X64_BIN"
strip -S -x "$UNIVERSAL_BIN" || true

mkdir -p "$APP_BUNDLE_DIR/Contents/MacOS" "$APP_BUNDLE_DIR/Contents/Resources"
cp "$UNIVERSAL_BIN" "$APP_BUNDLE_DIR/Contents/MacOS/$EXECUTABLE_NAME"
chmod +x "$APP_BUNDLE_DIR/Contents/MacOS/$EXECUTABLE_NAME"
cp "$SOURCE_INFO_PLIST" "$APP_BUNDLE_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $EXECUTABLE_NAME" "$APP_BUNDLE_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP_BUNDLE_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $APP_NAME" "$APP_BUNDLE_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$APP_BUNDLE_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $APP_BUILD" "$APP_BUNDLE_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion $MIN_MACOS" "$APP_BUNDLE_DIR/Contents/Info.plist"

if [[ -d "$ARM64_RELEASE_DIR/$EXPECTED_RESOURCE_BUNDLE" ]]; then
  [[ -d "$X64_RELEASE_DIR/$EXPECTED_RESOURCE_BUNDLE" ]] || {
    echo "x86_64 build is missing resource bundle present in arm64 build: $EXPECTED_RESOURCE_BUNDLE" >&2
    exit 1
  }
  cp -R "$ARM64_RELEASE_DIR/$EXPECTED_RESOURCE_BUNDLE" "$APP_BUNDLE_DIR/Contents/Resources/"
fi

if [[ -f "$SOURCE_APP_ICON" ]]; then
  cp "$SOURCE_APP_ICON" "$APP_BUNDLE_DIR/Contents/Resources/AppIcon.png"
  iconset_dir="$TEMP_BUILD_ROOT/AppIcon.iconset"
  mkdir -p "$iconset_dir"
  sips -z 16 16 "$SOURCE_APP_ICON" --out "$iconset_dir/icon_16x16.png" >/dev/null
  sips -z 32 32 "$SOURCE_APP_ICON" --out "$iconset_dir/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "$SOURCE_APP_ICON" --out "$iconset_dir/icon_32x32.png" >/dev/null
  sips -z 64 64 "$SOURCE_APP_ICON" --out "$iconset_dir/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "$SOURCE_APP_ICON" --out "$iconset_dir/icon_128x128.png" >/dev/null
  sips -z 256 256 "$SOURCE_APP_ICON" --out "$iconset_dir/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "$SOURCE_APP_ICON" --out "$iconset_dir/icon_256x256.png" >/dev/null
  sips -z 512 512 "$SOURCE_APP_ICON" --out "$iconset_dir/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "$SOURCE_APP_ICON" --out "$iconset_dir/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "$SOURCE_APP_ICON" --out "$iconset_dir/icon_512x512@2x.png" >/dev/null
  iconutil -c icns "$iconset_dir" -o "$APP_BUNDLE_DIR/Contents/Resources/AppIcon.icns"
fi

echo "==> Clearing extended attributes"
xattr -cr "$APP_BUNDLE_DIR"

echo "==> Signing app bundle ($SIGN_IDENTITY)"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --deep --options runtime --identifier "$BUNDLE_ID" --entitlements "$ENTITLEMENTS_FILE" --sign "$SIGN_IDENTITY" "$APP_BUNDLE_DIR"
else
  if [[ -n "$KEYCHAIN_PATH" ]]; then
    codesign --force --deep --options runtime --timestamp --identifier "$BUNDLE_ID" --entitlements "$ENTITLEMENTS_FILE" --sign "${SIGN_IDENTITY_HASH:-$SIGN_IDENTITY}" --keychain "$KEYCHAIN_PATH" "$APP_BUNDLE_DIR"
  else
    codesign --force --deep --options runtime --timestamp --identifier "$BUNDLE_ID" --entitlements "$ENTITLEMENTS_FILE" --sign "${SIGN_IDENTITY_HASH:-$SIGN_IDENTITY}" "$APP_BUNDLE_DIR"
  fi
fi

codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE_DIR"
codesign -dv --verbose=4 "$APP_BUNDLE_DIR" >/dev/null 2>&1 || true
codesign -d --entitlements :- "$APP_BUNDLE_DIR" 2>/dev/null >/dev/null || true

if [[ "$artifact_label" == "signed" && "$NOTARIZE" == "1" ]]; then
  [[ -n "$APPLE_ID" && -n "$APPLE_PASSWORD" && -n "$APPLE_TEAM_ID" ]] || {
    echo "Missing notarization settings for signed build." >&2
    exit 1
  }
  echo "==> Notarizing app bundle"
  xcrun notarytool submit "$APP_BUNDLE_DIR" \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_PASSWORD" \
    --team-id "$APPLE_TEAM_ID" \
    --wait
  echo "==> Stapling app bundle"
  xcrun stapler staple "$APP_BUNDLE_DIR"
  spctl -a -vvvv "$APP_BUNDLE_DIR"
fi

echo "==> Signature verification"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE_DIR"
codesign -dv --verbose=4 "$APP_BUNDLE_DIR"
codesign -d --entitlements :- "$APP_BUNDLE_DIR" 2>/dev/null

echo "==> Packaging ZIP"
ditto -c -k --keepParent "$APP_BUNDLE_DIR" "$ZIP_PATH"

extract_dir="$TEMP_BUILD_ROOT/zip-inspect"
mkdir -p "$extract_dir"
ditto -x -k "$ZIP_PATH" "$extract_dir"

app_count="$(find "$extract_dir" -maxdepth 1 -type d -name '*.app' | wc -l | tr -d ' ')"
if [[ "$app_count" != "1" ]]; then
  echo "Expected exactly one app bundle in ZIP, found $app_count." >&2
  exit 1
fi

bug_report_resource_prefix='FIXER_BUG_REPORT'
if find "$extract_dir" -name "${bug_report_resource_prefix}_*" -print | grep . >/dev/null; then
  echo "Forbidden bug-report resource file found in ZIP contents." >&2
  exit 1
fi

"$SCAN_SCRIPT" "$APP_BUNDLE_DIR" "$extract_dir" "$ZIP_PATH"
shasum -a 256 "$ZIP_PATH" > "$DIST_DIR/SHA256SUMS.txt"

echo "ZIP_PATH=$ZIP_PATH"
echo "SHA256_PATH=$DIST_DIR/SHA256SUMS.txt"
lipo -info "$APP_BUNDLE_DIR/Contents/MacOS/$EXECUTABLE_NAME"
