#!/usr/bin/env bash
# EC2 first-boot bootstrap. Deliberately minimal and idempotent-safe:
# installs the platform (Docker, dokku, Vault CLI) only. Application code,
# Vault PKI setup, and dokku app config are all handled afterwards by
# scripts/deploy.sh, which is re-runnable without touching the instance
# itself - so fixing a mistake never means re-provisioning EC2.
set -euxo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y --no-install-recommends \
  curl ca-certificates gnupg jq unzip openssl rsync git

# --- Docker Engine + Compose plugin ---
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sh
fi
usermod -aG docker ubuntu || true

# --- dokku ---
DOKKU_TAG="${dokku_version}"
if ! command -v dokku >/dev/null 2>&1; then
  curl -fsSL "https://dokku.com/install/$${DOKKU_TAG}/bootstrap.sh" -o /tmp/dokku-bootstrap.sh
  DOKKU_TAG="$${DOKKU_TAG}" bash /tmp/dokku-bootstrap.sh
fi

# Let the ubuntu user's SSH key (the one Terraform generated) also act as
# the dokku deploy key, so `git push dokku@<host>:<app>` works using the
# same key pair used for `ssh ubuntu@<host>`.
if [ -f /home/ubuntu/.ssh/authorized_keys ]; then
  cat /home/ubuntu/.ssh/authorized_keys | dokku ssh-keys:add admin || true
fi

# --- Vault CLI (for running the vault/scripts/*.sh setup scripts) ---
VAULT_VERSION="${vault_version}"
if ! command -v vault >/dev/null 2>&1; then
  curl -fsSL "https://releases.hashicorp.com/vault/$${VAULT_VERSION}/vault_$${VAULT_VERSION}_linux_amd64.zip" -o /tmp/vault.zip
  unzip -o /tmp/vault.zip -d /usr/local/bin
  chmod +x /usr/local/bin/vault
fi

# --- Host directories for cert bind-mounts (shared between Vault Agent
#     sidecars and the dokku app containers, see vault/docker-compose.vault.yml) ---
mkdir -p /opt/mtls-demo/certs/gateway
mkdir -p /opt/mtls-demo/certs/users-service
mkdir -p /opt/mtls-demo/certs/orders-service
chmod -R 755 /opt/mtls-demo

echo "user-data bootstrap complete" > /var/log/mtls-demo-bootstrap-done
