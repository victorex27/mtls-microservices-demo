# mTLS Microservices Demo (NestJS + gRPC + Vault + dokku on AWS)

A minimal, working demonstration of mutual TLS (mTLS) across a chain of
microservices: an HTTP API gateway and two gRPC backend services, all
authenticating each other with certificates from a shared, Vault-managed
CA. Runs identically (same code, same env-var contract) on localhost and
on a single AWS EC2 instance deployed via Terraform + dokku.

```
client --(HTTPS+mTLS)--> gateway --(gRPC+mTLS)--> users-service --(gRPC+mTLS)--> orders-service
```

## Why this exists

Built from a real design discussion about layering mTLS into a NestJS
microservice architecture - HTTP-inbound mTLS at the gateway, gRPC mTLS
between services, a shared internal CA, and how to actually run that on
[dokku](https://dokku.com/). See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
for the full design.

## Quick start (2 minutes, no Docker, no AWS, no Vault)

```bash
git clone <this-repo>
cd mtls-microservices
./scripts/gen-local-certs.sh
./scripts/run-local.sh &
./scripts/test-mtls.sh
```

You should see 4 passing checks, including a real end-to-end call through
all 3 services. See [docs/LOCAL_TESTING.md](docs/LOCAL_TESTING.md) for the
full local story, including the Vault-backed path (Docker Compose) that
mirrors what actually runs in production.

## Deploying to AWS

```bash
cd terraform && terraform init && terraform apply && cd ..
./scripts/deploy.sh
```

Or trigger `.github/workflows/deploy.yml` from GitHub Actions instead of
running Terraform locally - your AWS credentials then live only in GitHub
Secrets, never on your machine or in this chat. Full walkthrough:
[docs/DEPLOYMENT.md](docs/DEPLOYMENT.md).

## What's in here

| Path | What |
|---|---|
| `gateway/`, `users-service/`, `orders-service/` | The three NestJS apps |
| `proto/` | Shared gRPC `.proto` definitions |
| `vault/` | Vault server config, PKI setup scripts, per-service Vault Agent configs (cert issuance + rotation) |
| `terraform/` | AWS EC2 + security group + SSH key, bootstraps Docker/dokku/Vault via user-data |
| `scripts/` | `gen-local-certs.sh`, `run-local.sh`, `test-mtls.sh`, `rotate-certs.sh`, `deploy.sh`, `remote-setup.sh` |
| `docs/` | [ARCHITECTURE](docs/ARCHITECTURE.md) · [VAULT](docs/VAULT.md) · [LOCAL_TESTING](docs/LOCAL_TESTING.md) · [DEPLOYMENT](docs/DEPLOYMENT.md) · [TESTING_MTLS](docs/TESTING_MTLS.md) |
| `.github/workflows/` | CI (build + mTLS smoke test on every push) and an on-demand Terraform+deploy workflow |

## How certificates work here, in one paragraph

Every service (`gateway`, `users-service`, `orders-service`) reads three
env vars - `TLS_CA_PATH`, `TLS_CERT_PATH`, `TLS_KEY_PATH` - and doesn't
care how the files at those paths got there. Locally, `gen-local-certs.sh`
writes them once with plain openssl. In Docker Compose / on the deployed
EC2 instance, a per-service **Vault Agent** sidecar authenticates to Vault
via AppRole, requests a short-lived cert from Vault's PKI secrets engine,
and re-issues it automatically before it expires - triggering the app to
restart and pick up the fresh cert (see [docs/VAULT.md](docs/VAULT.md) for
exactly how). Same application code, two different ways the certs get
onto disk.

## Status / what's genuinely verified vs. documented-but-untested

Built and verified in this environment:
- All 3 services compile and run; the full mTLS chain (positive and
  negative cases) passes `scripts/test-mtls.sh` against the local
  openssl-cert path.
- The Vault Agent JSON-bundle → split-into-PEM-files logic was verified
  standalone (the `jq` parsing).

Written carefully but **not executed** in this environment, because it
required a Docker registry (`hashicorp/vault` image) and AWS/Terraform
network access this sandbox's egress policy blocks: the full
`docker-compose.yml`/`vault/docker-compose.vault.yml` Vault stack, and the
Terraform + dokku deployment. Run `docs/LOCAL_TESTING.md` Path B and
`docs/DEPLOYMENT.md` yourself (or via the GitHub Actions workflow) to
exercise those - and please open an issue/fix a PR if something doesn't
line up, since it hasn't had a real run yet.

## License

MIT - see [LICENSE](LICENSE).
