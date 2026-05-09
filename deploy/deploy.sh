#!/usr/bin/env bash
#
# /opt/docs/deploy.sh
#
# Runs on the Oracle VM. Pulls latest source, builds, reindexes FTS5
# (the build's postbuild step), atomically swaps the new dist into place,
# and restarts the docs-site systemd unit.

set -euo pipefail

SOURCE_DIR=/opt/docs/source
CURRENT_DIR=/opt/docs/current
ENV_FILE=/opt/docs/env

if [[ ! -f "$ENV_FILE" ]]; then
	echo "Missing $ENV_FILE — copy deploy/env.example, set LIBSQL_AUTH_TOKEN, chmod 600." >&2
	exit 1
fi

cd "$SOURCE_DIR"
git pull --ff-only

# Reuse pnpm store if available; --frozen-lockfile catches lockfile drift.
pnpm install --frozen-lockfile

# Build runs the FTS5 reindexer in postbuild against the local sqld
# (LIBSQL_URL+LIBSQL_AUTH_TOKEN come from the env file).
set -a; . "$ENV_FILE"; set +a
pnpm build

# Atomic swap: rsync into a sibling, then mv. This avoids serving a
# half-written dist if the deploy is interrupted.
NEW="$CURRENT_DIR.new"
rm -rf "$NEW"
mkdir -p "$NEW"
cp -r dist node_modules package.json "$NEW/"
rm -rf "$CURRENT_DIR.old"
[[ -d "$CURRENT_DIR" ]] && mv "$CURRENT_DIR" "$CURRENT_DIR.old"
mv "$NEW" "$CURRENT_DIR"

sudo systemctl restart docs-site
echo "Deploy OK at $(date -Iseconds)"
