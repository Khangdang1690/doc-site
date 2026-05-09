# Fly.io deploy — click-by-click

Time budget: **~25 minutes**. Cost: **~$2/mo** ($24/yr).

You'll do three things:
1. Create a Cloudflare R2 bucket + API token
2. Install `flyctl` and create the Fly app
3. Set Fly secrets and run `fly deploy`

---

## 1. Cloudflare R2 setup

You need: a bucket, an Account ID, and an R2 API token (Access Key + Secret).

### 1a. Create the bucket

1. Go to https://dash.cloudflare.com/ and sign in.
2. Left sidebar: click **R2 Object Storage**.
3. If this is your first time using R2, you'll see "Get started with R2" — click it.
   You'll be asked to add a payment method (R2 stays $0 within the free tier;
   the card is for overage protection).
4. Click **Create bucket**.
5. **Bucket name**: `sqlitedeploy-docs-db` (must be globally unique within
   your account; pick anything you'll remember).
6. **Location hint**: pick the region nearest to your Fly primary region.
   `iad` Fly region pairs with `ENAM` (Eastern North America) on R2.
7. Click **Create bucket**. Leave it empty.

### 1b. Capture the Account ID

1. In the R2 dashboard, look at the **right sidebar**. You'll see
   **Account ID** with a copy button. Copy it. It looks like
   `1a2b3c4d5e6f7g8h9i0j1k2l3m4n5o6p`.
2. Save this somewhere temporary — you'll need it in step 3.

### 1c. Create an R2 API token

1. R2 dashboard → top-right: **Manage R2 API Tokens**.
2. Click **Create API token**.
3. **Token name**: `sqlitedeploy-docs-fly`.
4. **Permissions**: select **Object Read & Write**.
5. **Specify bucket**: select **Apply to specific buckets only** →
   pick `sqlitedeploy-docs-db`.
6. **TTL**: leave **Forever**.
7. Click **Create API Token**.
8. **CRITICAL**: copy the **Access Key ID** and **Secret Access Key**
   immediately. They're shown only once. Save them in a password manager.

You now have four pieces of information:

```
CF_ACCOUNT_ID = ...
CF_R2_BUCKET = sqlitedeploy-docs-db
R2_ACCESS_KEY = <your access key id>
R2_SECRET_KEY = <your secret access key>
```

---

## 2. Install flyctl + create the Fly app

### 2a. Install flyctl on Windows (PowerShell)

Open **PowerShell as your normal user** (not Admin) and run:

```powershell
iwr https://fly.io/install.ps1 -useb | iex
```

After install, **close and reopen PowerShell** so `fly` is on your PATH.

Verify:
```powershell
fly version
```

### 2b. Sign up / log in

```powershell
fly auth signup
```

This opens a browser. Create a Fly account (you'll be asked for a credit
card — required, but you'll only be charged for usage above the free
allowances which we won't hit).

If you already have an account:
```powershell
fly auth login
```

### 2c. Create the app

From inside the docs-site repo:

```powershell
cd C:\Users\khang\OneDrive\Desktop\docs-site
fly apps create sqlitedeploy-docs --org personal
```

If `sqlitedeploy-docs` is taken, pick another name and update the `app =`
line in [`fly.toml`](../fly.toml).

### 2d. Create the persistent volume

```powershell
fly volumes create data --app sqlitedeploy-docs --region iad --size 1 --yes
```

`--size 1` = 1 GB. Free tier covers up to 3 GB per org.

The first 1 GB volume is free. Skipping `--yes` shows a warning that
single-volume setups have no HA — for a docs site that's fine.

---

## 3. Set Fly secrets

Paste in the four R2 values from step 1:

```powershell
fly secrets set --app sqlitedeploy-docs `
  CF_ACCOUNT_ID="..." `
  CF_R2_BUCKET="sqlitedeploy-docs-db" `
  R2_ACCESS_KEY="<your access key id>" `
  R2_SECRET_KEY="<your secret access key>"
```

> Don't paste real secrets into chat or commit them. They live only on
> Fly's encrypted secret store after this command.

---

## 4. Deploy

```powershell
fly deploy --app sqlitedeploy-docs
```

This will:
1. Build the Docker image (~3–5 minutes the first time)
2. Push it to Fly's registry
3. Boot a Machine, mount the volume at `/data`, run `entry.sh`
4. Run health checks until the Astro `/` route returns 200

When it's done, Fly prints your public URL — `https://sqlitedeploy-docs.fly.dev`.

---

## 5. Verify

```powershell
# Public site loads:
curl.exe -I https://sqlitedeploy-docs.fly.dev/

# Search API hits FTS5:
curl.exe "https://sqlitedeploy-docs.fly.dev/api/search?q=bottomless"

# Watch logs:
fly logs --app sqlitedeploy-docs
```

In the Cloudflare R2 dashboard → bucket → **Objects** tab, you should
see a `db/` prefix populated with `.frames` / `.gen` objects within
~10 seconds of the first deploy. That's bottomless replicating the WAL
to your bucket.

---

## 6. Subsequent deploys (GitHub Actions CI/CD)

Once the first deploy works manually, set up auto-deploy on every push
to `main`. The workflow file
[`.github/workflows/fly-deploy.yml`](../.github/workflows/fly-deploy.yml)
is already in this repo; you just need to give it a Fly token.

```powershell
# 1. Generate a long-lived deploy token (only `deploy` scope, only this app).
fly tokens create deploy -x 999999h -a sqlitedeploy-docs

# Output looks like:  FlyV1 fm2_lJP...long string...
# Copy the entire string including "FlyV1 ".

# 2. Save it as a GitHub Actions secret. Don't paste it into chat.
gh secret set FLY_API_TOKEN --app actions
# When prompted, paste the token. (Or use the GitHub web UI:
# Settings → Secrets and variables → Actions → New repository secret.)
```

That's the whole CI/CD setup. From now on:

```bash
git push origin main      # triggers the workflow, which runs `fly deploy`
```

You can still deploy manually whenever you want — the manual command
keeps working in parallel with CI:

```powershell
fly deploy --app sqlitedeploy-docs
```

Both paths use the same `fly.toml` and `Dockerfile`, so they're
equivalent. **Do not** use Fly's web-UI "Auto-deploy from GitHub"
feature — it overrides `fly.toml` settings (notably `internal_port`,
which it forces to 8080) and breaks the deploy.

---

## Cost monitoring

```powershell
fly billing                        # current bill
fly status --app sqlitedeploy-docs # machine state, last events
```

Set a budget alert at https://fly.io/dashboard/personal/billing →
**Spending limit**. Recommend $5/mo as a hard cap; you should never get
near it.

---

## Memory tuning

We're running on **256 MB RAM** to minimize cost. If `fly logs` shows
`Out of memory: Kill process` or the Machine restart-loops:

1. Edit [`fly.toml`](../fly.toml): change `memory = "256mb"` → `"512mb"`.
2. `fly deploy --app sqlitedeploy-docs`.
3. New cost: ~$3.32/mo (still cheap, +$1.30/mo).

Indicators that 256 MB is too tight: search API timeouts during indexing,
random 502s under any concurrent load, `fly machine status` showing
`exit_event = "OOMKilled"`.

---

## Common gotchas (with what we actually hit during first deploy)

| Symptom in `fly logs` | Cause | Fix |
|---|---|---|
| `error: unknown command "up" for "sqlitedeploy"` | npm `sqlitedeploy@latest` was v1 (uses `run`); v2 published in v0.5.1 ([#4](https://github.com/Khangdang1690/sqlitedeploy/issues/4)). | Fixed in sqlitedeploy v0.5.1; this repo's Dockerfile still clones from source so deploys can track `main` between releases. |
| `error: no sqld binary available for linux/amd64` | Committed `internal/sqld/bin/sqld-*` are placeholders; pre-v0.5.1 builds had no fallback ([#5](https://github.com/Khangdang1690/sqlitedeploy/issues/5)). | Fixed in sqlitedeploy v0.5.1 (`Resolve()` now downloads from GitHub Releases on first run); this repo's Dockerfile still pulls sqld from `ghcr.io/tursodatabase/libsql-server:v0.24.32` to keep cold starts fast. |
| `Internal Error: LIBSQL_BOTTOMLESS_AWS_DEFAULT_REGION was not set` | Pre-v0.5.1, `BottomlessEnv()` set the wrong env var name ([#6](https://github.com/Khangdang1690/sqlitedeploy/issues/6)). | Fixed in sqlitedeploy v0.5.1 — the `envRegion` constant now matches what sqld v0.24.32 reads. |
| `error: app name is taken` on `fly apps create` | Pick a different name; update `app =` in `fly.toml`. |
| Build fails with "no space left on device" | Layer cache full | `fly deploy --build-only`, then `fly deploy --image <ref>`. |
| Cold-start times out healthcheck | sqld first-time bootstrap can take >30s | Increase `grace_period` in `fly.toml` to `60s`. |
| sqld won't start: `bucket not found` | Bucket name in Fly secrets ≠ bucket created in R2 step 1a | `fly secrets list -a sqlitedeploy-docs`; reset `CF_R2_BUCKET` if mismatched. |
| `Permission denied: ENOENT /data/.sqlitedeploy` | Volume not mounted | `fly volumes list -a sqlitedeploy-docs`; if missing, `fly volumes create data --region iad --size 1`. |
| Machine restart-loops to "max restart count of 10" | Container exited 10 times in a row | Read the actual error above the loop. After 10 fails Fly stops retrying — every line *before* "max restart count" is the real failure. |
| Lease conflict: `machine ID … lease currently held by … @tokens.fly.io` | Fly's web UI Launch wizard holds leases that block CLI deploys | Use ONLY `fly deploy` from CLI; never click through Fly's "Launch app" wizard a second time. |
| Warning `app is not listening on 0.0.0.0:8080` | Fly's generic warning when no listener is detected — does NOT mean port mismatch | Ignore the port number in the warning text; check why nothing is listening at all. |

---

## Tearing it down

```powershell
fly apps destroy sqlitedeploy-docs
fly volumes list --app sqlitedeploy-docs   # confirm the volume is gone too
```

Then in Cloudflare: delete the R2 bucket and revoke the API token.
