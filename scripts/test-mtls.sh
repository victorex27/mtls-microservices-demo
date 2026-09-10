#!/usr/bin/env bash
# End-to-end mTLS verification against the gateway.
#
# Works against BOTH environments:
#   ./scripts/test-mtls.sh
#     -> https://localhost:3000
#
#   ./scripts/test-mtls.sh https://api-gateway:3000 34.201.1.2
#     -> deployed instance. The gateway's cert has SAN=api-gateway (a
#        stable identity), not the EC2 public IP (which can change on
#        stop/start). Passing the IP as a 3rd-arg RESOLVE target makes
#        curl connect to that IP while still sending/verifying SNI
#        "api-gateway", so hostname verification succeeds without needing
#        real DNS. See docs/TESTING_MTLS.md.
#
# Requires: certs/local/test-client/{tls-cert.pem,tls-key.pem,ca-cert.pem}
#   -> generate with: (cd vault && ./scripts/issue-test-client-cert.sh)
#   -> or, for the pure-openssl localhost path (no Vault), run
#      ./scripts/gen-local-certs.sh first, which drops an equivalent
#      test-client cert in the same place.
set -euo pipefail
cd "$(dirname "$0")/.."

GATEWAY_URL="${1:-https://localhost:3000}"
RESOLVE_IP="${2:-}"

CLIENT_DIR="certs/local/test-client"
CERT="$CLIENT_DIR/tls-cert.pem"
KEY="$CLIENT_DIR/tls-key.pem"
CA="$CLIENT_DIR/ca-cert.pem"

pass=0
fail=0

ok()   { echo "  PASS: $1"; pass=$((pass+1)); }
bad()  { echo "  FAIL: $1"; fail=$((fail+1)); }

require_file() {
  if [ ! -s "$1" ]; then
    echo "Missing $1 - generate test-client certs first (see script header)." >&2
    exit 1
  fi
}
require_file "$CERT"; require_file "$KEY"; require_file "$CA"

RESOLVE_ARGS=()
if [ -n "$RESOLVE_IP" ]; then
  host="$(echo "$GATEWAY_URL" | sed -E 's#^https?://##' | cut -d: -f1)"
  port="$(echo "$GATEWAY_URL" | sed -E 's#^https?://##' | cut -d: -f2)"
  RESOLVE_ARGS=(--resolve "${host}:${port}:${RESOLVE_IP}")
  echo "Using curl --resolve ${host}:${port}:${RESOLVE_IP}"
fi

echo "== Target: $GATEWAY_URL =="
echo

echo "[1] Positive: valid client cert + correct CA -> expect HTTP 200"
if curl -sS "${RESOLVE_ARGS[@]}" --cert "$CERT" --key "$KEY" --cacert "$CA" \
     --max-time 10 -o /tmp/mtls-healthz.json -w '%{http_code}' \
     "$GATEWAY_URL/healthz" > /tmp/mtls-code.txt 2>/tmp/mtls-err.txt; then
  code=$(cat /tmp/mtls-code.txt)
  if [ "$code" = "200" ]; then ok "GET /healthz -> 200"; else bad "GET /healthz -> $code"; fi
else
  bad "GET /healthz -> curl error: $(cat /tmp/mtls-err.txt)"
fi

echo "[2] Positive: full chain gateway -> users-service -> orders-service (all mTLS)"
if body=$(curl -sS "${RESOLVE_ARGS[@]}" --cert "$CERT" --key "$KEY" --cacert "$CA" --max-time 10 "$GATEWAY_URL/users/1"); then
  echo "  response: $body"
  if echo "$body" | grep -q '"orders"'; then
    ok "GET /users/1 returned orders from the users-service -> orders-service hop"
  else
    bad "GET /users/1 response missing 'orders' field: $body"
  fi
else
  bad "GET /users/1 -> curl error"
fi

echo "[3] Negative: NO client cert -> expect TLS handshake failure, not HTTP 200"
if curl -sS "${RESOLVE_ARGS[@]}" --cacert "$CA" --max-time 10 -o /dev/null -w '%{http_code}' \
     "$GATEWAY_URL/healthz" > /tmp/mtls-code2.txt 2>/tmp/mtls-err2.txt; then
  code=$(cat /tmp/mtls-code2.txt)
  bad "expected connection to be refused, but got HTTP $code"
else
  ok "connection refused as expected (curl: $(cat /tmp/mtls-err2.txt | tail -1))"
fi

echo "[4] Negative: client cert signed by an UNRELATED CA -> expect handshake failure"
TMP_ROGUE=$(mktemp -d)
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$TMP_ROGUE/rogue-key.pem" \
  -out "$TMP_ROGUE/rogue-cert.pem" -days 1 -subj "/CN=rogue-client" >/dev/null 2>&1
if curl -sS "${RESOLVE_ARGS[@]}" --cert "$TMP_ROGUE/rogue-cert.pem" --key "$TMP_ROGUE/rogue-key.pem" \
     --cacert "$CA" --max-time 10 -o /dev/null -w '%{http_code}' \
     "$GATEWAY_URL/healthz" > /tmp/mtls-code3.txt 2>/tmp/mtls-err3.txt; then
  code=$(cat /tmp/mtls-code3.txt)
  bad "expected connection to be refused, but got HTTP $code"
else
  ok "rogue cert rejected as expected (curl: $(cat /tmp/mtls-err3.txt | tail -1))"
fi
rm -rf "$TMP_ROGUE"

echo
echo "== Results: $pass passed, $fail failed =="
[ "$fail" -eq 0 ]
