pid_file = "/tmp/pidfile"

vault {
  address = "https://vault:8200"
  ca_cert = "/vault/tls/vault-ca.pem"
}

auto_auth {
  method "approle" {
    mount_path = "auth/approle"
    config = {
      role_id_file_path                   = "/vault/agent/creds/gateway/role_id"
      secret_id_file_path                 = "/vault/agent/creds/gateway/secret_id"
      remove_secret_id_file_after_reading = false
    }
  }

  sink "file" {
    config = {
      path = "/tmp/gateway-vault-token"
    }
  }
}

template {
  source      = "/vault/agent/templates/gateway-bundle.json.tpl"
  destination = "/certs/bundle.json"
  command     = "/vault/agent/split-bundle.sh"
  # Re-render (and thus re-issue) well before the 24h cert TTL expires.
  # Vault Agent's own lease-renewal logic re-runs the template as leases
  # approach their TTL; this backoff just governs retry-on-error cadence.
  error_backoff = "30s"
}
