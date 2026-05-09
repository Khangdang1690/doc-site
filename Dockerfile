# Multi-stage image: build sqlitedeploy CLI from source, build the Astro
# site, then assemble a slim runtime that runs both daemons under entry.sh.
#
# Why we build sqlitedeploy from source instead of `npm install -g`:
# the npm-published sqlitedeploy@latest is still v1 (Litestream-era) and
# only exposes `run`. v2 (sqld + bottomless, with `up`/`down`/`attach`)
# has not been published to npm yet, but our entry.sh requires `up`.
# Building straight from the GitHub source guarantees v2.

# ─── Stage 1: build sqlitedeploy ────────────────────────────────────────
FROM golang:1.25-bookworm AS sqlitedeploy-builder
ARG SQLITEDEPLOY_REF=main
RUN apt-get update && \
    apt-get install -y --no-install-recommends git ca-certificates && \
    rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 --branch "${SQLITEDEPLOY_REF}" \
        https://github.com/Khangdang1690/sqlitedeploy.git /src
WORKDIR /src
# Binary embeds linux-amd64 sqld via go:embed at compile time.
RUN go build -trimpath -ldflags='-s -w' -o /out/sqlitedeploy ./cmd/sqlitedeploy


# ─── Stage 2: build the Astro site ──────────────────────────────────────
FROM node:22-slim AS builder
WORKDIR /app
RUN corepack enable && corepack prepare pnpm@10 --activate
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile
COPY . .
# postbuild indexer no-ops here because LIBSQL_URL is unset; we run it at
# runtime once sqld is up (see entry.sh).
RUN pnpm build


# ─── Stage 3: runtime ───────────────────────────────────────────────────
FROM node:22-slim AS runtime
WORKDIR /app

# curl: entry.sh probes sqld's /health.
# ca-certificates: TLS to Cloudflare R2.
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl ca-certificates && \
    rm -rf /var/lib/apt/lists/*

COPY --from=sqlitedeploy-builder /out/sqlitedeploy /usr/local/bin/sqlitedeploy
COPY --from=builder /app/dist            ./dist
COPY --from=builder /app/node_modules    ./node_modules
COPY --from=builder /app/package.json    ./package.json
COPY --from=builder /app/scripts         ./scripts
COPY --from=builder /app/src/content/docs ./src/content/docs
COPY entry.sh ./entry.sh
RUN chmod +x ./entry.sh

ENV NODE_ENV=production \
    HOST=0.0.0.0 \
    PORT=4321 \
    LIBSQL_URL=http://127.0.0.1:8080

EXPOSE 4321
ENTRYPOINT ["./entry.sh"]
