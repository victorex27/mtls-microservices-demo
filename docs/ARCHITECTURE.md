# Architecture

## Services

Three NestJS apps, all TypeScript, all mutually authenticating over TLS:

```
                         [ Internet ]
                              |
                              |  HTTPS + mTLS (client cert required)
                              v
                       +--------------+
                       | api-gateway  |  HTTP inbound, port 3000
                       +--------------+
                              |
                              |  gRPC + mTLS
                              v
                       +--------------+
                       | users-service|  gRPC, port 50051
                       +--------------+
                              |
                              |  gRPC + mTLS
                              v
                       +--------------+
                       |orders-service|  gRPC, port 50052
                       +--------------+
```

- **gateway**: the only service reachable from outside. Terminates its own
  HTTPS with `requestCert: true, rejectUnauthorized: true` - Node's TLS
  layer refuses the handshake before any route code runs if the caller
  doesn't present a cert signed by the shared CA. Exposes `GET /users/:id`,
  which calls users-service over gRPC.
- **users-service**: a gRPC server (mTLS via `ServerCredentials.createSsl`
  with `checkClientCertificate=true`) that is *also* a gRPC client to
  orders-service (mTLS via `credentials.createSsl`). This is the "gRPC
  service calling another gRPC service" leg from the original design doc.
- **orders-service**: a leaf gRPC server, mTLS-only, no outbound calls.

Every hop - gateway→users-service, users-service→orders-service - is a
separate mTLS handshake. Nothing on the wire between these services is
ever plaintext, and nothing on the wire skips client-cert verification.

## Why three services and not just "microservices for their own sake"

The point of this repo is to demonstrate the mTLS wiring, not to model a
real business domain. `users-service` and `orders-service` hold mock,
in-memory data. Swap in real persistence/business logic without touching
any of the TLS code - it all lives in `mtls.util.ts`, `cert-watcher.ts`,
and the `*.client.ts` gRPC client setup, cleanly separated from
`app.controller.ts`.

## Trust model

One shared CA (a two-tier Root → Intermediate hierarchy managed by Vault -
see [VAULT.md](./VAULT.md)) signs a certificate for every service. Each
service is handed:
- its own cert + private key (its identity)
- the CA chain (so it can verify *anyone else's* cert)

A service's identity is its certificate's Common Name (CN): `api-gateway`,
`users-service`, `orders-service`. gRPC client connections pin the expected
server identity via `grpc.ssl_target_name_override` so a swapped/rogue
service with a *different* but still CA-signed identity would fail hostname
verification, not just cert-chain verification - see the `[4]` negative
test in `scripts/test-mtls.sh` for the chain-only case, and
`docs/TESTING_MTLS.md` for why identity pinning is the stronger property.

## Certificate lifecycle

Two independent ways to get certs onto disk, both writing to the same
`TLS_CA_PATH` / `TLS_CERT_PATH` / `TLS_KEY_PATH` locations so the
application code never needs to know which one is in play:

1. **`scripts/gen-local-certs.sh`** - a one-shot openssl script (same
   approach as the original design doc). Fast, no dependencies beyond
   openssl, 365-day certs. Good for the first "does the wiring even work"
   loop.
2. **Vault's PKI secrets engine + Vault Agent** - the production-style
   path. Certs are short-lived (24h) and auto-renewed by a Vault Agent
   sidecar per service; see [VAULT.md](./VAULT.md) for the full mechanism,
   including how rotation gets picked up by a running app.

## Deployment topology (single EC2 instance)

```
EC2 instance (Ubuntu, provisioned by Terraform)
│
├── dokku
│   ├── app: gateway         (Dockerfile deploy, port 3000 published to host)
│   ├── app: users-service   (Dockerfile deploy, internal only)
│   └── app: orders-service  (Dockerfile deploy, internal only)
│
├── docker network: internal-grpc-net (shared by all dokku apps + Vault + agents)
│
└── docker compose (vault/docker-compose.vault.yml)
    ├── vault                 (port 8200 published to host, restrict via SG)
    ├── vault-agent-gateway   -> writes /opt/mtls-demo/certs/gateway/*
    ├── vault-agent-users     -> writes /opt/mtls-demo/certs/users-service/*
    └── vault-agent-orders    -> writes /opt/mtls-demo/certs/orders-service/*

/opt/mtls-demo/certs/<service>/ is bind-mounted into both the vault-agent
sidecar (read-write, it's the writer) and the matching dokku app container
(read-only, via `dokku storage:mount`).
```

See [DEPLOYMENT.md](./DEPLOYMENT.md) for the step-by-step, and
[VAULT.md](./VAULT.md) for why two separate CAs exist (Vault's own listener
cert vs. the service-mesh CA it issues from).
