#!/usr/bin/env bash
#
# Regenerates Resources/AppIcon.icns from scripts/make_icon.swift.
# Run this whenever the icon design changes; the resulting .icns is committed to the repo so
# builds don't depend on regeneration.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ICONSET="$ROOT/build/AppIcon.iconset"
ICNS="$ROOT/Resources/AppIcon.icns"

echo "==> Rendering icon PNGs"
rm -rf "$ICONSET"
swift scripts/make_icon.swift "$ICONSET"

echo "==> Building $ICNS"
mkdir -p "$ROOT/Resources"
iconutil -c icns -o "$ICNS" "$ICONSET"
rm -rf "$ICONSET"

echo "==> Done: $ICNS"
