# docs-site

**Live: https://sqlitedeploy-docs.fly.dev**

Documentation website for [`sqlitedeploy`](https://github.com/Khangdang1690/sqlitedeploy),
powered by `sqlitedeploy` itself.

The site is built with **Astro Starlight** and runs in hybrid mode (static
pages + a single SSR API route) on the Node adapter. Search is backed by
**SQLite FTS5** inside a sqld instance; the index is rebuilt on every
boot by `scripts/index-search.ts`. WAL replicates to **Cloudflare R2**
via bottomless. Everything runs as a single **Fly.io** Machine.

## Stack

| Layer | Choice |
|---|---|
| Framework | Astro 6 + Starlight 0.39 |
| Runtime | Node 22 (Astro `@astrojs/node` standalone) |
| DB | sqld (via `sqlitedeploy up --byo-storage --ingress=listen`) |
| Search | SQLite FTS5 (`docs_fts` virtual table) |
| Object storage | Cloudflare R2 (10 GB free, $0 egress) |
| Host | Fly.io shared-cpu-1x, 256 MB RAM |
| Public URL | `https://<app>.fly.dev` (free TLS, free hostname) |
| **Total cost** | **~$2/mo** (~$24/yr) |

## Local dev

```bash
pnpm install
pnpm dev          # http://localhost:4321
```

Search will return `500 Internal Server Error` locally because
`LIBSQL_URL` is unset. To exercise it end-to-end:

```bash
# In one terminal:
sqlitedeploy dev

# In another:
export LIBSQL_URL=http://127.0.0.1:8080
export LIBSQL_AUTH_TOKEN=any-string-works-in-dev-mode
pnpm reindex      # populates docs_fts in the local sqld
pnpm dev
```

## Production deploy

See [`deploy/fly-setup.md`](./deploy/fly-setup.md) for the full
click-by-click walkthrough. tl;dr:

1. Cloudflare R2: create a bucket, generate an API token, capture
   `CF_ACCOUNT_ID` + bucket name + access/secret keys.
2. Install `flyctl` (one-line PowerShell installer).
3. `fly apps create sqlitedeploy-docs` and
   `fly volumes create data --region iad --size 1`.
4. `fly secrets set CF_ACCOUNT_ID=… CF_R2_BUCKET=… R2_ACCESS_KEY=… R2_SECRET_KEY=…`.
5. `fly deploy`. Wait ~5 minutes. Hit the printed URL.

## Project layout

```
docs-site/
├── Dockerfile                    # Multi-stage Docker build for Fly
├── entry.sh                      # Container entrypoint: starts sqld, reindexes, execs Astro
├── fly.toml                      # Fly app config (256 MB, 1 GB volume, scale-to-zero)
├── astro.config.mjs              # Starlight config + Node adapter
├── src/
│   ├── content/docs/
│   │   ├── index.mdx             # Landing page
│   │   ├── guides/*.mdx          # Quickstart, How-it-works, BYO storage, …
│   │   └── reference/*.mdx       # CLI reference (up, down, attach, dev, auth, status)
│   ├── components/
│   │   └── SearchBox.astro       # Replaces Starlight's default search
│   └── pages/
│       └── api/
│           └── search.ts         # SSR endpoint, runs FTS5 query
├── scripts/
│   └── index-search.ts           # FTS5 indexer; runs at container boot
├── deploy/
│   ├── README.md                 # Architecture + summary
│   └── fly-setup.md              # Click-by-click deploy walkthrough
└── package.json
```

## How search works

```
  ┌─────────────────────────────────────┐
  │  Container boot (Fly Machine starts)│
  │  ─────────                          │
  │  entry.sh                           │
  │   ├─ sqlitedeploy up --byo-storage  │
  │   │    └─ sqld :8080 (loopback)     │
  │   ├─ wait for sqld /health          │
  │   ├─ tsx scripts/index-search.ts    │
  │   │    └─ INSERT INTO docs_fts …    │
  │   │           ↓ bottomless (async)  │
  │   │       Cloudflare R2 bucket      │
  │   └─ exec node ./dist/server/entry.mjs (Astro foreground)
  └─────────────────────────────────────┘

  ┌─────────────────────────────────────┐
  │  Request time                       │
  │  ────────────                       │
  │  GET /api/search?q=replicas         │
  │   └─ Astro Node SSR (/api/search.ts)│
  │       └─ libsql client → 127.0.0.1:8080
  │           └─ SELECT … FROM docs_fts │
  │              WHERE docs_fts MATCH ? │
  │                                     │
  │  → JSON: [{ slug, title, snippet }] │
  └─────────────────────────────────────┘
```

A user hits `https://<app>.fly.dev/api/search?q=…`; Fly's edge proxy
terminates TLS and forwards over Fly's internal network to the Machine
on port 4321; Astro's API route opens a libsql client to `127.0.0.1:8080`
on the same Machine; sqld serves the FTS5 query out of the SQLite file
on the mounted volume.

## License

MIT.
