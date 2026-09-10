#!/bin/sh
# 1. Wait for the Vault Agent sidecar to have written our certs at least
#    once (first boot can race Vault init/unseal/PKI-setup on a fresh
#    environment - see docs/LOCAL_TESTING.md and docs/DEPLOYMENT.md).
# 2. Run the app. If it exits (crash, or exit(99) from cert-watcher.ts
#    after a cert rotation), restart it after a short backoff so the fresh
#    certs on disk get picked up. Docker/dokku's own restart policy is the
#    outer safety net if this loop itself dies.
set -u

echo "[entrypoint] waiting for TLS material at \$TLS_CERT_PATH / \$TLS_KEY_PATH / \$TLS_CA_PATH ..."
i=0
while [ ! -s "$TLS_CERT_PATH" ] || [ ! -s "$TLS_KEY_PATH" ] || [ ! -s "$TLS_CA_PATH" ]; do
  i=$((i + 1))
  if [ "$i" -gt 60 ]; then
    echo "[entrypoint] gave up waiting for certs after 60s. Is the vault-agent sidecar running and Vault unsealed/configured?" >&2
    exit 1
  fi
  sleep 1
done
echo "[entrypoint] certs found, starting app"

while true; do
  node dist/main.js
  code=$?
  echo "[entrypoint] app exited with code $code, restarting in 1s"
  sleep 1
done
