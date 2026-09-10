# Vault Agent + jq (needed by split-bundle.sh to parse the PKI issue response).
FROM hashicorp/vault:1.17
RUN apk add --no-cache jq
ENTRYPOINT ["vault", "agent"]
