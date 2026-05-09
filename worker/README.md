# sqlitedeploy-docs-worker

Cloudflare Worker that proxies the docs site from a free `*.workers.dev`
hostname to the Oracle VM. Lets us run on free tiers without buying a domain.

## What this gives you

- Permanent HTTPS URL: `https://sqlitedeploy-docs.<your-account>.workers.dev`
- Free TLS handled by Cloudflare's edge
- Free CDN edge cache (static assets cached for a year, doc pages for 60 s)
- 100 000 requests/day free (well above docs-site traffic)
- Origin VM stays on plain HTTP — no Caddy TLS config, no Origin Cert

## Setup (one-time)

```bash
cd worker
pnpm install

# Authenticate Wrangler against your Cloudflare account.
pnpm exec wrangler login

# Generate a shared secret for the Worker → VM hop. Save it; you'll paste
# the same value into /etc/caddy/Caddyfile on the Oracle VM later.
openssl rand -hex 32

# Store the secret in the Worker. (The CLI prompts you to paste it.)
pnpm exec wrangler secret put WORKER_SECRET
```

## Configure the origin

Edit [`wrangler.toml`](./wrangler.toml) and set `ORIGIN` to your Oracle VM:

```toml
[vars]
ORIGIN = "http://152.67.1.2"   # your VM's public IP, plain HTTP
```

## Deploy

```bash
pnpm deploy
```

Wrangler prints the public URL — bookmark it.

## Local dev

```bash
pnpm dev
```

`wrangler dev` starts the Worker on `http://127.0.0.1:8787`. Set
`ORIGIN=http://localhost:4321` in `wrangler.toml` for local dev so the
Worker hits a locally-running `astro dev`.

## How the shared secret works

The Worker forwards a header `X-Worker-Secret: <value>` on every upstream
request. Caddy on the VM is configured to reject any request that doesn't
carry that header, which prevents people who learn the VM's IP from
bypassing the Worker (and your free-tier metering).

To rotate the secret:

1. Generate new value: `openssl rand -hex 32`
2. `wrangler secret put WORKER_SECRET` and paste it
3. Update `/etc/caddy/Caddyfile` on the VM with the new value
4. `sudo systemctl reload caddy`
