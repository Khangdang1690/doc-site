# Multi-stage image: build the Astro site, then ship a slim runtime
# that runs sqlitedeploy + the Astro Node SSR server.
#
# Runtime is debian-slim (glibc) because the bundled sqld binary in the
# `sqlitedeploy` npm package is built against glibc; alpine/musl will
# segfault on load.

FROM node:22-slim AS builder
WORKDIR /app

# pnpm via corepack. python/build-essential are needed for the few packages
# that still have post-install C compiles (e.g. cpu-features in some setups).
RUN corepack enable && \
    corepack prepare pnpm@10 --activate

COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile

COPY . .
# postbuild indexer no-ops here because LIBSQL_URL is unset; we run it at
# runtime once sqld is up (see entry.sh).
RUN pnpm build


FROM node:22-slim AS runtime
WORKDIR /app

# curl: used by entry.sh to wait for sqld's /health.
# ca-certificates: TLS to Cloudflare R2.
# Pin sqlitedeploy so silent upstream changes can't break our build.
ARG SQLITEDEPLOY_VERSION=latest
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl ca-certificates && \
    rm -rf /var/lib/apt/lists/* && \
    npm install -g --omit=dev "sqlitedeploy@${SQLITEDEPLOY_VERSION}"

COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/package.json ./package.json
COPY --from=builder /app/scripts ./scripts
COPY --from=builder /app/src/content/docs ./src/content/docs
COPY entry.sh ./entry.sh
RUN chmod +x ./entry.sh

ENV NODE_ENV=production \
    HOST=0.0.0.0 \
    PORT=4321 \
    LIBSQL_URL=http://127.0.0.1:8080

EXPOSE 4321
ENTRYPOINT ["./entry.sh"]
