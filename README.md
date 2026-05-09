# docs-site

Documentation website for [`sqlitedeploy`](https://github.com/Khangdang1690/sqlitedeploy),
powered by `sqlitedeploy` itself.

The site is built with **Astro Starlight** and runs in hybrid mode (static
pages + a single SSR API route) on the Node adapter. Search is backed by
**SQLite FTS5** inside a sqld instance; the index is rebuilt at every
build by `scripts/index-search.ts`. WAL replicates to **Cloudflare R2**
via bottomless. Everything lives on **Oracle Cloud Always Free**
(Ampere A1 ARM, 4 OCPU / 24 GB).

## Stack

| Layer | Choice |
|---|---|
| Framework | Astro 6 + Starlight 0.39 |
| Runtime | Node 20 (Astro `@astrojs/node` standalone) |
| DB | sqld (via `sqlitedeploy up --no-tunnel`) |
| Search | SQLite FTS5 (`docs_fts` virtual table) |
| Object storage | Cloudflare R2 (10 GB free, $0 egress) |
| TLS / proxy | Caddy + Cloudflare Origin Certificate |
| Edge / CDN | Cloudflare proxy (orange cloud) |
| Host | Oracle Cloud Always Free Ampere A1 |

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

See [`deploy/README.md`](./deploy/README.md) for the Oracle Cloud +
Cloudflare setup walkthrough. tl;dr:

1. Create a Cloudflare account → register a domain → set DNS to Cloudflare,
   SSL/TLS to **Full (strict)**, generate an Origin Certificate.
2. Provision an Oracle Cloud Ampere A1 VM (Ubuntu 22.04 ARM64). Open ports
   80 + 443 in the VCN security list **and** in iptables.
3. SSH in. Install Node, pnpm, Caddy, and `npm i -g sqlitedeploy`.
4. As the `sqld` user: `sqlitedeploy auth login` then
   `sqlitedeploy up --no-tunnel`. Capture the replica JWT.
5. Drop in the systemd units, Caddyfile, and Origin Certificate from
   `deploy/`. `systemctl enable --now sqlitedeploy docs-site caddy`.
6. Run `deploy/deploy.sh` to build + reindex + start.

## Project layout

```
docs-site/
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
│   └── index-search.ts           # Build-time indexer; postbuild script
├── deploy/                       # Files to ship to the Oracle VM
│   ├── Caddyfile
│   ├── env.example
│   ├── deploy.sh
│   └── systemd/
│       ├── sqlitedeploy.service
│       └── docs-site.service
└── package.json
```

## How search works

```
  ┌─────────────────────────────────────┐
  │  Build time (on the VM)             │
  │  ─────────                          │
  │  pnpm build                         │
  │   └─ astro build  → dist/           │
  │   └─ postbuild    → tsx scripts/index-search.ts
  │                       │             │
  │                       ▼             │
  │  sqld :8080 ─── INSERT INTO docs_fts (slug,title,description,body)
  │   │                                 │
  │   ▼ bottomless (async)              │
  │  Cloudflare R2 bucket               │
  └─────────────────────────────────────┘

  ┌─────────────────────────────────────┐
  │  Request time                       │
  │  ────────────                       │
  │  GET /api/search?q=replicas         │
  │   └─ Astro Node SSR (/api/search.ts)│
  │       └─ libsql client → sqld :8080 │
  │           └─ SELECT … FROM docs_fts │
  │              WHERE docs_fts MATCH ? │
  │                                     │
  │  → JSON: [{ slug, title, snippet }] │
  └─────────────────────────────────────┘
```

The build inserts; sqld (running on the same VM) serves reads. The user
sees a search box that talks to `/api/search`, which Caddy proxies to
Astro on `127.0.0.1:4321`, which queries sqld on `127.0.0.1:8080`.

## License

MIT.
