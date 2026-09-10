# Least-privilege: the gateway's Vault Agent can ONLY request certs under
# its own PKI role. It cannot read secrets belonging to other services,
# cannot list other roles, cannot touch the root/intermediate config.
path "pki_int/issue/gateway-role" {
  capabilities = ["create", "update"]
}
