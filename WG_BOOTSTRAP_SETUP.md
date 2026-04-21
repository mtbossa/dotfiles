# WG Dashboard SSH-Tunneled API Bootstrap Setup

Goal: new machines running chezmoi register themselves as WireGuard peers by calling the **real WGD API** — but the API stays bound to `localhost` on the LXC and is only reachable through an SSH tunnel. No WGD exposed to the internet, no custom scripts writing to WGD's database.

**The trick:** the bootstrap SSH user can only do one thing — forward `localhost:10086` on the LXC to the client. The client then calls the WGD API as if it were local. That's it.

This assumes WGD is already running in the LXC, listening on `127.0.0.1:10086`, with an interface `wg0`. Adjust as needed.

---

## Part A — On the WGD LXC (one-time setup)

### A1. Confirm WGD listens on localhost only

WGD should bind to `127.0.0.1:10086`, not `0.0.0.0`. Check in the WGD config (typically `wg-dashboard.ini`):

```ini
[Server]
app_ip = 127.0.0.1
app_port = 10086
```

Restart WGD after changing. Verify:

```bash
ss -tlnp | grep 10086
```

**What this does:** lists TCP listening sockets so you can confirm which address WGD is bound to.
- `ss` — socket-statistics tool (replaces `netstat`).
- `-t` — TCP only.
- `-l` — listening sockets only.
- `-n` — numeric addresses/ports, don't resolve names.
- `-p` — show the owning process.
- `| grep 10086` — filter down to the WGD port.

You want to see `127.0.0.1:10086`, **not** `0.0.0.0:10086` (the latter means it's reachable from anywhere that can reach the LXC's IP).

### A2. Generate a WGD API key

In the WGD UI → **Settings** → **API Keys** → generate a new key. Copy it — you'll store it in Bitwarden in Part C.

Sanity-check the API works locally on the LXC:

```bash
curl -s http://127.0.0.1:10086/api/getWireguardConfigurations \
    -H "wg-dashboard-apikey: YOUR_API_KEY" | jq .
```

**What this does:** calls the WGD API locally (on the LXC itself) to confirm the API key and endpoint work before you try it through an SSH tunnel.
- `curl` — HTTP client.
- `-s` — silent mode, no progress bar/meters, only the response body.
- `http://127.0.0.1:10086/api/getWireguardConfigurations` — lists all WG interfaces WGD manages.
- `-H "wg-dashboard-apikey: ..."` — WGD's auth header; every API call needs this.
- `| jq .` — pretty-print the JSON response.

### A3. Create the dedicated bootstrap user

```bash
adduser --disabled-password --gecos "" --shell /usr/sbin/nologin wg-bootstrap
```

**What this does:** creates a locked-down Unix user whose only job is to receive SSH connections for port-forwarding.
- `--disabled-password` — no password login is possible (SSH key only).
- `--gecos ""` — skip the interactive "Full Name / Room Number / ..." prompts.
- `--shell /usr/sbin/nologin` — if anyone does get a session, they get kicked out immediately (no interactive shell).
- `wg-bootstrap` — the username.

```bash
mkdir -p /home/wg-bootstrap/.ssh
chmod 700 /home/wg-bootstrap/.ssh
touch /home/wg-bootstrap/.ssh/authorized_keys
chmod 600 /home/wg-bootstrap/.ssh/authorized_keys
chown -R wg-bootstrap:wg-bootstrap /home/wg-bootstrap/.ssh
```

The `700`/`600` permissions are required by sshd — it refuses to read `authorized_keys` if the directory or file is readable by other users.

### A4. Generate the bootstrap SSH keypair

Do this **on your current trusted machine** (not the LXC), so the private key can go straight into Bitwarden:

```bash
ssh-keygen -t ed25519 -f ~/wg-bootstrap-key -C "wg-bootstrap" -N ""
```

**What this does:** generates a new SSH keypair dedicated to this bootstrap flow.
- `-t ed25519` — key type; modern, short, fast, preferred over RSA.
- `-f ~/wg-bootstrap-key` — output path. Produces `wg-bootstrap-key` (private) and `wg-bootstrap-key.pub` (public).
- `-C "wg-bootstrap"` — comment embedded in the public key. Purely a label so you recognize it later.
- `-N ""` — empty passphrase. Needed because the bootstrap script must use the key non-interactively.

```bash
cat ~/wg-bootstrap-key.pub
```

Copy the single line that prints. That goes into `authorized_keys` on the LXC next.

### A5. Restrict the SSH key to port-forwarding only

On the LXC, paste the public key into `authorized_keys` with strict restrictions. This key can **only** forward `localhost:10086`, nothing else — no shell, no other ports, no agent forwarding:

```bash
cat >> /home/wg-bootstrap/.ssh/authorized_keys <<'EOF'
restrict,port-forwarding,permitopen="127.0.0.1:10086",command="/bin/sh -c 'trap : TERM; sleep infinity & wait'" ssh-ed25519 AAAA...PASTE_YOUR_PUBKEY_HERE... wg-bootstrap
EOF
```

**What the authorized_keys directives do** (these are parsed by `sshd` before the key authenticates a session):
- `restrict` — turns off everything by default: no agent forwarding, no X11, no port forwarding, no PTY, no user rc files. Safer-by-default baseline.
- `port-forwarding` — re-enables TCP forwarding, which `restrict` just disabled. Needed because `permitopen` only *constrains* forwarding; it doesn't enable it. Without this, sshd silently drops forward requests and you'll see TCP resets on the client with nothing interesting in the sshd log.
- `permitopen="127.0.0.1:10086"` — restricts TCP forwarding to this one destination. Attempts to forward anything else get refused by sshd.
- `command="/bin/sh -c 'trap : TERM; sleep infinity & wait'"` — forces every session to run this command instead of a shell. `sleep infinity` keeps the connection alive so the tunnel works; `trap : TERM` + `& wait` makes the process exit cleanly when the SSH session ends. The user literally cannot execute anything else.
- The rest of the line is the standard public key (type + key material + comment).

Upload the **private** key `~/wg-bootstrap-key` to Bitwarden (Part C) and then shred it locally:

```bash
shred -u ~/wg-bootstrap-key
```

**What this does:** overwrites the file with random data and then unlinks it, making casual recovery very hard.
- `-u` — truncate and remove the file after overwriting. (Without `-u`, `shred` only overwrites; the file still exists.)

(Note: on modern journaling/SSD filesystems `shred` is best-effort — the real guarantee is that the key only ever existed in Bitwarden and a single local file you're deleting now.)

### A6. Test end-to-end from your current machine

Before moving on, verify the tunnel + API work:

```bash
chmod 600 ~/wg-bootstrap-key
```

(Temporarily restore the private key from Bitwarden first. `600` is required or `ssh` will refuse to use it.)

```bash
ssh -i ~/wg-bootstrap-key -f -N \
    -L 10086:127.0.0.1:10086 \
    -o ExitOnForwardFailure=yes \
    wg-bootstrap@<LXC-or-public-host>
```

**What this does:** opens an SSH tunnel in the background that maps your local port `10086` to the WGD API on the remote LXC's loopback.
- `-i ~/wg-bootstrap-key` — use this specific private key (don't pick from ssh-agent or default identities).
- `-f` — fork into background after authentication succeeds. The ssh process keeps running, holding the tunnel open.
- `-N` — don't execute a remote command. (The `command=` in authorized_keys still runs on the server — that's what keeps the session alive. `-N` just tells the client side not to also ask for one.)
- `-L 10086:127.0.0.1:10086` — local forwarding. Traffic to `localhost:10086` on *your* machine gets tunneled through SSH and delivered to `127.0.0.1:10086` on the *remote* machine (i.e. the LXC's loopback, which is where WGD listens).
- `-o ExitOnForwardFailure=yes` — if the tunnel can't be established (port already in use, permission denied), the ssh command exits with an error instead of silently connecting without the forward.
- `wg-bootstrap@<host>` — user and host to connect to.

```bash
curl -s http://127.0.0.1:10086/api/getWireguardConfigurations \
    -H "wg-dashboard-apikey: YOUR_API_KEY" | jq .
```

**What this does:** same API call as in A2, but now going through the SSH tunnel. Your local `127.0.0.1:10086` is actually the LXC's `127.0.0.1:10086`. If this returns valid JSON, the whole chain works.

```bash
pkill -f "ssh.*wg-bootstrap"
```

**What this does:** kills the backgrounded SSH tunnel.
- `pkill` — find processes by name/command and send them a signal (default `SIGTERM`).
- `-f` — match against the full command line, not just the process name. Needed because we want to match the `ssh ... wg-bootstrap@...` command, not a process literally named `wg-bootstrap`.

---

## Part B — Make the LXC's SSH reachable

Same DNS pattern you use for Jellyfin, but Cloudflare proxy must be **off** (orange cloud disabled) — the free CF proxy doesn't cover SSH.

1. DNS: `wg-ssh.yourdomain.com` → your public IP (DNS-only, grey cloud).
2. Router/firewall: forward TCP `22` (or a non-standard port like `2222`) to the WGD LXC's internal IP.
3. Harden SSH on the LXC (`/etc/ssh/sshd_config`):
   ```
   PasswordAuthentication no
   PermitRootLogin no
   AllowTcpForwarding yes
   AllowAgentForwarding no
   X11Forwarding no
   ```
   - `PasswordAuthentication no` — keys only, no brute-forceable passwords.
   - `PermitRootLogin no` — root cannot SSH in directly.
   - `AllowTcpForwarding yes` — required for `-L` to work. The `permitopen` restriction still limits *where* it can forward.
   - `AllowAgentForwarding no` / `X11Forwarding no` — disable features we don't need.
4. Install `fail2ban` on the LXC to auto-ban IPs that fail SSH auth repeatedly.

Alternative: Tailscale on the LXC + every client. Then `wgSshHost` is a Tailscale hostname and nothing is on WAN. Adds its own bootstrap step though.

---

## Part C — Put secrets in Bitwarden

Create one Bitwarden secure note titled `wg-bootstrap` with:

- **Attachment:** the `wg-bootstrap-key` private SSH key.
- **Custom field `ssh_host`:** e.g. `wg-ssh.yourdomain.com`
- **Custom field `ssh_port`:** e.g. `22`
- **Custom field `ssh_user`:** `wg-bootstrap`
- **Custom field `api_key`:** the WGD API key from A2 (mark as hidden/password field)
- **Custom field `wg_interface`:** e.g. `wg0`
- **Custom field `endpoint`:** public `host:port` clients should dial (e.g. `vpn.yourdomain.com:51820`)

Grab the item ID for the chezmoi prompt:

```bash
bw list items --search wg-bootstrap | jq -r '.[0].id'
```

**What this does:** looks up the Bitwarden item ID, which you'll hand to chezmoi so the bootstrap script can fetch this exact item non-interactively.
- `bw list items --search wg-bootstrap` — returns a JSON array of matching items.
- `| jq -r '.[0].id'` — takes the first match and prints its `id` field as raw text (no surrounding quotes).

---

## Part D — The chezmoi client-side flow (what gets coded next)

Once Parts A–C are verified, the chezmoi script will:

1. Skip if `/etc/wireguard/wg0.conf` already exists or `registerWireguard=false`.
2. `apt install wireguard wireguard-tools jq openssh-client`.
3. Pull the SSH key and API key out of Bitwarden via `bw get attachment` / `bw get item`.
4. Generate a local keypair:
   ```bash
   wg genkey | tee privkey | wg pubkey > pubkey
   ```
   **What this does:** generates a WireGuard keypair in one pipeline.
   - `wg genkey` — writes a new private key to stdout.
   - `| tee privkey` — saves the private key to `privkey` AND passes it through to the next command.
   - `| wg pubkey` — reads a private key from stdin and writes the corresponding public key to stdout.
   - `> pubkey` — saves that public key to `pubkey`.
5. Open SSH tunnel (same flags as A6):
   ```bash
   ssh -i /tmp/wg-bootstrap-key -f -N \
       -L 10086:127.0.0.1:10086 \
       -o ExitOnForwardFailure=yes \
       -o StrictHostKeyChecking=accept-new \
       wg-bootstrap@$SSH_HOST
   ```
   The extra flag vs A6:
   - `-o StrictHostKeyChecking=accept-new` — on first connect, automatically trust and record the server's host key; on later connects, fail if it's changed. Needed for unattended automation (the default would prompt "Are you sure you want to continue?").
6. Call WGD API to add the peer:
   ```bash
   curl -s -X POST http://127.0.0.1:10086/api/addPeers/wg0 \
       -H "wg-dashboard-apikey: $API_KEY" \
       -H "Content-Type: application/json" \
       -d '{
         "public_key": "'$(cat pubkey)'",
         "name": "'$(hostname)'",
         "allowed_ips": ["10.0.0.X/32"]
       }'
   ```
   - `-X POST` — HTTP method.
   - `-H "Content-Type: application/json"` — tell WGD the body is JSON.
   - `-d '...'` — request body.
   - The exact payload shape will come from the WGD API docs — <https://docs.wgdashboard.dev/api/>.
7. Fetch the rendered client config via the appropriate WGD endpoint (e.g. `/api/downloadPeer/wg0?id=...`).
8. Substitute the local private key into the config and write to `/etc/wireguard/wg0.conf`.
9. Enable and start the interface:
   ```bash
   systemctl enable --now wg-quick@wg0
   ```
   **What this does:** brings the tunnel up immediately AND registers it to start on every boot.
   - `enable` — create the systemd symlinks so it starts at boot.
   - `--now` — also start it right now (equivalent to running `enable` then `start`).
   - `wg-quick@wg0` — template unit from the `wireguard-tools` package. The part after `@` is the interface name, which maps to `/etc/wireguard/wg0.conf`.
10. Kill the tunnel (`pkill -f "ssh.*wg-bootstrap"`) and shred the temp SSH key and API key from `/tmp`.

### Inputs needed before coding

1. WG interface name (`wg0`?)
2. Public endpoint clients should dial (e.g. `vpn.yourdomain.com:51820`)
3. Bitwarden item name/ID for `wg-bootstrap`
4. SSH host + port
5. Confirmation the API call from A6 works
6. A sample response from a manual `POST /api/addPeers/wg0` so the JSON parse logic matches the actual WGD version you run (the API shape has shifted between WGD 3.x and 4.x)

Provide those and the chezmoi integration will add:
- Prompts in `.chezmoi.toml.tmpl`
- `.chezmoiscripts/run_once_after_30-register-wireguard.sh.tmpl`
- Ansible task to install `wireguard` / `wireguard-tools`
