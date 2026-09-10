#!/usr/bin/env bash
# Issues a short-lived mTLS client cert (CN=test-client) directly from
# Vault's PKI engine for use with curl / scripts/test-mtls.sh. This is the
# "I'm an operator hitting the API by hand" identity, distinct from the
# service-to-service certs the Vault Agents manage automatically.
set -euo pipefail
cd "$(dirname "$0")/.."

export VAULT_ADDR="${VAULT_ADDR:-https://127.0.0.1:8200}"
export VAULT_CACERT="${VAULT_CACERT:-$(pwd)/tls/vault-ca.pem}"
export VAULT_TOKEN="${VAULT_TOKEN:-$(cat secrets/root-token.txt 2>/dev/null || true)}"

if [ -z "${VAULT_TOKEN:-}" ]; then
  echo "VAULT_TOKEN not set. Run init-vault.sh first." >&2
  exit 1
fi

OUT_DIR="../certs/local/test-client"
mkdir -p "$OUT_DIR"

vault write -format=json pki_int/issue/test-client-role \
  common_name="test-client" ttl="1h" > /tmp/test-client-bundle.json

jq -r '.data.certificate + "\n" + .data.issuing_ca' /tmp/test-client-bundle.json > "$OUT_DIR/tls-cert.pem"
jq -r '.data.private_key' /tmp/test-client-bundle.json > "$OUT_DIR/tls-key.pem"
jq -r '.data.issuing_ca' /tmp/test-client-bundle.json > "$OUT_DIR/ca-cert.pem"
chmod 600 "$OUT_DIR/tls-key.pem"
rm -f /tmp/test-client-bundle.json

echo "Test client cert issued: $OUT_DIR/{tls-cert.pem,tls-key.pem,ca-cert.pem} (1h TTL)"
