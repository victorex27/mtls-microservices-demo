#!/usr/bin/env bash
# One-command deploy: syncs this repo to the EC2 instance, runs the Vault +
# dokku setup there, then pushes each service's code to its own dokku git
# remote (this repo is a monorepo of 3 apps; dokku expects one repo per
# app, so we use `git subtree split` to carve each service's subtree out
# and push just that).
#
# Usage:
#   ./scripts/deploy.sh                 # full deploy: sync + remote setup + push all 3 apps
#   ./scripts/deploy.sh --push-only     # skip sync/remote-setup, just re-push app code
#   ./scripts/deploy.sh --setup-only    # sync + remote setup, skip the app push
#
# Reads the instance IP and SSH key path from `terraform output` if you
# don't pass them via env vars:
#   EC2_HOST=1.2.3.4 SSH_KEY=./terraform/mtls-demo-key.pem ./scripts/deploy.sh
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="${1:-full}"

if [ -z "${EC2_HOST:-}" ]; then
  EC2_HOST=$(cd terraform && terraform output -raw instance_public_ip 2>/dev/null) \
    || { echo "Could not read EC2_HOST from terraform output. Set EC2_HOST env var." >&2; exit 1; }
fi
if [ -z "${SSH_KEY:-}" ]; then
  SSH_KEY_NAME=$(cd terraform && terraform output -raw private_key_path 2>/dev/null) \
    || { echo "Could not read SSH key path from terraform output. Set SSH_KEY env var." >&2; exit 1; }
  SSH_KEY="terraform/${SSH_KEY_NAME}"
fi

SSH_OPTS=(-i "$SSH_KEY" -o StrictHostKeyChecking=accept-new)
REMOTE="ubuntu@${EC2_HOST}"
REMOTE_DIR="/home/ubuntu/mtls-microservices"

echo "Target: $REMOTE (key: $SSH_KEY)"

sync_repo() {
  echo "== Syncing repo to $REMOTE:$REMOTE_DIR =="
  ssh "${SSH_OPTS[@]}" "$REMOTE" "mkdir -p $REMOTE_DIR"
  rsync -az --delete \
    --exclude 'node_modules' --exclude 'dist' --exclude '.git' \
    --exclude 'certs/local' --exclude '.local-logs' \
    --exclude 'vault/tls' --exclude 'vault/secrets' --exclude 'vault/data' \
    --exclude 'vault/agent/creds/*/role_id' --exclude 'vault/agent/creds/*/secret_id' \
    --exclude 'terraform/.terraform' --exclude 'terraform/*.tfstate*' --exclude 'terraform/*.pem' \
    -e "ssh ${SSH_OPTS[*]}" \
    ./ "$REMOTE:$REMOTE_DIR/"
}

run_remote_setup() {
  echo "== Running remote-setup.sh on the instance (this takes a few minutes) =="
  ssh "${SSH_OPTS[@]}" "$REMOTE" "sudo bash $REMOTE_DIR/scripts/remote-setup.sh"
}

fetch_vault_ca() {
  echo "== Fetching Vault's listener CA cert so local scripts can reach the remote Vault =="
  mkdir -p vault/tls
  scp "${SSH_OPTS[@]}" "$REMOTE:$REMOTE_DIR/vault/tls/vault-ca.pem" vault/tls/vault-ca.pem
}

push_apps() {
  echo "== Pushing application code to dokku via git subtree =="
  for app in gateway users-service orders-service; do
    echo "-- $app --"
    branch="deploy-${app}"
    git branch -D "$branch" >/dev/null 2>&1 || true
    git subtree split --prefix="$app" -b "$branch" >/dev/null

    remote_name="dokku-${app}"
    git remote remove "$remote_name" >/dev/null 2>&1 || true
    git remote add "$remote_name" "dokku@${EC2_HOST}:${app}"

    GIT_SSH_COMMAND="ssh -i $SSH_KEY -o StrictHostKeyChecking=accept-new" \
      git push "$remote_name" "${branch}:master" --force

    git branch -D "$branch" >/dev/null 2>&1 || true
  done
}

case "$MODE" in
  --push-only)
    push_apps
    ;;
  --setup-only)
    sync_repo
    run_remote_setup
    fetch_vault_ca
    ;;
  full|"")
    sync_repo
    run_remote_setup
    fetch_vault_ca
    push_apps
    ;;
  *)
    echo "Unknown mode: $MODE (expected --push-only, --setup-only, or nothing)" >&2
    exit 1
    ;;
esac

echo
echo "== Done =="
echo "Gateway: https://${EC2_HOST}:3000  (mTLS required - see docs/TESTING_MTLS.md)"
echo "Vault UI: https://${EC2_HOST}:8200"
echo "Try:"
echo "  (cd vault && VAULT_ADDR=https://${EC2_HOST}:8200 ./scripts/issue-test-client-cert.sh)"
echo "  ./scripts/test-mtls.sh https://api-gateway:3000 ${EC2_HOST}"
