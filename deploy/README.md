# Deploy artifacts

This directory contains the files you copy onto the Oracle Cloud VM.
None of these run locally — they're for the production host.

## What goes where

| File in this repo | Path on the VM | Notes |
|---|---|---|
| `Caddyfile` | `/etc/caddy/Caddyfile` | Edit the hostname before installing. |
| `systemd/sqlitedeploy.service` | `/etc/systemd/system/sqlitedeploy.service` | Runs `sqlitedeploy up --no-tunnel` as the `sqld` user. |
| `systemd/docs-site.service` | `/etc/systemd/system/docs-site.service` | Runs the Astro Node SSR server as the `docs` user. |
| `env.example` | `/opt/docs/env` (renamed) | Paste the real `replica.jwt` value here, then `chmod 600`. |
| `deploy.sh` | `/opt/docs/deploy.sh` | `chmod +x` it. Run as the `docs` user. |

## First-time host setup

```bash
# 1. Open Oracle's VCN ingress (TCP 80 + 443 from 0.0.0.0/0) in the
#    Cloud console, AND open Ubuntu's iptables on the VM:
sudo iptables -I INPUT 6 -p tcp --dport 80 -j ACCEPT
sudo iptables -I INPUT 6 -p tcp --dport 443 -j ACCEPT
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
sudo mkdir -p /etc/caddy/certs
# Paste the Cloudflare Origin Certificate cert + key:
sudo nano /etc/caddy/certs/origin.pem
sudo nano /etc/caddy/certs/origin.key
sudo chmod 600 /etc/caddy/certs/origin.key

# 7. Clone the docs repo and run the first deploy.
sudo -iu docs
git clone https://github.com/<you>/docs-site /opt/docs/source
cp /opt/docs/source/deploy/deploy.sh /opt/docs/deploy.sh
chmod +x /opt/docs/deploy.sh
exit

# 8. Light it up.
sudo systemctl daemon-reload
sudo systemctl enable --now sqlitedeploy
sudo -u docs /opt/docs/deploy.sh
sudo systemctl reload caddy
```

## Subsequent deploys

```bash
sudo -u docs /opt/docs/deploy.sh
```

That's it. The script pulls, builds, reindexes FTS5, swaps the dist
atomically, and restarts the docs-site unit.

## Verifying

```bash
# 1. Caddy + Astro reachable from the VM itself.
curl -I http://127.0.0.1:4321/

# 2. Public.
curl -I https://docs.sqlitedeploy.dev/

# 3. Search API hits FTS5.
curl 'https://docs.sqlitedeploy.dev/api/search?q=bottomless'

# 4. WAL replicated to R2.
#    Check the Cloudflare R2 dashboard for the bucket — you should see
#    `db/` prefix objects with timestamps after your last deploy.
```
