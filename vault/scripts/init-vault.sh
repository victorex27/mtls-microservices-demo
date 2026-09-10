#!/usr/bin/env bash
# Initializes and unseals the Vault server. Run this ONCE against a fresh
# Vault instance (local docker-compose, or the deployed EC2 instance).
#
# Production caveat: this writes unseal keys + root token to
# vault/secrets/vault-init.json on whatever machine runs this script.
# That file is gitignored and MUST be moved to a real secret store
# (a password manager, AWS Secrets Manager, etc.) and deleted from disk
# after your operators have their shares. For a real multi-operator
# production setup, distribute the 5 unseal key shares to 5 different
# people (Shamir's Secret Sharing) instead of keeping them all in one
# file - see docs/VAULT.md.
set -euo pipefail
cd "$(dirname "$0")/.."

export VAULT_ADDR="${VAULT_ADDR:-https://127.0.0.1:8200}"
export VAULT_CACERT="${VAULT_CACERT:-$(pwd)/tls/vault-ca.pem}"

mkdir -p secrets

if vault status >/dev/null 2>&1; then
  INITIALIZED=$(vault status -format=json | jq -r '.initialized')
else
  # vault status exits non-zero when sealed; check the json anyway
  INITIALIZED=$(vault status -format=json 2>/dev/null | jq -r '.initialized' || echo "false")
fi

if [ "$INITIALIZED" != "true" ]; then
  echo "Initializing Vault (5 key shares, threshold 3)..."
  vault operator init -key-shares=5 -key-threshold=3 -format=json > secrets/vault-init.json
  chmod 600 secrets/vault-init.json
  echo "Wrote unseal keys + root token to vault/secrets/vault-init.json"
  echo "!! Move this file to a secure secret store and delete it from disk !!"
else
  echo "Vault already initialized."
fi

if [ ! -f secrets/vault-init.json ]; then
  echo "No local vault-init.json found and Vault isn't initialized by this script." >&2
  echo "If Vault was already initialized elsewhere, unseal manually with 'vault operator unseal'." >&2
  exit 1
fi

SEALED=$(vault status -format=json | jq -r '.sealed')
if [ "$SEALED" = "true" ]; then
  echo "Unsealing Vault with 3 of 5 key shares..."
  jq -r '.unseal_keys_b64[0]' secrets/vault-init.json | xargs vault operator unseal >/dev/null
  jq -r '.unseal_keys_b64[1]' secrets/vault-init.json | xargs vault operator unseal >/dev/null
  jq -r '.unseal_keys_b64[2]' secrets/vault-init.json | xargs vault operator unseal >/dev/null
  echo "Vault unsealed."
else
  echo "Vault already unsealed."
fi

export VAULT_TOKEN=$(jq -r '.root_token' secrets/vault-init.json)
echo "$VAULT_TOKEN" > secrets/root-token.txt
chmod 600 secrets/root-token.txt
echo "Root token written to vault/secrets/root-token.txt (gitignored)."
echo "Next: run ./scripts/setup-pki.sh"
