#!/usr/bin/env bash
#
# Packages build/Lockin.app into a drag-to-Applications .dmg.
#
# For a distributable build the app must be signed with a Developer ID identity (see
# build_app.sh) and then notarized. Notarization requires YOUR Apple Developer credentials and
# cannot be done unattended:
#
#   1. Build signed:
#        SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" scripts/build_app.sh
#   2. Package:
#        scripts/package_dmg.sh
#   3. Notarize (store credentials once with `xcrun notarytool store-credentials`):
#        xcrun notarytool submit build/Lockin.dmg --keychain-profile "lockin" --wait
#   4. Staple:
#        xcrun stapler staple build/Lockin.dmg
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/Lockin.app"
DMG="$BUILD_DIR/Lockin.dmg"
STAGE="$BUILD_DIR/dmg-stage"

[ -d "$APP" ] || { echo "!! $APP not found. Run scripts/build_app.sh first."; exit 1; }

echo "==> Staging"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "==> Creating DMG"
hdiutil create \
    -volname "Lockin" \
    -srcfolder "$STAGE" \
    -ov -format UDZO \
    "$DMG"

rm -rf "$STAGE"
echo "==> Done: $DMG"
