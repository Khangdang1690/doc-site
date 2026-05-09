# Deploy artifacts

This directory contains the files you copy onto the Oracle Cloud VM.
None of these run locally — they're for the production host.

The public ingress is a [Cloudflare Worker](../worker/) on a free
`*.workers.dev` hostname; the VM itself stays on plain HTTP behind a
shared-secret check.

## Architecture (free-tier topology)

```
  User
    ↓ HTTPS (free, Cloudflare edge cert)
  Cloudflare Worker  →  sqlitedeploy-docs.<your-account>.workers.dev
    │
    │  HTTP (over public internet) + X-Worker-Secret header
    ↓
  Oracle VM port 80
    ↓
  Caddy (plain HTTP, validates X-Worker-Secret, gzip, logs)
    ↓
  Astro Node SSR :4321
    ↓
  sqld :8080 (loopback only)
    ↓
  bottomless WAL → Cloudflare R2 bucket (10 GB free)
```

No domain, no Origin Certificate, no Let's Encrypt — Cloudflare's free
edge cert covers TLS at the Worker.

## What goes where

| File in this repo | Path on the VM | Notes |
|---|---|---|
| `Caddyfile` | `/etc/caddy/Caddyfile` | Replace `WORKER_SECRET_HERE` with the value you stored in `wrangler secret put`. |
| `systemd/sqlitedeploy.service` | `/etc/systemd/system/sqlitedeploy.service` | Runs `sqlitedeploy up --no-tunnel` as the `sqld` user. |
| `systemd/docs-site.service` | `/etc/systemd/system/docs-site.service` | Runs the Astro Node SSR server as the `docs` user. |
| `env.example` | `/opt/docs/env` (renamed) | Paste the real `replica.jwt` value here, then `chmod 600`. |
| `deploy.sh` | `/opt/docs/deploy.sh` | `chmod +x` it. Run as the `docs` user. |

## First-time host setup

```bash
# 1. Open Oracle's VCN ingress (TCP 80 from 0.0.0.0/0) in the
#    Cloud console, AND open Ubuntu's iptables on the VM:
sudo iptables -I INPUT 6 -p tcp --dport 80 -j ACCEPT
sudo netfilter-persistent save

# 2. Install runtime deps.
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs caddy
sudo npm i -g sqlitedeploy pnpm

# 3. Create service users.
sudo useradd -m -s /bin/bash sqld
sudo useradd -m -s /bin/bash docs
sudo mkdir -p /opt/docs && sudo chown docs:docs /opt/docs

# 4. Bootstrap sqld interactively, then stop it.
sudo -iu sqld
mkdir -p ~/db && cd ~/db
sqlitedeploy auth login    # browser flow
sqlitedeploy up --no-tunnel  # Ctrl-C after you see the success banner
exit

# 5. Capture the replica JWT for systemd.
sudo cat /home/sqld/db/.sqlitedeploy/auth/replica.jwt   # copy the token
sudo cp deploy/env.example /opt/docs/env
sudo nano /opt/docs/env                                 # paste the token
sudo chown docs:docs /opt/docs/env && sudo chmod 600 /opt/docs/env

# 6. Install systemd units + Caddy config.
sudo cp deploy/systemd/*.service /etc/systemd/system/
sudo cp deploy/Caddyfile /etc/caddy/Caddyfile
sudo nano /etc/caddy/Caddyfile      # replace WORKER_SECRET_HERE

# 7. Clone the docs repo and run the first deploy.
sudo -iu docs
git clone https://github.com/Khangdang1690/doc-site /opt/docs/source
cp /opt/docs/source/deploy/deploy.sh /opt/docs/deploy.sh
chmod +x /opt/docs/deploy.sh
exit

# 8. Light it up.
sudo systemctl daemon-reload
sudo systemctl enable --now sqlitedeploy
sudo -u docs /opt/docs/deploy.sh
sudo systemctl reload caddy
```

## Then deploy the Worker

```bash
# On your workstation:
cd worker
pnpm install
pnpm exec wrangler login
openssl rand -hex 32 | tee /tmp/worker-secret      # save this value
pnpm exec wrangler secret put WORKER_SECRET        # paste it
nano wrangler.toml                                  # set ORIGIN to http://<VM_IP>
pnpm deploy
```

Wrangler prints the public URL — that's your docs site.

**Then** SSH back to the VM and update `/etc/caddy/Caddyfile` so its
`WORKER_SECRET_HERE` placeholder matches the value you set above:

```bash
sudo sed -i "s/WORKER_SECRET_HERE/$(cat /tmp/worker-secret)/" /etc/caddy/Caddyfile
sudo systemctl reload caddy
shred -u /tmp/worker-secret
```

## Subsequent deploys

```bash
# Docs site changes:
sudo -u docs /opt/docs/deploy.sh

# Worker changes:
cd worker && pnpm deploy
```

## Verifying

```bash
# 1. Origin reachable from the Worker (run on the VM):
curl -I -H "X-Worker-Secret: $(grep -oP 'X-Worker-Secret \K\S+' /etc/caddy/Caddyfile | head -1)" http://127.0.0.1/

# 2. Origin rejects requests without the secret (run from anywhere):
curl -I http://<VM_IP>/      # → 401 Forbidden

# 3. Public site (replace with your workers.dev hostname):
curl -I https://sqlitedeploy-docs.<your-account>.workers.dev/

# 4. Search API hits FTS5:
curl 'https://sqlitedeploy-docs.<your-account>.workers.dev/api/search?q=bottomless'

# 5. WAL replicated to R2: check Cloudflare R2 dashboard → bucket has
#    `db/` prefix objects with timestamps after your last deploy.
```
