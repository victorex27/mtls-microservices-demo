# What "testing mTLS" actually means here

mTLS is only meaningfully tested if you check both directions: that valid
traffic gets through, AND that invalid traffic is rejected. A gateway that
happens to accept a request with a client cert attached proves nothing if
it would have accepted the request without one too. `scripts/test-mtls.sh`
checks four things against a running gateway (localhost or deployed):

| # | Check | What it proves |
|---|-------|-----------------|
| 1 | Valid client cert, correct CA → HTTP 200 | The happy path actually works |
| 2 | `/users/1` returns real data with an `orders` field | The FULL chain - gateway → users-service → orders-service - completed over mTLS at every hop, not just the first one |
| 3 | No client cert at all → connection refused (not HTTP 401, an actual TLS handshake failure) | `rejectUnauthorized`/`checkClientCertificate` is enforced at the TLS layer, before any application code runs |
| 4 | A cert signed by a DIFFERENT, unrelated CA → connection refused | The server is actually checking the cert chain against the CA it was configured with, not just "is any cert present" |

Check 3 vs. check 4 matters: it's possible to misconfigure a server so
"no cert" is rejected (satisfies a naive check 3) but any self-signed cert
is accepted (fails what should be check 4). Testing only the "no cert"
case would miss that. This repo tests both, and generates the check-4
rogue cert on the fly rather than reusing a stale fixture, so as it
guaranteed to be untrusted every run.

## Reading the failure output

A passing `[3]`/`[4]` looks like:

```
[3] Negative: NO client cert -> expect TLS handshake failure, not HTTP 200
  PASS: connection refused as expected (curl: curl: (56) OpenSSL SSL_read: ... alert certificate required)
```

curl error 56 (`CURLE_RECV_ERROR`) with a TLS alert in the message is
correct - the server refused the handshake, curl never even got to send
the HTTP request. If you instead see an HTTP status code printed (even
403/401), that means the TLS handshake *succeeded* without a client cert
and your app-level code did the rejecting - which means mTLS enforcement
has regressed to being optional. Treat that as a real bug: check
`requestCert`/`rejectUnauthorized` in `gateway/src/main.ts` (HTTP layer) or
`checkClientCertificate` in `*/src/main.ts` (gRPC layer).

## Testing gRPC hops directly (not just through the gateway)

`test-mtls.sh` verifies the full chain indirectly (gateway proves
users-service is reachable and working, and `orders` being populated
proves users-service reached orders-service). To poke the gRPC layer
directly instead of only via the gateway:

```bash
# needs grpcurl: https://github.com/fullstorydev/grpcurl
grpcurl -cacert certs/local/users-service/ca-cert.pem \
        -cert   certs/local/api-gateway/tls-cert.pem \
        -key    certs/local/api-gateway/tls-key.pem \
        -proto  proto/users.proto \
        -d '{"id": "1"}' \
        localhost:50051 users.UsersService/GetUser

# and the negative case - omit -cert/-key entirely and watch it fail
grpcurl -cacert certs/local/users-service/ca-cert.pem \
        -proto proto/users.proto \
        -d '{"id": "1"}' \
        localhost:50051 users.UsersService/GetUser
```

The positive call re-uses the gateway's own client cert (it's a valid
`test-client`-equivalent identity from users-service's point of view,
since the mock app logic here doesn't restrict by caller identity - see
"Identity vs. just chain validation" below for how you'd tighten that).

## Identity vs. just chain validation

Everything in this repo validates that a peer's cert chains to the shared
CA (chain validation) and, on the gRPC client side, that the peer's cert
CN matches the expected hostname (`grpc.ssl_target_name_override` +
Node's own hostname check). It does NOT currently restrict which
*specific* identities are allowed to call which endpoints beyond that -
e.g. orders-service's `checkClientCertificate=true` accepts a connection
from anything holding a CA-signed cert, not only from `users-service`
specifically. For a demo this is an acceptable simplification (the AppRole
policies restricting who can *obtain* a `users-service`-identified cert
are the real access boundary - see [VAULT.md](./VAULT.md)); a system with
real authorization requirements would additionally inspect the peer
identity in application code (`call.getPeer()` / the gRPC context's peer
cert, or the `whoami` pattern already shown in `gateway/src/app.controller.ts`)
and enforce a specific allowlist per endpoint.

## CI

`.github/workflows/ci.yml`'s `local-mtls-smoke-test` job runs this exact
suite (Path A from [LOCAL_TESTING.md](./LOCAL_TESTING.md)) on every push -
so a change that breaks mTLS enforcement fails CI, not just "looks fine
until someone checks."
