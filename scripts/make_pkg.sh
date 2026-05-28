#!/usr/bin/env bash
# Build a Developer ID-signed, notarized, stapled .pkg installer.
# Usage: make_pkg.sh path/to/App.app path/to/output.pkg
set -euo pipefail

APP="${1:?usage: make_pkg.sh <app> <pkg>}"
PKG="${2:?usage: make_pkg.sh <app> <pkg>}"

UNSIGNED="$(mktemp -d)/unsigned.pkg"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")"

productbuild \
  --component "$APP" /Applications \
  --identifier "net.calii.markyttdown" \
  --version "$VERSION" \
  "$UNSIGNED"

SIGN_ID="${DEV_ID_INSTALLER_IDENTITY:-Developer ID Installer: Nico Bousquet (XJQQCN392F)}"
echo ">> Signing $PKG with $SIGN_ID"
productsign --sign "$SIGN_ID" "$UNSIGNED" "$PKG"
pkgutil --check-signature "$PKG"

echo ">> Notarizing $PKG"
"$(dirname "$0")/notarize.sh" "$PKG"
