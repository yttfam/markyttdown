#!/usr/bin/env bash
# Import Developer ID certs from base64 .p12 blobs into an ephemeral keychain.
# Designed to run on a fresh GitHub-hosted macos-latest runner.
# Env required:
#   DEV_ID_APP_P12, DEV_ID_APP_PASS
#   DEV_ID_INST_P12, DEV_ID_INST_PASS
#   ASC_KEY_P8 (written to $ASC_KEY_PATH)
# Exports:
#   ASC_KEY_PATH (consumed by notarize.sh)
set -euo pipefail

: "${DEV_ID_APP_P12:?}"; : "${DEV_ID_APP_PASS:?}"
: "${DEV_ID_INST_P12:?}"; : "${DEV_ID_INST_PASS:?}"
: "${ASC_KEY_P8:?}"; : "${ASC_KEY_ID:?}"

KC="$RUNNER_TEMP/markyttdown-signing.keychain-db"
KC_PWD="$(openssl rand -hex 16)"

security create-keychain -p "$KC_PWD" "$KC"
security set-keychain-settings -lut 21600 "$KC"
security unlock-keychain -p "$KC_PWD" "$KC"

PRIORS="$(security list-keychains -d user | tr -d '"')"
security list-keychains -d user -s "$KC" $PRIORS

APP_P12="$RUNNER_TEMP/app.p12"
INST_P12="$RUNNER_TEMP/inst.p12"
printf '%s' "$DEV_ID_APP_P12"  | base64 -d > "$APP_P12"
printf '%s' "$DEV_ID_INST_P12" | base64 -d > "$INST_P12"

security import "$APP_P12"  -k "$KC" -P "$DEV_ID_APP_PASS"  -T /usr/bin/codesign -T /usr/bin/security -T /usr/bin/productsign
security import "$INST_P12" -k "$KC" -P "$DEV_ID_INST_PASS" -T /usr/bin/codesign -T /usr/bin/security -T /usr/bin/productsign

security set-key-partition-list -S apple-tool:,apple:,codesign:,productsign: -s -k "$KC_PWD" "$KC"

ASC_DIR="$RUNNER_TEMP/asc"
mkdir -p "$ASC_DIR"
ASC_KEY_PATH="$ASC_DIR/AuthKey_${ASC_KEY_ID}.p8"
printf '%s' "$ASC_KEY_P8" > "$ASC_KEY_PATH"
chmod 600 "$ASC_KEY_PATH"
echo "ASC_KEY_PATH=$ASC_KEY_PATH" >> "$GITHUB_ENV"

security find-identity -v -p codesigning "$KC"
security find-identity -v "$KC" | grep -E "Developer ID Installer" || { echo "Installer identity missing"; exit 1; }

echo ">> Keychain ready: $KC"
