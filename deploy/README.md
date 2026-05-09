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

## Upstream sqlitedeploy fixes that landed in v0.5.1

While bringing this site up we found three real bugs in the
sqlitedeploy repo. All three landed upstream in v0.5.1 (issues
[#4](https://github.com/Khangdang1690/sqlitedeploy/issues/4),
[#5](https://github.com/Khangdang1690/sqlitedeploy/issues/5),
[#6](https://github.com/Khangdang1690/sqlitedeploy/issues/6)):

1. **npm `sqlitedeploy@latest` now ships v2** — the v0.5.1 tag pushed
   the existing release pipeline through `npm publish`, so
   `npm install -g sqlitedeploy` finally exposes the v2 commands
   (`up`, `down`, `attach`, `dev`, `auth`, `status`).
2. **`go install` works without `make build-sqld`** — `Resolve()` now
   adds a third fallback after the PATH lookup: download the
   matching real `sqld` from this repo's GitHub Release on first run
   (cached under the user cache dir). The npm/pip/Maven packages
   still ship `sqld` embedded — the fallback only kicks in for
   `go install` and source builds.
3. **`LIBSQL_BOTTOMLESS_AWS_DEFAULT_REGION` is set correctly** — the
   `envRegion` constant in `internal/sqld/env.go` was renamed to
   match what sqld v0.24.32 actually reads. R2 deployments no longer
   need to export the env var manually.

### What this repo no longer needs

- The two `export LIBSQL_BOTTOMLESS_AWS_DEFAULT_REGION=auto` lines in
  `entry.sh` (removed) — sqlitedeploy v0.5.1 sets the right name itself.

### What this repo still does (by choice, not by workaround)

- **Dockerfile pulls sqld from `ghcr.io/tursodatabase/libsql-server:v0.24.32`** —
  faster cold starts than letting v2's runtime fallback download from
  GitHub Releases on the first container boot. The fallback exists, we
  just prefer baking the binary in for container images.
- **Dockerfile builds `sqlitedeploy` from GitHub source instead of
  `npm install -g sqlitedeploy@<version>`** — lets the docs-site
  deploy track changes on `main` between published releases. We'll
  switch to pinning a tagged npm version once v0.5.1's release
  pipeline has shipped one full cycle successfully.
