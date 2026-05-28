#!/usr/bin/env bash
# Read Apple signing/notarization material from Vault via HTTP API and push
# to GitHub Actions repo secrets via `gh`. Run locally whenever certs rotate.
# Requires: VAULT_ADDR + VAULT_TOKEN in env, gh authenticated, jq.
set -euo pipefail

REPO="${REPO:-yttfam/markyttdown}"
: "${VAULT_ADDR:?VAULT_ADDR not set}"
: "${VAULT_TOKEN:?VAULT_TOKEN not set}"

field() {
  curl -sf -H "X-Vault-Token: $VAULT_TOKEN" \
    "$VAULT_ADDR/v1/secret/data/$1" \
    | jq -r ".data.data.\"$2\""
}

set_secret() {
  local name="$1" value="$2"
  if [ -z "$value" ] || [ "$value" = "null" ]; then
    echo "skip $name (empty)" >&2
    return 1
  fi
  printf '%s' "$value" | gh secret set "$name" --repo "$REPO" --body-file -
}

echo ">> Reading from Vault $VAULT_ADDR"
ASC_KEY_ID="$(field infra/apple-asc key_id)"
ASC_ISSUER_ID="$(field infra/apple-asc issuer_id)"
ASC_KEY_P8="$(field infra/apple-asc key_p8)"

DEV_ID_APP_P12="$(field infra/apple-cert-developer-id-application p12_base64)"
DEV_ID_APP_PASS="$(field infra/apple-cert-developer-id-application p12_password)"

DEV_ID_INST_P12="$(field infra/apple-cert-developer-id-installer p12_base64)"
DEV_ID_INST_PASS="$(field infra/apple-cert-developer-id-installer p12_password)"

APPLE_ID_APP_PWD="$(field infra/apple-id-app-password app_password)"

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
