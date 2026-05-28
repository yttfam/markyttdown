#!/usr/bin/env bash
# Read Apple signing/notarization material from Vault (via kytti) and push to
# GitHub Actions repo secrets (via gh). Run locally whenever certs rotate.
# Requires: `gh` authenticated, `kytti` MCP not needed — uses raw `vault` CLI.
#
# Vault is read via `vault` CLI here (not kytti, since kytti is read-only MCP
# and this is a sync tool you run yourself). Make sure VAULT_ADDR/VAULT_TOKEN
# are in your env.
set -euo pipefail

REPO="${REPO:-yttfam/markyttdown}"

field() {
  vault kv get -field="$2" "secret/$1"
}

set_secret() {
  local name="$1" value="$2"
  gh secret set "$name" --repo "$REPO" --body "$value"
}

echo ">> Reading from Vault"
ASC_KEY_ID="$(field infra/apple-asc key_id)"
ASC_ISSUER_ID="$(field infra/apple-asc issuer_id)"
ASC_KEY_P8="$(field infra/apple-asc key_p8)"

DEV_ID_APP_P12="$(field infra/apple-cert-developer-id-application p12_base64)"
DEV_ID_APP_PASS="$(field infra/apple-cert-developer-id-application password)"

DEV_ID_INST_P12="$(field infra/apple-cert-developer-id-installer p12_base64)"
DEV_ID_INST_PASS="$(field infra/apple-cert-developer-id-installer password)"

APPLE_ID_APP_PWD="$(field infra/apple-id-app-password password)"

echo ">> Pushing to GitHub: $REPO"
set_secret ASC_KEY_ID        "$ASC_KEY_ID"
set_secret ASC_ISSUER_ID     "$ASC_ISSUER_ID"
set_secret ASC_KEY_P8        "$ASC_KEY_P8"
set_secret DEV_ID_APP_P12    "$DEV_ID_APP_P12"
set_secret DEV_ID_APP_PASS   "$DEV_ID_APP_PASS"
set_secret DEV_ID_INST_P12   "$DEV_ID_INST_P12"
set_secret DEV_ID_INST_PASS  "$DEV_ID_INST_PASS"
set_secret APPLE_ID_APP_PWD  "$APPLE_ID_APP_PWD"

echo ">> Done. Verify: gh secret list --repo $REPO"
