#!/usr/bin/env bash
# Runs all three services directly on your host (no Docker, no Vault) using
# the certs from ./scripts/gen-local-certs.sh. Fastest inner loop for
# developing/testing the mTLS wiring itself.
#
# Usage:
#   ./scripts/gen-local-certs.sh   # once, or whenever you want fresh certs
#   ./scripts/run-local.sh         # builds + starts all 3 services in foreground
# Ctrl+C stops all three.
set -euo pipefail
cd "$(dirname "$0")/.."

CERTS="$(pwd)/certs/local"
if [ ! -d "$CERTS/api-gateway" ]; then
  echo "No local certs found. Run ./scripts/gen-local-certs.sh first." >&2
  exit 1
fi

echo "== Building all services =="
for svc in orders-service users-service gateway; do
  (cd "$svc" && [ -d node_modules ] || npm install --no-audit --no-fund)
  (cd "$svc" && npm run build)
done

mkdir -p .local-logs
pids=()

cleanup() {
  echo
  echo "Stopping services..."
  for pid in "${pids[@]:-}"; do
    kill "$pid" 2>/dev/null || true
  done
}
trap cleanup EXIT INT TERM

echo "== Starting orders-service (grpc :50052) =="
( cd orders-service && \
  TLS_CA_PATH="$CERTS/orders-service/ca-cert.pem" \
  TLS_CERT_PATH="$CERTS/orders-service/tls-cert.pem" \
  TLS_KEY_PATH="$CERTS/orders-service/tls-key.pem" \
  ORDERS_GRPC_PORT=50052 \
  WATCH_CERTS_FOR_ROTATION=false \
  node dist/main.js 2>&1 | sed 's/^/[orders]  /' ) &
pids+=($!)
sleep 1

echo "== Starting users-service (grpc :50051, -> orders-service:50052) =="
( cd users-service && \
  TLS_CA_PATH="$CERTS/users-service/ca-cert.pem" \
  TLS_CERT_PATH="$CERTS/users-service/tls-cert.pem" \
  TLS_KEY_PATH="$CERTS/users-service/tls-key.pem" \
  USERS_GRPC_PORT=50051 \
  ORDERS_SERVICE_URL=localhost:50052 \
  ORDERS_SERVICE_TLS_SERVER_NAME=orders-service \
  WATCH_CERTS_FOR_ROTATION=false \
  node dist/main.js 2>&1 | sed 's/^/[users]   /' ) &
pids+=($!)
sleep 1

echo "== Starting gateway (https :3000, -> users-service:50051) =="
( cd gateway && \
  TLS_CA_PATH="$CERTS/api-gateway/ca-cert.pem" \
  TLS_CERT_PATH="$CERTS/api-gateway/tls-cert.pem" \
  TLS_KEY_PATH="$CERTS/api-gateway/tls-key.pem" \
  GATEWAY_PORT=3000 \
  USERS_SERVICE_URL=localhost:50051 \
  USERS_SERVICE_TLS_SERVER_NAME=users-service \
  WATCH_CERTS_FOR_ROTATION=false \
  node dist/main.js 2>&1 | sed 's/^/[gateway] /' ) &
pids+=($!)

echo
echo "All three services starting. Try in another terminal:"
echo "  ./scripts/test-mtls.sh"
echo
wait
