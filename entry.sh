#!/bin/bash
# Container entry point. Runs both daemons inside one Fly Machine:
#   1. sqlitedeploy (which spawns sqld + bottomless) — backgrounded
#   2. Astro Node SSR server — foreground
#
# Persistent state lives in /data (a Fly Volume). On cold start, sqld
# replays from R2 if the volume is empty.

set -euo pipefail

# Required Fly secrets:
#   R2_ACCESS_KEY    — R2 API token "Access Key ID"
#   R2_SECRET_KEY    — R2 API token "Secret Access Key"
#   CF_ACCOUNT_ID    — Cloudflare account ID
#   CF_R2_BUCKET     — pre-created R2 bucket name
: "${R2_ACCESS_KEY:?Set with: fly secrets set R2_ACCESS_KEY=...}"
: "${R2_SECRET_KEY:?Set with: fly secrets set R2_SECRET_KEY=...}"
: "${CF_ACCOUNT_ID:?Set with: fly secrets set CF_ACCOUNT_ID=...}"
: "${CF_R2_BUCKET:?Set with: fly secrets set CF_R2_BUCKET=...}"

mkdir -p /data
cd /data

# Spawn sqld (via sqlitedeploy) in the background.
# --byo-storage skips the managed-R2 OAuth flow (we have raw creds).
# --no-tunnel keeps sqld on loopback (Fly's edge fronts our public port).
SQLITEDEPLOY_ACCESS_KEY="$R2_ACCESS_KEY" \
SQLITEDEPLOY_SECRET_KEY="$R2_SECRET_KEY" \
sqlitedeploy up \
    --byo-storage \
    --no-tunnel \
    --provider r2 \
    --bucket "$CF_R2_BUCKET" \
    --account-id "$CF_ACCOUNT_ID" \
    --http-listen-addr 127.0.0.1:8080 &
SQLD_PID=$!

# Forward SIGTERM/SIGINT to sqld so Fly's graceful shutdown works.
trap 'kill -TERM "$SQLD_PID" 2>/dev/null || true' SIGTERM SIGINT

# Wait for sqld to listen (~3 s on warm boot, up to 30 s on cold restore).
echo "[entry] waiting for sqld at 127.0.0.1:8080…"
for i in $(seq 1 60); do
    if curl -fsS -o /dev/null http://127.0.0.1:8080/health 2>&1; then
        echo "[entry] sqld is up after ${i}s."
        break
    fi
    if ! kill -0 "$SQLD_PID" 2>/dev/null; then
        echo "[entry] FATAL: sqld exited during startup." >&2
        exit 1
    fi
    sleep 1
done

# Reindex docs into FTS5. Best-effort — Astro can still serve pages even
# if reindex fails (only /api/search would 500).
export LIBSQL_URL="http://127.0.0.1:8080"
export LIBSQL_AUTH_TOKEN="$(cat /data/.sqlitedeploy/auth/replica.jwt)"
cd /app
echo "[entry] running FTS5 reindex…"
node node_modules/tsx/dist/cli.mjs scripts/index-search.ts || \
    echo "[entry] reindex failed; search will be unavailable until next deploy."

# Start Astro in foreground so PID 1 propagates signals naturally.
echo "[entry] starting Astro Node SSR…"
exec node ./dist/server/entry.mjs
