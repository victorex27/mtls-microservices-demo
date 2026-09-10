# Production-style Vault server config: integrated storage (Raft), TLS
# listener, UI enabled. Single node for this demo - see docs/VAULT.md for
# how to extend to a multi-node Raft cluster.
ui = true
disable_mlock = true

storage "raft" {
  path    = "/vault/data"
  node_id = "vault-node-1"
}

listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_cert_file = "/vault/tls/vault-cert.pem"
  tls_key_file  = "/vault/tls/vault-key.pem"
  tls_client_ca_file = "/vault/tls/vault-ca.pem"
}

api_addr     = "https://127.0.0.1:8200"
cluster_addr = "https://127.0.0.1:8201"

log_level = "info"
