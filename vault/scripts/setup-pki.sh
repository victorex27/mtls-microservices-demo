#!/usr/bin/env bash
# Configures Vault's PKI secrets engine as a two-tier CA:
#   pki      -> Root CA (offline-ish, long TTL, only ever signs the intermediate)
#   pki_int  -> Intermediate CA (the one actually issuing per-service certs)
#
# This mirrors standard PKI practice: the root CA's key is used as rarely
# as possible; day-to-day issuance and rotation goes through the
# intermediate. Every service (gateway, users-service, orders-service)
# trusts the same chain because they're all handed pki_int's CA chain as
# their TLS_CA_PATH.
set -euo pipefail
cd "$(dirname "$0")/.."

export VAULT_ADDR="${VAULT_ADDR:-https://127.0.0.1:8200}"
export VAULT_CACERT="${VAULT_CACERT:-$(pwd)/tls/vault-ca.pem}"
export VAULT_TOKEN="${VAULT_TOKEN:-$(cat secrets/root-token.txt 2>/dev/null || true)}"

if [ -z "${VAULT_TOKEN:-}" ]; then
  echo "VAULT_TOKEN not set and vault/secrets/root-token.txt not found. Run init-vault.sh first." >&2
  exit 1
fi

echo "== Enabling Root CA (pki) =="
vault secrets enable -path=pki -max-lease-ttl=87600h pki || echo "(already enabled)"
vault secrets tune -max-lease-ttl=87600h pki

vault write -field=certificate pki/root/generate/internal \
  common_name="mtls-demo Root CA" \
  ttl=87600h > secrets/root-ca.pem || true

vault write pki/config/urls \
  issuing_certificates="${VAULT_ADDR}/v1/pki/ca" \
  crl_distribution_points="${VAULT_ADDR}/v1/pki/crl"

echo "== Enabling Intermediate CA (pki_int) =="
vault secrets enable -path=pki_int -max-lease-ttl=8760h pki || echo "(already enabled)"
vault secrets tune -max-lease-ttl=8760h pki_int

vault write -format=json pki_int/intermediate/generate/internal \
  common_name="mtls-demo Intermediate CA" \
  | jq -r '.data.csr' > secrets/pki_intermediate.csr

vault write -format=json pki/root/sign-intermediate \
  csr=@secrets/pki_intermediate.csr \
  format=pem_bundle ttl=8760h \
  | jq -r '.data.certificate' > secrets/intermediate.cert.pem

vault write pki_int/intermediate/set-signed \
  certificate=@secrets/intermediate.cert.pem

vault write pki_int/config/urls \
  issuing_certificates="${VAULT_ADDR}/v1/pki_int/ca" \
  crl_distribution_points="${VAULT_ADDR}/v1/pki_int/crl"

echo "== Creating per-service PKI roles =="
# max_ttl kept short (72h, default issuance 24h) on purpose: it forces
# rotation to actually happen during any reasonably long-running demo,
# which is the whole point of wiring Vault Agent up to renew them.
vault write pki_int/roles/gateway-role \
  allowed_domains="api-gateway" \
  allow_bare_domains=true \
  allow_subdomains=false \
  max_ttl="72h" ttl="24h" \
  server_flag=true client_flag=true \
  key_usage="DigitalSignature,KeyEncipherment" \
  ext_key_usage="ServerAuth,ClientAuth"

vault write pki_int/roles/users-service-role \
  allowed_domains="users-service" \
  allow_bare_domains=true \
  allow_subdomains=false \
  max_ttl="72h" ttl="24h" \
  server_flag=true client_flag=true \
  key_usage="DigitalSignature,KeyEncipherment" \
  ext_key_usage="ServerAuth,ClientAuth"

vault write pki_int/roles/orders-service-role \
  allowed_domains="orders-service" \
  allow_bare_domains=true \
  allow_subdomains=false \
  max_ttl="72h" ttl="24h" \
  server_flag=true client_flag=true \
  key_usage="DigitalSignature,KeyEncipherment" \
  ext_key_usage="ServerAuth,ClientAuth"

vault write pki_int/roles/test-client-role \
  allowed_domains="test-client" \
  allow_bare_domains=true \
  allow_subdomains=false \
  max_ttl="24h" ttl="1h" \
  server_flag=false client_flag=true \
  key_usage="DigitalSignature,KeyEncipherment" \
  ext_key_usage="ClientAuth"

echo "PKI setup complete. Intermediate CA chain: vault/secrets/intermediate.cert.pem"
echo "Next: run ./scripts/setup-approles.sh"
