#!/usr/bin/env bash
# Quick-start path: generates a local root CA + per-service certs with
# plain openssl, no Vault required. This is the fastest way to prove the
# mTLS wiring in the NestJS apps works before layering Vault-managed
# issuance/rotation on top (see vault/scripts/ for the Vault path).
#
# Output: certs/local/<service>/{tls-cert.pem,tls-key.pem,ca-cert.pem}
# Each service's SAN includes both its DNS name (for docker-compose /
# dokku network resolution) and localhost/127.0.0.1 (for running the app
# directly on your host with `npm run start`).
set -euo pipefail
cd "$(dirname "$0")/.."

ROOT_DIR="certs/local"
mkdir -p "$ROOT_DIR"
cd "$ROOT_DIR"

if [ ! -f ca-cert.pem ]; then
  echo "== Generating root CA =="
  openssl genrsa -out ca-key.pem 2048
  openssl req -x509 -new -nodes -key ca-key.pem -sha256 -days 365 \
    -out ca-cert.pem -subj "/CN=mtls-demo-local-CA"
else
  echo "== Root CA already exists, reusing =="
fi

gen_service_cert() {
  local name="$1"; shift
  local extra_sans=("$@")
  mkdir -p "$name"

  local san_entries="DNS.1 = ${name}\nDNS.2 = localhost\nIP.1  = 127.0.0.1"
  local i=3
  for extra in "${extra_sans[@]}"; do
    san_entries="${san_entries}\nDNS.${i} = ${extra}"
    i=$((i + 1))
  done

  cat > "$name/san.cnf" <<CONF
[req]
default_bits       = 2048
distinguished_name = req_distinguished_name
req_extensions     = req_ext
prompt             = no
[req_distinguished_name]
CN = ${name}
[req_ext]
subjectAltName = @alt_names
[alt_names]
$(echo -e "$san_entries")
CONF

  openssl genrsa -out "$name/tls-key.pem" 2048
  openssl req -new -key "$name/tls-key.pem" -out "$name/req.csr" -config "$name/san.cnf"
  openssl x509 -req -in "$name/req.csr" -CA ca-cert.pem -CAkey ca-key.pem \
    -CAcreateserial -out "$name/tls-cert.pem" -days 365 -sha256 \
    -extfile "$name/san.cnf" -extensions req_ext
  cp ca-cert.pem "$name/ca-cert.pem"
  rm -f "$name/req.csr"
  chmod 600 "$name/tls-key.pem"
  echo "  generated $name/{tls-cert.pem,tls-key.pem,ca-cert.pem}"
}

echo "== Generating service certs =="
gen_service_cert "api-gateway"
gen_service_cert "users-service"
gen_service_cert "orders-service"

echo "== Generating test-client cert (for curl / test-mtls.sh) =="
gen_service_cert "test-client"

echo
echo "Done. Certs are under $ROOT_DIR/<service>/. This whole directory is"
echo "gitignored - regenerate it any time with this script."
