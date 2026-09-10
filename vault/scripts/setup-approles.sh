#!/usr/bin/env bash
# Creates one AppRole per service, each scoped by the matching policy in
# vault/policies/. Each service's Vault Agent authenticates with its own
# role_id + secret_id (its "machine identity") and can then request certs
# ONLY for itself.
set -euo pipefail
cd "$(dirname "$0")/.."

export VAULT_ADDR="${VAULT_ADDR:-https://127.0.0.1:8200}"
export VAULT_CACERT="${VAULT_CACERT:-$(pwd)/tls/vault-ca.pem}"
export VAULT_TOKEN="${VAULT_TOKEN:-$(cat secrets/root-token.txt 2>/dev/null || true)}"

if [ -z "${VAULT_TOKEN:-}" ]; then
  echo "VAULT_TOKEN not set. Run init-vault.sh first." >&2
  exit 1
fi

vault auth enable approle || echo "(approle auth already enabled)"

for svc in gateway users-service orders-service; do
  echo "== $svc =="
  vault policy write "${svc}-policy" "policies/${svc}-policy.hcl"

  vault write "auth/approle/role/${svc}" \
    token_policies="${svc}-policy" \
    token_ttl=1h \
    token_max_ttl=4h \
    secret_id_ttl=0 \
    secret_id_num_uses=0

  mkdir -p "agent/creds/${svc}"
  vault read -field=role_id "auth/approle/role/${svc}/role-id" > "agent/creds/${svc}/role_id"
  vault write -field=secret_id -f "auth/approle/role/${svc}/secret-id" > "agent/creds/${svc}/secret_id"
  chmod 600 "agent/creds/${svc}/role_id" "agent/creds/${svc}/secret_id"
  echo "  wrote agent/creds/${svc}/{role_id,secret_id}"
done

echo "AppRoles created. These agent/creds/*/{role_id,secret_id} files are gitignored -"
echo "on deployment they're generated fresh on the EC2 instance, never committed."
