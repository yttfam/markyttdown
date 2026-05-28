#!/usr/bin/env bash
# Build a Developer ID-signed, notarized, stapled .pkg installer.
# Usage: make_pkg.sh path/to/App.app path/to/output.pkg
set -euo pipefail

APP="${1:?usage: make_pkg.sh <app> <pkg>}"
PKG="${2:?usage: make_pkg.sh <app> <pkg>}"

UNSIGNED="$(mktemp -d)/unsigned.pkg"

productbuild \
  --component "$APP" /Applications \
  --identifier "net.calii.markyttdown" \
  --version "$(defaults read "$(pwd)/$APP/Contents/Info" CFBundleShortVersionString)" \
  "$UNSIGNED"

echo ">> Signing $PKG with Developer ID Installer"
productsign --sign "Developer ID Installer" "$UNSIGNED" "$PKG"
pkgutil --check-signature "$PKG"

echo ">> Notarizing $PKG"
"$(dirname "$0")/notarize.sh" "$PKG"
