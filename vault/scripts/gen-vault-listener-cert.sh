#!/usr/bin/env bash
# Generates a standalone, self-signed CA + server cert for Vault's OWN
# HTTPS listener (its API port 8200). This is intentionally a SEPARATE
# trust root from the internal service-mesh CA that Vault's PKI secrets
# engine will manage once it's up - Vault can't issue a cert for its own
# bootstrap listener before it's unsealed and configured. See docs/VAULT.md
# "Why two CAs" for the full explanation.
#
# Layout matters here:
#   vault/tls/          - vault-cert.pem, vault-key.pem, vault-ca.pem
#                          (mounted READ-ONLY into the vault container -
#                          it needs these three to serve HTTPS)
#   vault/tls-private/   - vault-ca-key.pem (the CA's own private key -
#                          NEVER mounted into any container; only this
#                          script and a human re-issuing certs need it)
# vault-key.pem is deliberately world-readable (644): it's bind-mounted
# into a container that reads it as the non-root `vault` user, which
# doesn't share a host UID with whatever ran this script. The CA private
# key does NOT need this since it's never mounted anywhere.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p tls tls-private

if [ -f tls/vault-ca.pem ]; then
  echo "Vault listener CA already exists in vault/tls/, skipping generation."
  exit 0
fi

openssl genrsa -out tls-private/vault-ca-key.pem 4096
openssl req -x509 -new -nodes -key tls-private/vault-ca-key.pem -sha256 -days 3650 \
  -out tls/vault-ca.pem -subj "/CN=Vault-Bootstrap-CA"

cat > tls/vault-san.cnf <<CONF
[req]
default_bits       = 2048
distinguished_name = req_distinguished_name
req_extensions     = req_ext
prompt             = no
[req_distinguished_name]
CN = vault
[req_ext]
subjectAltName = @alt_names
[alt_names]
DNS.1 = vault
DNS.2 = localhost
IP.1  = 127.0.0.1
CONF

openssl genrsa -out tls/vault-key.pem 2048
openssl req -new -key tls/vault-key.pem -out tls/vault.csr -config tls/vault-san.cnf
openssl x509 -req -in tls/vault.csr -CA tls/vault-ca.pem -CAkey tls-private/vault-ca-key.pem \
  -CAcreateserial -out tls/vault-cert.pem -days 825 -sha256 \
  -extfile tls/vault-san.cnf -extensions req_ext

rm -f tls/vault.csr
chmod 600 tls-private/vault-ca-key.pem
chmod 644 tls/vault-key.pem tls/vault-cert.pem tls/vault-ca.pem
echo "Vault listener cert generated in vault/tls/ (CA private key in vault/tls-private/, never mounted into any container)"
