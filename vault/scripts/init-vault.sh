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

# `vault status` exits non-zero whenever Vault is sealed or uninitialized -
# that's normal, expected, and NOT an error we want set -e to act on. It
# still prints valid JSON to stdout in that case, so capture stdout with
# its exit code neutralized (`|| true`), then hand that string to jq as a
# SEPARATE command (not piped straight from `vault status`) so pipefail
# has nothing to trip on. Piping `vault status | jq ... || echo fallback`
# looks equivalent but isn't: if jq itself exits 0, its real output is
# already captured, and pipefail still fails the pipeline because vault
# status exited non-zero - so `|| echo fallback` APPENDS a second line
# instead of replacing anything, corrupting the value.
STATUS_JSON=$(vault status -format=json 2>/dev/null || true)
INITIALIZED=$(jq -r '.initialized // false' <<<"$STATUS_JSON")

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

# Same reasoning as STATUS_JSON above - re-check now rather than reuse the
# pre-init snapshot, since operator init above changes sealed state.
STATUS_JSON=$(vault status -format=json 2>/dev/null || true)
SEALED=$(jq -r '.sealed // true' <<<"$STATUS_JSON")
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

# `sealed: false` doesn't mean Vault is ready to serve writes yet. With Raft
# storage, unsealing just lets this node join/complete its own single-node
# leader election - there's a real (if usually sub-second) gap between
# "unsealed" and "elected itself active node". Hit it too early and you get
# a real, reproducible failure, not a flake in the "eventually consistent"
# sense - every mounts/pki write in that gap fails with:
#   Code: 500 * local node not active but active cluster node not found
# So actively wait for the node to report itself as the Raft leader before
# handing control to setup-pki.sh, instead of assuming unsealed == ready.
echo "Waiting for Vault to become the active (leader) node..."
for i in $(seq 1 30); do
  IS_SELF=$(vault read -format=json sys/leader 2>/dev/null | jq -r '.data.is_self // false')
  if [ "$IS_SELF" = "true" ]; then
    echo "Vault is the active node (after ~${i}s)."
    break
  fi
  sleep 1
  if [ "$i" -eq 30 ]; then
    echo "Vault did not become the active node within 30s." >&2
    vault read sys/leader >&2 || true
    exit 1
  fi
done

echo "Next: run ./scripts/setup-pki.sh"
