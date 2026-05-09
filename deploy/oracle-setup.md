# Oracle Cloud Always Free — click-by-click setup

This guide walks through the Oracle Cloud Console step by step for someone
who's never used it. Time budget: **~45 minutes** (most of which is
account verification waiting).

If you already have an Oracle Cloud account and an Ampere A1 VM running,
[skip ahead to the deploy README](./README.md).

---

## 1. Create the account

Go to https://www.oracle.com/cloud/free/ and click **Start for free**.

You'll fill in:

- Country/territory — pick where you actually live; this **locks your
  home region** and you can't change it later.
- Email + first/last name.
- Account type: **Individual**.
- Address + phone (real ones — they SMS-verify).
- A credit card (for identity check). Oracle places a **temporary $1
  authorization hold** that's released within 7 days. They will **not**
  charge you unless you upgrade to "Pay as you go".
- Password.

After submitting you'll see "Verifying your account…". This usually takes
**5–10 minutes**. Refresh occasionally; you'll get an email when the
account is ready.

> **Region tip.** Oracle's home region defines where your free Ampere A1
> capacity comes from. The popular regions (Frankfurt, Ashburn, Phoenix)
> are heavily oversubscribed — you may hit "Out of host capacity"
> errors when creating the VM (see [section 5](#5b-out-of-host-capacity-errors-known-issue)).
> Less-loaded regions: **Sao Paulo (gru)**, **Mumbai (bom)**,
> **Hyderabad (hyd)**, **Zurich (zrh)**. If you don't have a strong
> reason for a specific region, pick one of these.

---

## 2. First sign-in to the console

After verification you'll land on https://cloud.oracle.com/.

The first thing to do: **disable upgrade prompts** so you don't
accidentally click "Upgrade" later.

1. Top-right, click your avatar → **My profile**.
2. Note your **Tenancy name** and **OCID** somewhere — you may need them.
3. Top-right banner often says "Upgrade" — ignore it. Always-Free
   resources are tagged with a green **Always Free Eligible** badge.
   As long as you only create those, you're never charged.

---

## 3. Generate an SSH key (Windows / PowerShell)

Open **PowerShell** (Win+R → `powershell` → Enter) and run:

```powershell
ssh-keygen -t ed25519 -f $env:USERPROFILE\.ssh\oracle_a1 -C "oracle-a1-free"
```

Press Enter to skip the passphrase (or set one — your call).

You now have:

- Private key: `C:\Users\<you>\.ssh\oracle_a1`
- Public key: `C:\Users\<you>\.ssh\oracle_a1.pub`

Open the **`.pub`** file in Notepad (`notepad $env:USERPROFILE\.ssh\oracle_a1.pub`)
and copy the entire contents — one line starting with `ssh-ed25519`.
You'll paste this when creating the VM.

> Don't share `oracle_a1` (no extension). That's the private key.

---

## 4. Create the VM

In the Oracle Cloud Console:

1. Click the **hamburger menu** (☰) in the top-left.
2. Hover **Compute**, then click **Instances**.
3. Make sure the **Compartment** dropdown (left sidebar) is set to your
   root compartment (default: `<your-tenancy>` — root). Stick with this
   unless you know why you'd want a sub-compartment.
4. Click **Create instance**.

Now fill in the form, top to bottom:

### Name and compartment

- **Name**: `sqlitedeploy-docs` (or whatever).
- **Compartment**: leave as the default (root).
- **Placement → Availability domain**: leave default (`AD-1`). If you
  hit capacity errors, you'll come back and try `AD-2` / `AD-3`.

### Image and shape

- Find the **Image and shape** card. Both default to "VM.Standard.E2.1.Micro"
  (an x86 free tier, only 1 GB RAM — too small for us).
- Click **Edit** on that card.
- **Image**: click **Change image** → in the popup, find and select
  **Canonical Ubuntu 22.04** (or 24.04 — either works). Click **Select image**.
- **Shape**: click **Change shape**. In the popup:
  - Click the **Ampere** tab at the top.
  - Select **VM.Standard.A1.Flex**.
  - Drag the **Number of OCPUs** slider to **4**.
  - The **Amount of memory (GB)** field auto-jumps to **24**.
  - Confirm the green **Always Free Eligible** badge is showing.
  - Click **Select shape**.

### Networking

- Leave **Primary VNIC information** at defaults — Oracle will create a
  new VCN named `vcn-<random>` and a public subnet.
- **Public IPv4 address**: should default to **Assign a public IPv4
  address**. Confirm this is checked.

### SSH keys

- Under **Add SSH keys**, select **Paste public keys**.
- Paste the contents of `oracle_a1.pub` (from step 3) into the textarea.

### Boot volume

- Leave **Boot volume size**: 50 GB (default). You can go up to 200 GB
  always-free if you want, but 50 GB is plenty for our docs site.
- Leave encryption defaults.

### Create

- Scroll down. Click **Create**.

The instance state goes: **Provisioning** → **Starting** → **Running**
(usually 1–2 minutes).

### 5b. "Out of host capacity" errors (known issue)

If the create fails with `Out of host capacity` (very common in
Frankfurt, Ashburn, Phoenix):

1. Click **Cancel** if the dialog offers retry.
2. Try **Edit** → **Placement** → switch to a different **Availability
   domain** (AD-1 → AD-2 → AD-3). Click **Create** again.
3. If all three ADs fail, wait an hour and retry. Capacity opens up
   constantly as other free-tier users rotate.
4. Last resort: tools like
   [hitrov/oci-arm-host-capacity](https://github.com/hitrov/oci-arm-host-capacity)
   poll for capacity and create on your behalf.

There is no way to skip the queue. Don't bother contacting support — the
Always Free tier is unsupported.

---

## 5. Reserve the public IP (so it doesn't change)

By default the public IP is **ephemeral** — if you stop the VM, the IP
is released and you'll get a new one on next start. You don't want that
for a docs site. Reserve it:

1. From the **Instance details** page (where you landed after creation),
   scroll down to **Resources** in the left sidebar.
2. Click **Attached VNICs**.
3. Click the only VNIC in the list.
4. In the VNIC details, scroll to **IPv4 addresses**. Click the **⋮**
   menu next to your assigned IP → **Edit**.
5. **Public IP type**: change from **Ephemeral** to **Reserved**.
6. **Reserved Public IP**: select **Create new reserved public IP**,
   give it any name, click **Update**.

The IP value stays the same; it's just now permanent. **Write it down** —
this is what goes in `worker/wrangler.toml` as `ORIGIN`.

---

## 6. Open the VCN to inbound HTTP

Oracle's VCN blocks all inbound traffic except SSH by default. We need
TCP **80** open for the Cloudflare Worker to reach Caddy.

1. ☰ menu → **Networking** → **Virtual Cloud Networks**.
2. Click your VCN (the one named `vcn-<random>`).
3. Left sidebar: **Resources** → **Security Lists**.
4. Click **Default Security List for vcn-<random>**.
5. Click **Add Ingress Rules**.
6. Fill in:
   - **Stateless**: leave unchecked.
   - **Source Type**: `CIDR`.
   - **Source CIDR**: `0.0.0.0/0`.
   - **IP Protocol**: `TCP`.
   - **Source Port Range**: leave blank.
   - **Destination Port Range**: `80`.
   - **Description**: `HTTP from Cloudflare Worker (any source; X-Worker-Secret enforced at Caddy)`.
7. Click **Add Ingress Rules**.

> You can tighten this later by allow-listing
> [Cloudflare's IP ranges](https://www.cloudflare.com/ips/) instead of
> `0.0.0.0/0`. Skipping that simplification for now since the shared
> secret in Caddy already enforces "Worker only".

---

## 7. Connect via SSH

From PowerShell on your workstation:

```powershell
ssh -i $env:USERPROFILE\.ssh\oracle_a1 ubuntu@<YOUR_VM_PUBLIC_IP>
```

(Use `opc@` instead of `ubuntu@` if you picked an Oracle Linux image.)

You'll see "Are you sure you want to continue connecting?" the first
time — type `yes` and Enter.

If the connection hangs forever, the VCN ingress rule for port 22 is
broken (it's added by default; only break-able if you edited the
default security list). Re-check section 6.

---

## 8. Open the host firewall (Ubuntu only — Oracle gotcha)

Oracle's Ubuntu cloud images ship with iptables that **REJECT** all
inbound except SSH. Even after opening port 80 in the VCN, packets get
dropped at the OS level. Fix it:

```bash
sudo iptables -L INPUT --line-numbers
```

You'll see a numbered list. Find the line that says
`REJECT all -- anywhere anywhere reject-with icmp-host-prohibited` —
its number is usually **6**. Insert your ALLOW rule **before** that
position:

```bash
sudo iptables -I INPUT 6 -p tcp --dport 80 -j ACCEPT
sudo netfilter-persistent save
```

Verify:

```bash
sudo iptables -L INPUT --line-numbers
```

You should see your ACCEPT rule at line 6, with the REJECT now at
line 7 (or later).

> If `netfilter-persistent` isn't installed (rare):
> `sudo apt install -y iptables-persistent` and answer "yes" to both
> prompts. Then `sudo netfilter-persistent save`.

---

## 9. Confirm port 80 is reachable from the public internet

From any other machine (your phone on cellular works):

```bash
curl -v http://<YOUR_VM_PUBLIC_IP>/
```

You should get **`Connection refused`** (because nothing is listening
on 80 yet — that's good; the firewall is letting traffic through, the
service just hasn't been installed).

If you get **`Connection timed out`**: either the VCN security list
(section 6) or the iptables rule (section 8) is wrong. Walk through
both again.

---

## 10. Keep the Always Free VM from being reclaimed

Oracle reclaims Always Free Ampere VMs that stay idle for ~7 days.
The threshold is *very* low — even minimal background activity counts.

The docs-site daemons (`sqlitedeploy.service` + `docs-site.service`)
generate enough activity to count. But just to be safe, add a small
cron that touches a file every 10 minutes:

```bash
sudo crontab -e
# Add this line:
*/10 * * * * /bin/touch /tmp/keepalive
```

If Oracle does send a reclaim warning email, you have **5 days** to
respond. Just SSH in and run `uptime` — that resets the counter.

---

## You're done with Oracle

Now follow [`deploy/README.md`](./README.md) starting from
**"First-time host setup"** to install Node, Caddy, sqlitedeploy, and
bring the docs site live.
