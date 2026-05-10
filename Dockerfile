# Multi-stage Docker image for Fly.io.
#
# Three things have to come together at runtime inside the container:
#   1. A real `sqld` binary on PATH      ← downloaded from this project's GitHub Release
#   2. Our `sqlitedeploy` v2 CLI         ← built from source at a pinned tag
#   3. The built Astro site + indexer    ← built from this repo
#
# As of sqlitedeploy v0.5.1, the upstream binary on npm exposes the v2
# commands (`up`/`down`/`attach`) and `Resolve()` will download a real
# sqld from GitHub Releases on first run if the embedded binary is a
# placeholder — so neither stage 1 nor stage 2 is *strictly required*
# anymore. We keep both for two reasons:
#
#  - Stage 1 (sqld from GH Release): bakes the binary into the image so
#    container cold starts don't pay the ~30 MB GitHub Releases fetch
#    that `Resolve()` would do at first run.
#  - Stage 2 (build sqlitedeploy from source): lets this repo deploy off
#    a pinned tag between published releases. We'll switch to
#    `npm install -g sqlitedeploy@<version>` once we've shipped a few
#    pipelines successfully off the v0.6.x line.
#
# sqlitedeploy's binary resolution (internal/sqld/embed.go:Resolve) tries
# the embedded binary, then `exec.LookPath("sqld")`, then GitHub Releases.
# Putting sqld on PATH (stage 1) hits the second branch.

# ─── Stage 1: download the sqld binary from our own GitHub Release ──────
# Previously this stage was `FROM ghcr.io/tursodatabase/libsql-server`.
# Switched to pulling from our own release so the docs site has no
# build-time dependency on Turso's distribution channel. The binary
# attached to the v0.6.2 release was built on ubuntu-22.04 (GLIBC 2.35)
# by .github/workflows/release.yml, so it runs on the bookworm-based
# runtime stage below (GLIBC 2.36).
FROM alpine:3 AS sqld-image
ARG SQLD_RELEASE=v0.6.2
RUN apk add --no-cache curl ca-certificates && \
    curl -fsSL -o /bin/sqld \
        "https://github.com/Khangdang1690/sqlitedeploy/releases/download/${SQLD_RELEASE}/sqld-linux-amd64" && \
    chmod +x /bin/sqld

# ─── Stage 2: build sqlitedeploy v2 CLI from source ─────────────────────
# Pin to a published tag so BuildKit's cache key on the `git clone` step is
# stable per release. Bumping SQLITEDEPLOY_REF to a new tag busts the cache
# and pulls fresh source. Override at build time with:
#   fly deploy --build-arg SQLITEDEPLOY_REF=main
# to deploy off the upstream main between releases.
FROM golang:1.25-bookworm AS sqlitedeploy-builder
ARG SQLITEDEPLOY_REF=v0.6.2
RUN apt-get update && \
    apt-get install -y --no-install-recommends git ca-certificates && \
    rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 --branch "${SQLITEDEPLOY_REF}" \
        https://github.com/Khangdang1690/sqlitedeploy.git /src
WORKDIR /src
RUN go build -trimpath -ldflags='-s -w' -o /out/sqlitedeploy ./cmd/sqlitedeploy

# ─── Stage 3: build the Astro site ──────────────────────────────────────
FROM node:22-slim AS builder
WORKDIR /app
RUN corepack enable && corepack prepare pnpm@10 --activate
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile
COPY . .
# postbuild indexer no-ops here (LIBSQL_URL unset). Real reindex runs at
# container start (see entry.sh).
RUN pnpm build

# ─── Stage 4: runtime ───────────────────────────────────────────────────
FROM node:22-slim AS runtime
WORKDIR /app

# curl: entry.sh probes sqld's /health.
# ca-certificates: TLS to Cloudflare R2.
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl ca-certificates && \
    rm -rf /var/lib/apt/lists/*

COPY --from=sqld-image            /bin/sqld           /usr/local/bin/sqld
COPY --from=sqlitedeploy-builder  /out/sqlitedeploy   /usr/local/bin/sqlitedeploy

COPY --from=builder /app/dist             ./dist
COPY --from=builder /app/node_modules     ./node_modules
COPY --from=builder /app/package.json     ./package.json
COPY --from=builder /app/scripts          ./scripts
COPY --from=builder /app/src/content/docs ./src/content/docs
COPY entry.sh ./entry.sh
RUN chmod +x ./entry.sh

ENV NODE_ENV=production \
    HOST=0.0.0.0 \
    PORT=4321 \
    LIBSQL_URL=http://127.0.0.1:8080

EXPOSE 4321
ENTRYPOINT ["./entry.sh"]
