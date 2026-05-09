#!/bin/bash
# Container entry point. Runs both daemons inside one Fly Machine:
#   1. sqlitedeploy (which spawns sqld + bottomless) — backgrounded
#   2. Astro Node SSR server — backgrounded so this script stays PID 1
#      and can forward signals on Fly's graceful shutdown.
#
# Persistent state lives in /data (a Fly Volume).

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

# Workaround: sqld v0.24.32 demands LIBSQL_BOTTOMLESS_AWS_DEFAULT_REGION
# (AWS SDK naming convention), but sqlitedeploy's BottomlessEnv only sets
# LIBSQL_BOTTOMLESS_AWS_REGION. Without this, sqld errors out with
# "Internal Error: `LIBSQL_BOTTOMLESS_AWS_DEFAULT_REGION was not set`"
# during namespace creation. R2's region is always "auto".
# We set these in os.Environ() so they propagate through sqlitedeploy's
# Cmd.Env merge (BottomlessEnv overrides take precedence, but neither of
# these names is in BottomlessEnv).
export LIBSQL_BOTTOMLESS_AWS_DEFAULT_REGION=auto
export AWS_DEFAULT_REGION=auto

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

# Cleanup function: forward TERM to both children, wait, exit.
shutdown() {
    echo "[entry] received signal, shutting down…"
    if [[ -n "${ASTRO_PID:-}" ]]; then kill -TERM "$ASTRO_PID" 2>/dev/null || true; fi
    if [[ -n "${SQLD_PID:-}" ]]; then kill -TERM "$SQLD_PID" 2>/dev/null || true; fi
    wait
    exit 0
}
trap shutdown SIGTERM SIGINT

# Wait for sqld to listen AND for the JWT bootstrap to finish.
echo "[entry] waiting for sqld at 127.0.0.1:8080 + JWT bootstrap…"
ready=false
for i in $(seq 1 60); do
    if curl -fsS -o /dev/null http://127.0.0.1:8080/health 2>/dev/null \
       && [[ -s /data/.sqlitedeploy/auth/replica.jwt ]]; then
        ready=true
        echo "[entry] sqld is up after ${i}s."
        break
    fi
    if ! kill -0 "$SQLD_PID" 2>/dev/null; then
        echo "[entry] FATAL: sqld exited during startup. Check fly logs for sqld output." >&2
        exit 1
    fi
    sleep 1
done
if [[ "$ready" != "true" ]]; then
    echo "[entry] FATAL: sqld didn't become ready within 60s." >&2
    kill -TERM "$SQLD_PID" 2>/dev/null || true
    exit 1
fi

# Reindex docs into FTS5. Best-effort — Astro can still serve pages even
# if reindex fails (only /api/search would 500).
export LIBSQL_URL="http://127.0.0.1:8080"
export LIBSQL_AUTH_TOKEN="$(cat /data/.sqlitedeploy/auth/replica.jwt)"
cd /app
echo "[entry] running FTS5 reindex…"
./node_modules/.bin/tsx scripts/index-search.ts \
    || echo "[entry] reindex failed; search will be unavailable until next deploy."

# Start Astro in background so this shell stays PID 1 with the trap intact.
echo "[entry] starting Astro Node SSR…"
node ./dist/server/entry.mjs &
ASTRO_PID=$!

# Wait for either child to exit. If one dies, take the whole container down
# so Fly restarts us cleanly.
wait -n "$SQLD_PID" "$ASTRO_PID"
EXIT_CODE=$?
echo "[entry] a child exited (code=$EXIT_CODE); shutting down."
shutdown
