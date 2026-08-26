# dotfiles

Personal dotfiles managed with [chezmoi](https://www.chezmoi.io/) and [Ansible](https://www.ansible.com/).

## Bootstrap a fresh machine

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply mtbossa
```

You will be prompted for:
1. Your full name, email, and GitHub username (stored in chezmoi config, never committed)
2. Optional installs: Slack, Discord, JetBrains Toolbox, Claude Code CLI
3. Your **Bitwarden master password** (when the SSH setup script runs)
4. Your **sudo password** (when Ansible installs system packages)

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

Required PAT permissions (fine-grained token, resource owner = your account):

| Permission | Access |
|------------|--------|
| Git SSH keys | Read and write |
| SSH signing keys | Read and write |

The token is retrieved at runtime via `bw get password github-pat`, exported as `GH_TOKEN`, and never written to disk.

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
│   └── run_once_after_21-setup-atuin.sh.tmpl
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
