#!/usr/bin/env bash
# Build a notarized + stapled .dmg around a .app bundle.
# Usage: make_dmg.sh path/to/App.app path/to/output.dmg
# Requires: create-dmg (brew install create-dmg) OR falls back to hdiutil.
set -euo pipefail

APP="${1:?usage: make_dmg.sh <app> <dmg>}"
DMG="${2:?usage: make_dmg.sh <app> <dmg>}"
VOL="${VOLNAME:-markyttdown}"

rm -f "$DMG"

if command -v create-dmg >/dev/null 2>&1; then
  create-dmg \
    --volname "$VOL" \
    --window-pos 200 120 \
    --window-size 540 360 \
    --icon-size 96 \
    --icon "$(basename "$APP")" 140 180 \
    --app-drop-link 400 180 \
    --no-internet-enable \
    "$DMG" "$APP"
else
  STAGE="$(mktemp -d)"
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -volname "$VOL" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
  rm -rf "$STAGE"
fi

echo ">> Signing $DMG"
codesign --force --sign "Developer ID Application" --timestamp "$DMG"

echo ">> Notarizing $DMG"
"$(dirname "$0")/notarize.sh" "$DMG"
