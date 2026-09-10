#!/bin/sh
# Post-render hook run by Vault Agent every time it (re)issues a cert.
# Splits the JSON bundle Vault handed us (one atomic PKI issuance) into the
# three PEM files the NestJS apps read (TLS_CERT_PATH / TLS_KEY_PATH /
# TLS_CA_PATH), writing via temp-file+rename so the app's fs.watch() never
# sees a half-written file.
set -eu
BUNDLE="/certs/bundle.json"
OUT_DIR="/certs"

# Use Vault's full ca_chain (issuing intermediate + root), not just
# issuing_ca (the bare intermediate). Node's TLS verification (unlike
# curl/OpenSSL's CLI trust-store handling, which is more lenient about
# trusting a non-self-signed cert placed directly in the CA file) needs a
# complete chain up to a self-signed root to reliably validate a peer's
# cert - a CA file containing only the intermediate reproducibly fails
# Node's peer-certificate verification with "unable to get issuer
# certificate", even though the intermediate IS in fact the correct/only
# issuer. ca_chain falls back to [issuing_ca] if Vault ever omits it.
CHAIN_FILTER='(.ca_chain // [.issuing_ca]) | join("\n")'

jq -r ".certificate + \"\n\" + ($CHAIN_FILTER)" "$BUNDLE" > "$OUT_DIR/tls-cert.pem.tmp"
jq -r '.private_key' "$BUNDLE" > "$OUT_DIR/tls-key.pem.tmp"
jq -r "$CHAIN_FILTER" "$BUNDLE" > "$OUT_DIR/ca-cert.pem.tmp"

mv "$OUT_DIR/tls-cert.pem.tmp" "$OUT_DIR/tls-cert.pem"
mv "$OUT_DIR/tls-key.pem.tmp" "$OUT_DIR/tls-key.pem"
mv "$OUT_DIR/ca-cert.pem.tmp" "$OUT_DIR/ca-cert.pem"
chmod 600 "$OUT_DIR/tls-key.pem"

expiry=$(jq -r '.expiration' "$BUNDLE")
echo "$(date -u +%FT%TZ) cert rendered, expires (unix): $expiry" >> "$OUT_DIR/rotation.log"
