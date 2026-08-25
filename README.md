# dotfiles

Personal dotfiles managed with [chezmoi](https://www.chezmoi.io/) and [Ansible](https://www.ansible.com/).

## Bootstrap a fresh machine

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply mtbossa
```

You will be prompted for:
1. Your full name, email, and GitHub username (stored in chezmoi config, never committed)
2. Optional installs: Slack, Discord, JetBrains Toolbox, Claude Code CLI
3. Whether to join this machine to your **Tailscale tailnet** (see [Tailscale auto-join](#tailscale-auto-join) below)
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
- **Optional** (prompted at init time): Slack, Discord, JetBrains Toolbox, Claude Code CLI (skips gracefully if the install fails or times out — see task warning)
- **Conditional** (if `joinTailscale=true`): tailscale (via the official install script)

### Phase 5 — Tailscale join (`run_once_after_30-join-tailscale`)

Only runs if you answered "yes" to joining the Tailscale tailnet at init time. Skips silently otherwise.

See [Tailscale auto-join](#tailscale-auto-join) below for the full picture.

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
| `tailscale-oauth-client` | username | Tailscale OAuth client ID (see [Tailscale auto-join](#tailscale-auto-join)) |
| `tailscale-oauth-client` | password | Tailscale OAuth client secret |

Required PAT permissions (fine-grained token, resource owner = your account):

| Permission | Access |
|------------|--------|
| Git SSH keys | Read and write |
| SSH signing keys | Read and write |

The token is retrieved at runtime via `bw get password github-pat`, exported as `GH_TOKEN`, and never written to disk.

---

## Tailscale auto-join

Optional flow where a fresh machine joins your Tailscale tailnet during bootstrap. Tailscale's own coordination servers handle NAT traversal and peer registration, so unlike the old WireGuard setup there is no self-hosted control-plane host and no SSH tunnel to manage.

Auth keys are minted on demand via a Tailscale **OAuth client** rather than stored as a static secret — static auth keys cap out at 90 days, which means manual rotation forever. An OAuth client secret doesn't expire on its own (valid until revoked), so this is the actual set-and-forget fix.

### How it works (`run_once_after_30-join-tailscale`)

1. Skips silently unless `joinTailscale=true` at init time.
2. Checks `tailscale status --json`:
   - Already `Running` with the current hostname → no-op, nothing else happens (so re-runs are cheap and don't even need Bitwarden or network calls).
   - Already `Running` but the hostname changed (machine renamed) → `sudo tailscale set --hostname=<hostname>`, done.
   - Otherwise → unlocks Bitwarden, fetches the OAuth client ID/secret from the `tailscale-oauth-client` item, exchanges them for a short-lived access token (`POST /api/v2/oauth/token`), mints a fresh single-use, pre-authorized auth key tagged `tag:bootstrap` (`POST /api/v2/tailnet/-/keys`), and runs `sudo tailscale up --authkey=file:<tmp> --hostname=<hostname>` (the key is passed via `file:` so it never appears in `ps` or shell history).
3. `trap cleanup EXIT`: shreds the temp file holding the minted key and unsets `BW_SESSION`/`CLIENT_SECRET`/`ACCESS_TOKEN`.

### One-time Tailscale setup

1. **ACL policy** (admin console → Access Controls) — add a `tagOwners` entry so `tag:bootstrap` exists:
   ```json
   "tagOwners": {
     "tag:bootstrap": ["autogroup:admin"],
   },
   ```
2. **OAuth client** (admin console → Settings → OAuth clients → Generate OAuth client):
   - Scopes: **Auth Keys** → **Write**
   - Tags: `tag:bootstrap` (only selectable once step 1 is done)
   - Copy the generated **Client ID** and **Client Secret** (shown once).

### Bitwarden `tailscale-oauth-client` item

A single login item.

| Field | Value |
|-------|-------|
| username | OAuth Client ID |
| password | OAuth Client Secret |

### Operational notes

- Minted keys are single-use, `expirySeconds: 3600`, and consumed immediately — there's nothing to rotate on the key side. If you ever need to revoke access, revoke the OAuth client in the admin console.
- Bootstrapped devices are tagged `tag:bootstrap`, and `preauthorized: true` means they skip manual device approval even if your tailnet has that enabled.
- To verify a machine joined correctly: `tailscale status` and `tailscale ip -4`.

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
│   └── run_once_after_30-join-tailscale.sh.tmpl
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
