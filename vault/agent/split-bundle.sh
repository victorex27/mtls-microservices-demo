#!/bin/sh
# Post-render hook run by Vault Agent every time it (re)issues a cert.
# Splits the JSON bundle Vault handed us (one atomic PKI issuance) into the
# three PEM files the NestJS apps read (TLS_CERT_PATH / TLS_KEY_PATH /
# TLS_CA_PATH), writing via temp-file+rename so the app's fs.watch() never
# sees a half-written file.
set -eu
BUNDLE="/certs/bundle.json"
OUT_DIR="/certs"

jq -r '.certificate + "\n" + .issuing_ca' "$BUNDLE" > "$OUT_DIR/tls-cert.pem.tmp"
jq -r '.private_key' "$BUNDLE" > "$OUT_DIR/tls-key.pem.tmp"
jq -r '.issuing_ca' "$BUNDLE" > "$OUT_DIR/ca-cert.pem.tmp"

mv "$OUT_DIR/tls-cert.pem.tmp" "$OUT_DIR/tls-cert.pem"
mv "$OUT_DIR/tls-key.pem.tmp" "$OUT_DIR/tls-key.pem"
mv "$OUT_DIR/ca-cert.pem.tmp" "$OUT_DIR/ca-cert.pem"
chmod 600 "$OUT_DIR/tls-key.pem"

expiry=$(jq -r '.expiration' "$BUNDLE")
echo "$(date -u +%FT%TZ) cert rendered, expires (unix): $expiry" >> "$OUT_DIR/rotation.log"
