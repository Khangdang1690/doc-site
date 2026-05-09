# Deploy

The docs site runs as a single Fly.io Machine with a 1 GB persistent
volume. WAL replicates to a Cloudflare R2 bucket via bottomless.
Public HTTPS comes free on `*.fly.dev`.

**Cost: ~$2/mo** (shared-cpu-1x @ 256 MB always-on; cheaper with scale-to-zero).

## Setup walkthrough

Follow **[fly-setup.md](./fly-setup.md)**. It's a click-by-click guide
covering Cloudflare R2, flyctl install, app + volume + secrets, and
the first deploy. ~25 minutes end-to-end.

## What's in this repo for deploys

| File | Purpose |
|---|---|
| [`../Dockerfile`](../Dockerfile) | Multi-stage build: pnpm build → Debian-slim runtime with sqlitedeploy CLI |
| [`../entry.sh`](../entry.sh) | Container entry point: starts sqlitedeploy, reindexes FTS5, execs Astro |
| [`../fly.toml`](../fly.toml) | Fly app config: 256 MB shared-cpu-1x, scale-to-zero, 1 GB volume mount |
| [`../.dockerignore`](../.dockerignore) | Excludes node_modules, dist, deploy/, etc. from the build context |

## Architecture

```
  User
    ↓ HTTPS (*.fly.dev, free TLS at edge)
  Fly proxy
    ↓ HTTP (Fly internal network)
  Fly Machine (256 MB shared-cpu-1x)
    ├─ Astro Node SSR :4321 (foreground PID 1)
    └─ sqlitedeploy + sqld :8080 (loopback only)
            ↓
        bottomless WAL replication
            ↓
        Cloudflare R2 bucket
```

The Astro process queries sqld over `127.0.0.1:8080` — same host, no
network hop. No reverse proxy on the Machine itself; Fly's edge handles
TLS, HTTP/2, and DDoS protection.

## Switching to a different host later

If you outgrow Fly or want to move:

- The persistent state lives in **two places**: the Fly Volume (mounted
  at `/data`) and the R2 bucket. Either alone is enough to rebuild.
- To move: spin up sqlitedeploy on the new host, point it at the same
  R2 bucket with `--byo-storage --provider r2 --bucket <name>` and the
  same R2 credentials, and `sqlitedeploy up --sync-from-storage`. Done.
- Update `Dockerfile`/`fly.toml` for the new host (or replace them with
  whatever the new platform expects).

## Upstream sqlitedeploy fixes worth contributing back

While bringing this site up we found three real bugs in the
sqlitedeploy repo. We worked around each one in this docs-site so the
deploy works today, but the fixes belong upstream so other users don't
hit the same wall.

### 1. npm `sqlitedeploy@latest` still ships v1

`packaging/npm/sqlitedeploy/package.json` is at v0.5.1 in the repo,
but the version published to npm is the v1 binary that exposes `run`
instead of `up`. Either run `npm publish` from the v2 source, or
delete the npm `latest` tag until v2 is ready to publish.

**Workaround in this repo**: Dockerfile builds sqlitedeploy from
github.com/Khangdang1690/sqlitedeploy at branch `main` instead of
installing from npm.

### 2. `internal/sqld/bin/sqld-linux-*` are placeholders, not real binaries

The repo commits 144-byte text files like
`PLACEHOLDER sqld-linux-amd64 — replaced by make build-sqld...` to
those paths. A `go build` of sqlitedeploy embeds these placeholders,
so the resulting binary errors out at runtime with `no sqld binary
available for linux/amd64` whenever the user hasn't run `make
build-sqld` first.

**Suggested upstream fix**: either ship pre-built binaries via Git LFS
or GitHub Releases, or add a build hook so `go install
github.com/Khangdang1690/sqlitedeploy/cmd/sqlitedeploy@latest` works.

**Workaround in this repo**: Dockerfile pulls the real sqld binary
from `ghcr.io/tursodatabase/libsql-server:v0.24.32` and puts it on
PATH, where sqlitedeploy's `Resolve()` falls back to it.

### 3. `LIBSQL_BOTTOMLESS_AWS_REGION` env var name mismatch

[`internal/sqld/env.go`](https://github.com/Khangdang1690/sqlitedeploy/blob/main/internal/sqld/env.go)
sets `LIBSQL_BOTTOMLESS_AWS_REGION`, but sqld v0.24.32 (which the
Makefile pins via `LIBSQL_VERSION ?= libsql-server-v0.24.32`) demands
`LIBSQL_BOTTOMLESS_AWS_DEFAULT_REGION` (the AWS SDK convention). sqld
fails namespace creation with `Internal Error:
LIBSQL_BOTTOMLESS_AWS_DEFAULT_REGION was not set`.

**Suggested upstream fix**: change the constant to
`LIBSQL_BOTTOMLESS_AWS_DEFAULT_REGION`, or set both names in the env
map for compatibility across sqld versions.

**Workaround in this repo**: `entry.sh` exports both env vars
explicitly before invoking sqlitedeploy, so they propagate to sqld via
`os.Environ()`.

### Once these are fixed upstream, you can simplify this repo by:

- Replacing the Dockerfile's Go builder stage with `npm install -g sqlitedeploy@<version>`
- Removing the `ghcr.io/tursodatabase/libsql-server` stage entirely (real binaries will be embedded)
- Deleting the two `export LIBSQL_BOTTOMLESS_AWS_DEFAULT_REGION=auto` lines from entry.sh
