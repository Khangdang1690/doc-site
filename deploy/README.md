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
