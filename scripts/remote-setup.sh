#!/usr/bin/env bash
# Runs ON the EC2 instance (invoked by ./scripts/deploy.sh over SSH, from a
# copy of this repo already rsync'd to ~/mtls-microservices). Idempotent:
# safe to re-run after fixing a mistake, without recreating the instance.
#
# Order matters and is deliberate - see the comments at each phase.
set -euo pipefail
cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd)"

echo "############################################"
echo "# Phase 1: Vault listener cert + Vault server"
echo "############################################"
(cd vault && ./scripts/gen-vault-listener-cert.sh)

docker network inspect internal-grpc-net >/dev/null 2>&1 \
  || docker network create internal-grpc-net

docker compose -f vault/docker-compose.vault.yml up -d --build vault

echo "Waiting for Vault to report healthy..."
export VAULT_ADDR="https://127.0.0.1:8200"
export VAULT_CACERT="$REPO_ROOT/vault/tls/vault-ca.pem"
for i in $(seq 1 60); do
  if curl -sk --cacert "$VAULT_CACERT" "$VAULT_ADDR/v1/sys/health?standbyok=true" >/dev/null 2>&1; then
    echo "Vault is up."
    break
  fi
  sleep 2
  if [ "$i" -eq 60 ]; then
    echo "Vault did not become healthy in time." >&2
    exit 1
  fi
done

echo "############################################"
echo "# Phase 2: Initialize + unseal + configure PKI"
echo "############################################"
(cd vault && ./scripts/init-vault.sh)
(cd vault && ./scripts/setup-pki.sh)
(cd vault && ./scripts/setup-approles.sh)

echo "############################################"
echo "# Phase 3: Bring up Vault Agent sidecars"
echo "#   (their role_id/secret_id files now exist from Phase 2, so they"
echo "#    can authenticate and issue the first certs on first start)"
echo "############################################"
docker compose -f vault/docker-compose.vault.yml up -d --build

echo "Waiting for certs to be issued..."
for svc in gateway users-service orders-service; do
  for i in $(seq 1 60); do
    if [ -s "/opt/mtls-demo/certs/${svc}/tls-cert.pem" ]; then
      echo "  ${svc}: cert present"
      break
    fi
    sleep 2
    if [ "$i" -eq 60 ]; then
      echo "  ${svc}: cert NOT issued after 120s - check: docker logs vault-agent-${svc%%-service}" >&2
      exit 1
    fi
  done
done

echo "############################################"
echo "# Phase 4: dokku apps, network, storage, config"
echo "############################################"
for app in gateway users-service orders-service; do
  dokku apps:create "$app" 2>/dev/null || echo "  ${app}: app already exists"
done

for app in gateway users-service orders-service; do
  dokku network:set "$app" attach-post-deploy internal-grpc-net
done

# Each app gets a stable network alias matching the CN Vault issued its
# cert for, so peer services can dial it by that name.
dokku docker-options:add gateway deploy "--network-alias api-gateway"
dokku docker-options:add users-service deploy "--network-alias users-service"
dokku docker-options:add orders-service deploy "--network-alias orders-service"

# Bind-mount each app's cert directory (written by its Vault Agent sidecar)
# read-only into the container at /certs.
dokku storage:mount gateway /opt/mtls-demo/certs/gateway:/certs 2>/dev/null || true
dokku storage:mount users-service /opt/mtls-demo/certs/users-service:/certs 2>/dev/null || true
dokku storage:mount orders-service /opt/mtls-demo/certs/orders-service:/certs 2>/dev/null || true

# gateway does its OWN TLS termination (mTLS at the app layer) - dokku's
# nginx proxy must NOT sit in front of it doing plaintext HTTP, so it's
# disabled and the container's port is published directly to the host.
dokku proxy:disable gateway
dokku docker-options:add gateway deploy "-p 3000:3000"

# users-service / orders-service are gRPC-only and internal-only: no nginx
# proxy, no published host port. Reachable ONLY via internal-grpc-net.
dokku proxy:disable users-service
dokku proxy:disable orders-service

dokku config:set gateway --no-restart \
  TLS_CA_PATH=/certs/ca-cert.pem \
  TLS_CERT_PATH=/certs/tls-cert.pem \
  TLS_KEY_PATH=/certs/tls-key.pem \
  GATEWAY_PORT=3000 \
  USERS_SERVICE_URL=users-service:50051 \
  USERS_SERVICE_TLS_SERVER_NAME=users-service

dokku config:set users-service --no-restart \
  TLS_CA_PATH=/certs/ca-cert.pem \
  TLS_CERT_PATH=/certs/tls-cert.pem \
  TLS_KEY_PATH=/certs/tls-key.pem \
  USERS_GRPC_PORT=50051 \
  ORDERS_SERVICE_URL=orders-service:50052 \
  ORDERS_SERVICE_TLS_SERVER_NAME=orders-service

dokku config:set orders-service --no-restart \
  TLS_CA_PATH=/certs/ca-cert.pem \
  TLS_CERT_PATH=/certs/tls-cert.pem \
  TLS_KEY_PATH=/certs/tls-key.pem \
  ORDERS_GRPC_PORT=50052

echo
echo "Remote setup complete. Next: push the app code from your machine:"
echo "  ./scripts/deploy.sh --push-only"
