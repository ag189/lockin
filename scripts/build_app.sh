#!/usr/bin/env bash
#
# Builds Lockin.app as a universal (arm64 + x86_64), release binary wrapped in a proper .app
# bundle with a hardened runtime. Ad-hoc signs by default so it runs locally; pass a Developer ID
# identity to sign for distribution (notarization is a separate step, see package_dmg.sh / README).
#
# Usage:
#   scripts/build_app.sh                       # ad-hoc signed, universal
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" scripts/build_app.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="Lockin"
BUNDLE_ID="com.lockin.app"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/$APP_NAME.app"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"   # default: ad-hoc

echo "==> Building universal release binary"
if ! swift build -c release --arch arm64 --arch x86_64; then
    echo "!! Universal build failed (likely missing x86_64 support); falling back to native arch"
    swift build -c release
    BIN="$(swift build -c release --show-bin-path)/$APP_NAME"
else
    BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/$APP_NAME"
fi

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

echo "==> Signing ($SIGN_IDENTITY)"
codesign --force --deep --options runtime \
    --sign "$SIGN_IDENTITY" \
    --identifier "$BUNDLE_ID" \
    "$APP"

echo "==> Verifying"
codesign --verify --verbose "$APP" || true
lipo -info "$APP/Contents/MacOS/$APP_NAME" || true

echo "==> Done: $APP"
