#!/usr/bin/env bash
# Notarize and staple a .app bundle (or any signed artefact).
# Env required: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH
# Usage: notarize.sh path/to/Something.app
set -euo pipefail

TARGET="${1:?usage: notarize.sh <path>}"
: "${ASC_KEY_ID:?ASC_KEY_ID not set}"
: "${ASC_ISSUER_ID:?ASC_ISSUER_ID not set}"
: "${ASC_KEY_PATH:?ASC_KEY_PATH not set}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

case "$TARGET" in
  *.app)
    ZIP="$WORK/$(basename "$TARGET").zip"
    /usr/bin/ditto -c -k --keepParent "$TARGET" "$ZIP"
    SUBMIT="$ZIP"
    ;;
  *.dmg|*.pkg)
    SUBMIT="$TARGET"
    ;;
  *)
    echo "notarize.sh: unsupported target type: $TARGET" >&2
    exit 1
    ;;
esac

echo ">> Submitting $SUBMIT to notarytool…"
xcrun notarytool submit "$SUBMIT" \
  --key "$ASC_KEY_PATH" \
  --key-id "$ASC_KEY_ID" \
  --issuer "$ASC_ISSUER_ID" \
  --wait

echo ">> Stapling $TARGET"
xcrun stapler staple "$TARGET"
xcrun stapler validate "$TARGET"
echo ">> Notarization complete"
