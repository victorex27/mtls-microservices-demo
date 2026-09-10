#!/usr/bin/env bash
# Forces an immediate cert rotation for one or all services, for
# demonstrating/testing the rotation path without waiting for the natural
# 24h TTL to approach expiry. Restarting a Vault Agent container makes it
# re-run auto_auth + template rendering from scratch, which re-issues a
# fresh cert immediately; split-bundle.sh then rewrites the PEM files, and
# each app's cert-watcher.ts (fs.watch) notices and restarts the app
# process (exit code 99) to pick up the new cert.
#
# Local (docker-compose.yml):  ./scripts/rotate-certs.sh
# Deployed (run ON the EC2 instance, where vault/docker-compose.vault.yml
# is the active compose file):
#   COMPOSE_FILE=vault/docker-compose.vault.yml ./scripts/rotate-certs.sh
set -euo pipefail
cd "$(dirname "$0")/.."

COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.yml}"
SERVICE="${1:-all}"

restart_one() {
  echo "Restarting vault-agent-$1 to force cert re-issuance..."
  docker compose -f "$COMPOSE_FILE" restart "vault-agent-$1"
}

case "$SERVICE" in
  gateway) restart_one gateway ;;
  users|users-service) restart_one users ;;
  orders|orders-service) restart_one orders ;;
  all)
    restart_one gateway
    restart_one users
    restart_one orders
    ;;
  *)
    echo "Usage: $0 [gateway|users|orders|all]" >&2
    exit 1
    ;;
esac

echo "Rotation triggered. Check vault/agent/creds/*/... and the app logs -"
echo "each app should log 'restarting to pick up rotated cert' within a few seconds."
