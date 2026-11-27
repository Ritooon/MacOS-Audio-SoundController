#!/usr/bin/env bash
# Builds a distributable Orpheus .dmg.
#
# Two modes:
#   scripts/release.sh --adhoc
#       No Apple Developer account needed. The app is signed ad hoc, so
#       Gatekeeper blocks it on other Macs until the user allows it
#       (right-click > Open, or System Settings > Privacy & Security).
#
#   TEAM_ID=ABCDE12345 scripts/release.sh
#       Developer ID signing + notarization + stapling. Needs, on this Mac:
#         - a "Developer ID Application" certificate in the login keychain;
#         - notarization credentials stored once with
#             xcrun notarytool store-credentials orpheus-notary \
#               --apple-id <apple-id> --team-id <TEAM_ID>
#           (the password is an app-specific password from account.apple.com).
#       NOTARY_PROFILE overrides the keychain profile name (default orpheus-notary).
#
# Output: build/release/Orpheus-<version>.dmg
# No secret is read from or written to the repository.

set -euo pipefail

cd "$(dirname "$0")/.."

PROJECT="Orpheus.xcodeproj"
SCHEME="Orpheus"
APP_NAME="Orpheus"
ENTITLEMENTS="Orpheus/Orpheus.entitlements"
OUT_DIR="build/release"
ARCHIVE="$OUT_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$OUT_DIR/export"
NOTARY_PROFILE="${NOTARY_PROFILE:-orpheus-notary}"

MODE="developer-id"
if [[ "${1:-}" == "--adhoc" ]]; then
  MODE="adhoc"
elif [[ -n "${1:-}" ]]; then
  echo "Usage: $0 [--adhoc]" >&2
  exit 64
fi

step() { printf '\n==> %s\n' "$*"; }

if [[ "$MODE" == "developer-id" ]]; then
  if [[ -z "${TEAM_ID:-}" ]]; then
    echo "TEAM_ID is not set. Use TEAM_ID=<your team id> $0, or $0 --adhoc." >&2
    exit 64
  fi
  if ! security find-identity -v -p codesigning | grep -q "Developer ID Application.*($TEAM_ID)"; then
    echo "No 'Developer ID Application' certificate for team $TEAM_ID in the keychain." >&2
    exit 1
  fi
fi

VERSION="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -showBuildSettings 2>/dev/null | awk -F' = ' '/ MARKETING_VERSION = /{print $2; exit}')"
BUILD="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -showBuildSettings 2>/dev/null | awk -F' = ' '/ CURRENT_PROJECT_VERSION = /{print $2; exit}')"
DMG="$OUT_DIR/$APP_NAME-$VERSION.dmg"
echo "Orpheus $VERSION ($BUILD), mode: $MODE"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

step "Archiving (Release)"
if [[ "$MODE" == "developer-id" ]]; then
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
    -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" \
    DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="Developer ID Application" \
    ENABLE_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS="--timestamp" \
    archive | tail -n 5
else
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
    -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" \
    CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" \
    ENABLE_HARDENED_RUNTIME=YES \
    archive | tail -n 5
fi

step "Exporting the app"
mkdir -p "$EXPORT_DIR"
if [[ "$MODE" == "developer-id" ]]; then
  OPTIONS="$OUT_DIR/ExportOptions.plist"
  cat > "$OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Developer ID Application</string>
</dict>
</plist>
PLIST
  xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$OPTIONS" | tail -n 3
else
  ditto "$ARCHIVE/Products/Applications/$APP_NAME.app" "$EXPORT_DIR/$APP_NAME.app"
  # Re-sign ad hoc with the hardened runtime and the app's entitlements.
  codesign --force --deep --sign - --options runtime \
    --entitlements "$ENTITLEMENTS" "$EXPORT_DIR/$APP_NAME.app"
fi
APP="$EXPORT_DIR/$APP_NAME.app"

step "Verifying the app signature"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -d --entitlements - "$APP" 2>/dev/null || true

step "Building the disk image"
STAGING="$OUT_DIR/dmg"
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/$APP_NAME.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$STAGING" \
  -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG" >/dev/null
rm -rf "$STAGING"

if [[ "$MODE" == "developer-id" ]]; then
  step "Signing the disk image"
  IDENTITY="$(security find-identity -v -p codesigning \
    | awk -v t="($TEAM_ID)" '/Developer ID Application/ && index($0, t) {print $2; exit}')"
  codesign --force --timestamp --sign "$IDENTITY" "$DMG"

  step "Notarizing (this can take a few minutes)"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

  step "Stapling the ticket"
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"

  step "Gatekeeper check"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
fi

shasum -a 256 "$DMG" | tee "$DMG.sha256"
echo
echo "Done: $DMG"
