# dotfiles

Personal dotfiles managed with [chezmoi](https://www.chezmoi.io/) and [Ansible](https://www.ansible.com/).

## Bootstrap a fresh machine

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply mtbossa
```

You will be prompted for:
1. Your full name, email, and GitHub username (stored in chezmoi config, never committed)
2. Optional installs: Slack, Discord, JetBrains Toolbox
3. Whether to register this machine as a **WireGuard peer** (and if yes, the Bitwarden item name that holds the bootstrap secrets — see [WireGuard auto-registration](#wireguard-auto-registration))
4. Your **Bitwarden master password** (when the SSH setup script runs)
5. Your **sudo password** (when Ansible installs system packages)

---

## What happens, in order

### Phase 1 — Tool installation (`run_onchange_before_0*`)

Each tool is installed in its own script so they run independently and only re-run when their content changes.

| Script | Installs |
|--------|----------|
| `00-install-snapd` | snapd (required by bw) |
| `01-install-bw` | Bitwarden CLI via snap |
| `02-install-gh` | GitHub CLI via official apt/rpm repo |
| `03-install-ansible` | Ansible via apt/dnf |

### Phase 2 — SSH + GitHub (`run_onchange_before_10-setup-ssh-github`)

Re-runs if your email, GitHub username, or hostname changes.

1. Generates `~/.ssh/id_ed25519` (ed25519, skips if already exists)
2. Unlocks Bitwarden and retrieves the GitHub PAT (see [Bitwarden setup](#bitwarden-setup) below)
3. Registers the public key with GitHub for **authentication** (`/user/keys`)
4. Registers the public key with GitHub for **commit signing** (`/user/ssh_signing_keys`)
5. Idempotent — if a key with the same hostname title already exists and matches, it's skipped; if it differs (key was regenerated), the old one is replaced
6. Creates `~/.ssh/allowed_signers` for local signature verification
7. Adds a `Host github.com` block to `~/.ssh/config`
8. Switches the dotfiles remote from HTTPS to SSH

### Phase 3 — File deployment (chezmoi apply)

chezmoi deploys all managed dotfiles to `$HOME`:

| Source | Target |
|--------|--------|
| `dot_gitconfig.tmpl` | `~/.gitconfig` |
| `dot_zshrc` | `~/.zshrc` |
| `dot_bashrc` | `~/.bashrc` |
| `dot_tmux.conf` | `~/.tmux.conf` |
| `dot_bootstrap/` | `~/.bootstrap/` |
| `private_dot_config/` | `~/.config/` |
| `oh-my-zsh-customization/` | `~/oh-my-zsh-customization/` |

### Phase 4 — System packages (`run_once_after_20-run-ansible`)

Runs the Ansible playbook once. Installs:

- **Shell**: zsh, Oh My Zsh, Starship, zsh-autosuggestions, zsh-syntax-highlighting, atuin
- **Terminal**: tmux + TPM + catppuccin theme, alacritty, Nerd Fonts (JetBrainsMono, FiraCode)
- **Dev tools**: git, curl, vim, gcc, htop, mise, Docker
- **Apps**: Brave Browser, Postman (snap)
- **Optional** (prompted at init time): Slack, Discord, JetBrains Toolbox
- **Conditional** (if `registerWireguard=true`): wireguard, wireguard-tools, jq, openssh-client

### Phase 5 — WireGuard registration (`run_once_after_30-register-wireguard`)

Only runs if you answered "yes" to registering this machine as a WireGuard peer at init time. Skips silently otherwise.

See [WireGuard auto-registration](#wireguard-auto-registration) below for the full picture.

---

## Git commit signing

Git is configured to sign commits with SSH instead of GPG.

```
gpg.format = ssh
user.signingkey = ~/.ssh/id_ed25519.pub
commit.gpgsign = true
tag.gpgsign = true
gpg.ssh.allowedSignersFile = ~/.ssh/allowed_signers
```

No GPG involved. Signatures are verified against `~/.ssh/allowed_signers`.

---

## SSH key design

- One key per machine (ed25519), named after the hostname
- Generated locally, **never** stored in this repo or Bitwarden
- Serves dual purpose: GitHub authentication + commit signing

---

## Bitwarden setup

Before bootstrapping a new machine, ensure your Bitwarden vault has:

| Item name | Field | Value |
|-----------|-------|-------|
| `github-pat` | password | A GitHub fine-grained PAT |
| `atuin-account` | username | Your atuin account username |
| `atuin-account` | password | Your atuin account password |
| `atuin-key` | password | Your atuin encryption key (shown on `atuin key`) |
| `atuin-server` | uri | Your atuin sync server URL (e.g. `http://10.x.x.x:8888`) |
| `wg-bootstrap` | (see below) | Only needed if you'll register this machine with WireGuard |

Required PAT permissions (fine-grained token, resource owner = your account):

| Permission | Access |
|------------|--------|
| Git SSH keys | Read and write |
| SSH signing keys | Read and write |

The token is retrieved at runtime via `bw get password github-pat`, exported as `GH_TOKEN`, and never written to disk.

---

## WireGuard auto-registration

Optional flow where a fresh OS registers itself as a peer on your WG Dashboard (WGD) instance during bootstrap. WGD stays bound to `127.0.0.1` on its LXC — it is **not** exposed to the public internet. The new machine reaches the WGD API through a tightly-scoped SSH tunnel.

### How it works

```
new machine                    home router               WGD LXC
───────────                    ───────────               ───────
chezmoi apply                                            (WGD listens on
  │                                                       127.0.0.1:10086)
  ▼                                                         ▲
generate WG keypair                                         │
  │                                                         │
  ▼                                                         │
open SSH tunnel  ──► wg-ssh.domain:2225 ──► NAT ──► LXC:22 ─┘
  │                                                         │
  │    -L 10086:127.0.0.1:10086  (only forward allowed)     │
  │                                                         │
  ▼                                                         │
POST /api/addPeers/<iface>  (through tunnel) ────────────── ┘
  │
  ▼
GET /api/downloadPeer/<iface>?id=<pubkey>
  │
  ▼
/etc/wireguard/wg0.conf + systemctl enable --now wg-quick@wg0
```

Two secrets are required and they are **independent**:
- An SSH key that can open the tunnel (and literally nothing else — restricted via `authorized_keys` `restrict,port-forwarding,permitopen=...,command=sleep-infinity`).
- A WGD API key that authenticates the `addPeers` call.

Neither alone grants peer-creation ability. The SSH key only opens a pipe to WGD's localhost API; the API key is useless without a way to reach the API. Both live in Bitwarden.

### One-time infrastructure setup

See [`WG_BOOTSTRAP_SETUP.md`](WG_BOOTSTRAP_SETUP.md) for the full, command-by-command guide. In short:

1. In the WGD LXC: bind WGD to `127.0.0.1`, generate an API key, create a `wg-bootstrap` Unix user, restrict its `authorized_keys` to port-forwarding only.
2. At your router (pfSense or similar): NAT a public port (e.g. `2225`) → LXC `:22`.
3. In Cloudflare DNS: `A` record `wg-ssh.yourdomain.com` → your public IP, **DNS-only (grey cloud)**. Cloudflare's free proxy doesn't handle SSH.
4. In Bitwarden: create the `wg-bootstrap` item (below).

### Bitwarden `wg-bootstrap` item

One secure note that bundles everything the bootstrap script needs.

| Field | Type | Value |
|-------|------|-------|
| *attachment* | file | The bootstrap SSH private key |
| `ssh_host` | text | Public hostname reaching the LXC (e.g. `wg-ssh.yourdomain.com`) |
| `ssh_port` | text | The NATed external port (e.g. `2225`) |
| `ssh_user` | text | `wg-bootstrap` |
| `api_key` | hidden | WGD API key generated in the dashboard UI |
| `wg_interface` | text | WG interface name (e.g. `wg0`) |
| `endpoint` | text | Public `host:port` clients should dial for WG itself (e.g. `vpn.yourdomain.com:51820`) |

The chezmoi prompt accepts any item name (default `wg-bootstrap`) — only the item's name needs to match what you enter; the custom fields are fixed.

### What the chezmoi script does (`run_once_after_30-register-wireguard`)

1. Skips silently unless `registerWireguard=true` at init time.
2. Skips if `/etc/wireguard/<iface>.conf` already exists (so re-runs are safe).
3. Unlocks Bitwarden; pulls all config + secrets out of the `wg-bootstrap` item.
4. Fetches the SSH private key attachment into a `mktemp` directory (600 perms).
5. Generates a fresh WireGuard keypair locally — the private key **never leaves this machine**.
6. Opens a backgrounded SSH tunnel: `ssh -f -N -L 10086:127.0.0.1:10086 -p $ssh_port $ssh_user@$ssh_host`.
7. `POST /api/addPeers/<iface>` with the new peer's public key + this machine's hostname.
8. `GET /api/downloadPeer/<iface>?id=<pubkey>` to fetch the rendered client config.
9. Injects the local private key into the returned config, writes it to `/etc/wireguard/<iface>.conf` (root-owned, 600).
10. `systemctl enable --now wg-quick@<iface>`.
11. `trap cleanup EXIT`: kills the tunnel, `shred`s all temp files, `bw lock`.

If the WGD API response shape doesn't match your WGD version, the script dumps the raw JSON to stderr so you can adjust the `PAYLOAD` in `run_once_after_30-register-wireguard.sh.tmpl` — the targeted version is WGD 4.x.

### What's exposed publicly

Only SSH on the chosen NAT port. Hardening on the LXC's `sshd_config`:

```
PasswordAuthentication no
PermitRootLogin no
```

Plus `fail2ban` for brute-force mitigation. WGD itself is never reachable from the internet.

---

## Repo structure

```
dotfiles/
├── .chezmoi.toml.tmpl              # init prompts (name, email, github username)
├── .chezmoiscripts/
│   ├── run_onchange_before_00-install-snapd.sh.tmpl
│   ├── run_onchange_before_01-install-bw.sh.tmpl
│   ├── run_onchange_before_02-install-gh.sh.tmpl
│   ├── run_onchange_before_03-install-ansible.sh.tmpl
│   ├── run_onchange_before_10-setup-ssh-github.sh.tmpl
│   ├── run_once_after_20-run-ansible.sh.tmpl
│   ├── run_once_after_21-setup-atuin.sh.tmpl
│   └── run_once_after_30-register-wireguard.sh.tmpl
├── WG_BOOTSTRAP_SETUP.md           # one-time infra guide for the WGD LXC side
├── dot_gitconfig.tmpl              # ~/.gitconfig (SSH signing configured)
├── dot_zshrc                       # ~/.zshrc
├── dot_bashrc                      # ~/.bashrc
├── dot_tmux.conf                   # ~/.tmux.conf
├── dot_bootstrap/                  # ~/.bootstrap/ (Ansible playbook)
│   ├── setup.yml
│   └── requirements.yml
├── oh-my-zsh-customization/        # ~/oh-my-zsh-customization/
└── private_dot_config/             # ~/.config/
```

Files without a chezmoi prefix (`README.md`, `.gitignore`, `.vscode/`) are repo-level only and are never deployed to `$HOME`.

---

## Re-running scripts manually

```bash
# Force re-run a specific script
chezmoi state delete-bucket --bucket=scriptState
chezmoi apply

# Dry-run to see what would change
chezmoi apply --dry-run --verbose

# Re-apply everything
chezmoi apply
```
