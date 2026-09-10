#!/usr/bin/env bash
# Generates a standalone, self-signed CA + server cert for Vault's OWN
# HTTPS listener (its API port 8200). This is intentionally a SEPARATE
# trust root from the internal service-mesh CA that Vault's PKI secrets
# engine will manage once it's up - Vault can't issue a cert for its own
# bootstrap listener before it's unsealed and configured. See docs/VAULT.md
# "Why two CAs" for the full explanation.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p tls
cd tls

if [ -f vault-ca.pem ]; then
  echo "Vault listener CA already exists in vault/tls/, skipping generation."
  exit 0
fi

openssl genrsa -out vault-ca-key.pem 4096
openssl req -x509 -new -nodes -key vault-ca-key.pem -sha256 -days 3650 \
  -out vault-ca.pem -subj "/CN=Vault-Bootstrap-CA"

cat > vault-san.cnf <<CONF
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

openssl genrsa -out vault-key.pem 2048
openssl req -new -key vault-key.pem -out vault.csr -config vault-san.cnf
openssl x509 -req -in vault.csr -CA vault-ca.pem -CAkey vault-ca-key.pem \
  -CAcreateserial -out vault-cert.pem -days 825 -sha256 \
  -extfile vault-san.cnf -extensions req_ext

rm -f vault.csr
chmod 600 vault-ca-key.pem vault-key.pem
echo "Vault listener cert generated in vault/tls/"
