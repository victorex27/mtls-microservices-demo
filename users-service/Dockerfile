# syntax=docker/dockerfile:1
FROM node:22-bookworm-slim AS build
WORKDIR /app
COPY package.json ./
RUN npm install --no-audit --no-fund
COPY tsconfig.json ./
COPY src ./src
COPY proto ./proto
RUN npm run build

FROM node:22-bookworm-slim
WORKDIR /app
ENV NODE_ENV=production
COPY package.json ./
RUN npm install --omit=dev --no-audit --no-fund
COPY --from=build /app/dist ./dist
COPY --from=build /app/proto ./proto

# Certs are NEVER baked into the image. They are mounted at runtime by
# dokku storage:mount (or docker-compose volumes locally) at /certs, and
# TLS_CA_PATH / TLS_CERT_PATH / TLS_KEY_PATH point into that mount.
# This wrapper loop is the "rotate by restart" mechanism described in
# docs/VAULT.md: Vault Agent re-renders the PEM files in place and then
# execs a small trigger that kills the node process (exit code != 0),
# and this loop just starts it again, picking up the fresh files.
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

ENTRYPOINT ["/app/entrypoint.sh"]
