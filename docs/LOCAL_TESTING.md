# Testing mTLS on localhost

Two paths, from fastest to most realistic. Both end with the same
verification step (`scripts/test-mtls.sh`).

## Path A: quick start, no Docker, no Vault (openssl only)

Fastest inner loop for iterating on the NestJS/gRPC/TLS wiring itself.

```bash
./scripts/gen-local-certs.sh    # generates certs/local/{api-gateway,users-service,orders-service,test-client}/
./scripts/run-local.sh          # builds + runs all 3 services in your terminal (Ctrl+C stops them)
```

In another terminal:

```bash
./scripts/test-mtls.sh
```

Expected output: 4 passing checks - valid-cert success, the full
gateway→users-service→orders-service chain returning real data, no-cert
rejected, and wrong-CA cert rejected. This is exactly what's verified in
CI (`.github/workflows/ci.yml`, job `local-mtls-smoke-test`).

Try it manually too:

```bash
curl --cert certs/local/test-client/tls-cert.pem \
     --key  certs/local/test-client/tls-key.pem \
     --cacert certs/local/test-client/ca-cert.pem \
     https://localhost:3000/users/1

# and the negative case - watch it fail:
curl --cacert certs/local/test-client/ca-cert.pem https://localhost:3000/healthz
```

## Path B: full stack with Vault (Docker Compose)

This is what actually runs on the deployed EC2 instance, just with
localhost networking instead of dokku. Requires Docker + Docker Compose.

```bash
# 1. Generate Vault's own listener cert (separate from the service-mesh CA - see docs/VAULT.md)
./vault/scripts/gen-vault-listener-cert.sh

# 2. Bring up ONLY Vault first
docker compose up -d vault

# 3. Initialize, unseal, configure the PKI hierarchy + AppRoles
(cd vault && ./scripts/init-vault.sh)
(cd vault && ./scripts/setup-pki.sh)
(cd vault && ./scripts/setup-approles.sh)

# 4. Now bring up everything else - the Vault Agents can authenticate
#    immediately since their role_id/secret_id files exist from step 3
docker compose up -d --build

# 5. Issue yourself a test-client cert straight from Vault
(cd vault && ./scripts/issue-test-client-cert.sh)

# 6. Run the same verification suite
./scripts/test-mtls.sh
```

Order matters in steps 2-4: if you `docker compose up -d` everything at
once before Vault is initialized/unsealed, the Vault Agent sidecars will
sit retrying auth against a Vault that isn't ready to serve PKI requests
yet, and the app containers will sit in their `entrypoint.sh` wait loop
(60s timeout) with no certs to read. Re-running steps 2-4 in order fixes
that; nothing here is destructive to re-run.

### Watching rotation happen

Certs are issued with a 24h TTL and Vault Agent renews them automatically
as that approaches. To see it happen immediately instead of waiting:

```bash
./scripts/rotate-certs.sh          # restarts all 3 vault-agent sidecars
docker compose logs -f gateway     # watch for "restarting to pick up rotated cert"
```

### Tearing down

```bash
docker compose down -v   # -v also removes the named volumes (vault-data, *-certs)
```

`-v` deletes Vault's Raft storage too, so you'll need to redo steps 3-4
from scratch next time (a fresh root CA, fresh certs - fine for a demo).

## Troubleshooting

- **`curl: (56) ... certificate required`** - this is the *expected*
  failure mode when you omit `--cert`/`--key`. It's proof mTLS is being
  enforced, not a bug.
- **`ENOENT` reading a cert file on app boot** - the app started before its
  Vault Agent (or `gen-local-certs.sh`) had written certs yet. In Docker
  Compose, `entrypoint.sh` retries for 60s before giving up; check
  `docker compose logs vault-agent-<service>` for why issuance failed
  (usually: Vault not unsealed, or AppRole creds missing/expired).
- **Hostname/SNI mismatch errors between services** - the `grpc.ssl_target_name_override`
  in `users.client.ts`/`orders.client.ts` must exactly match the peer's
  certificate CN. If you changed a service name anywhere, it has to change
  in three places: the Vault PKI role's `allowed_domains`
  (`vault/scripts/setup-pki.sh`), the `common_name` in that service's
  Vault Agent template, and the `*_TLS_SERVER_NAME` env var on the caller.
