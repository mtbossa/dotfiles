# dotfiles

Personal dotfiles managed with [chezmoi](https://www.chezmoi.io/), for Omarchy, Arch and Debian/Ubuntu
(Fedora is partially supported). Debian-family system packages are installed with [Ansible](https://www.ansible.com/).

## Bootstrap a fresh machine

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply mtbossa
```

You will be prompted for:

1. Your full name, email and GitHub username (stored in the local chezmoi config, never committed)
2. Optional installs: Slack, JetBrains Toolbox, Tailscale, and (except on Arch, where Omarchy ships them) Discord and Claude Code CLI
3. Your **Bitwarden master password**, once (see [Bitwarden setup](#bitwarden-setup))
4. Your **sudo password** for package installs

---

## Repository layout

`.chezmoiroot` points chezmoi at `home/`, so everything outside it is repo-only and never deployed.

```
dotfiles/
├── .chezmoiroot                 # "home": the chezmoi source state lives in home/
├── .chezmoiversion              # minimum chezmoi version
├── README.md
├── reset-bootstrap.sh           # undo the bootstrap so it can be re-run from scratch
├── ansible/                     # Debian-family playbook, run in place by run_onchange_after_20-run-ansible
│   ├── setup.yml
│   └── requirements.yml
└── home/                        # mirrors $HOME (dot_ → ".", private_ → 0700)
    ├── .chezmoi.toml.tmpl       # `chezmoi init` prompts → ~/.config/chezmoi/chezmoi.toml
    ├── .chezmoidata/            # data for templates: package lists, external versions
    ├── .chezmoiexternal.toml.tmpl  # downloaded dependencies (oh-my-zsh, plugins, TPM, fonts)
    ├── .chezmoiignore           # targets skipped on some machines
    ├── .chezmoiremove           # leftovers of older layouts, deleted on apply
    ├── .chezmoiscripts/         # install/setup scripts (see below)
    ├── .chezmoitemplates/       # shared template snippets: osFamily, isOmarchy, bitwarden, atuin-config.toml
    ├── dot_gitconfig.tmpl       # ~/.gitconfig
    ├── dot_zshrc                # ~/.zshrc
    ├── modify_dot_bashrc        # appends one block to the distro's ~/.bashrc
    └── private_dot_config/      # ~/.config
        ├── alacritty/           # alacritty.toml.tmpl + iTerm palette
        ├── atuin/               # modify_ script: our config, the machine's sync_address
        ├── oh-my-zsh/           # ZSH_CUSTOM: aliases and functions (*.zsh)
        ├── shell/               # aliases.sh (bash + zsh), extras.bash (sourced from ~/.bashrc)
        ├── starship.toml
        └── tmux/tmux.conf.tmpl
```

## How machines differ

Two helpers in `home/.chezmoitemplates/` are the only places that detect the machine; everything else asks them:

| Helper | Values | Used for |
|--------|--------|----------|
| `osFamily` | `arch` (Arch, Omarchy, `ID_LIKE=arch`), `debian` (Debian, Ubuntu, Pop!_OS), `fedora`, `other-linux`, or the OS name | Which installer runs: pacman/yay vs. apt/dnf + Ansible |
| `isOmarchy` | `true` when `/usr/share/omarchy` exists | Whether Omarchy owns the look (see [Omarchy](#omarchy)) |

Use them in templates with `{{ if eq (includeTemplate "osFamily" .) "arch" }}`.

Small differences are `{{ if }}` blocks inside a file (`alacritty.toml.tmpl`, `tmux.conf.tmpl`); whole files that don't apply
are listed in `.chezmoiignore`; scripts that don't apply render empty, which chezmoi skips.

---

## What `chezmoi apply` does

Scripts run in this order: `before_` scripts, then files, externals and `after_` scripts, each group sorted by name.
`run_onchange_` scripts re-run when their rendered content changes (package lists and hashed files are rendered into them);
`run_once_` scripts run once per content. All of them are idempotent.

| Script | Runs on | Does |
|--------|---------|------|
| `before_00-install-snapd` | Debian, Fedora | snapd (needed for bw) |
| `before_01-install-bw` | Debian, Fedora | Bitwarden CLI (snap) |
| `before_02-install-gh` | Debian, Fedora | GitHub CLI (official apt/rpm repo) |
| `before_03-install-ansible` | Debian, Fedora | Ansible |
| `before_04-install-jq` | Debian, Fedora | jq |
| `before_05-install-packages-arch` | Arch | `.chezmoidata/packages.yaml` via pacman and yay; starts tailscaled if chosen |
| `before_06-setup-shell-terminal-arch` | Arch | zsh as login shell; Alacritty as Omarchy's default terminal |
| `before_10-setup-ssh-github` | Linux | SSH key, registered on GitHub for auth + signing (see [SSH keys](#ssh-keys)) |
| `after_10-refresh-font-cache` | non-Arch | `fc-cache` after the Nerd Fonts externals change |
| `after_20-run-ansible` | Debian, Fedora | `ansible/setup.yml`; re-runs when the playbook or your answers change |
| `after_21-setup-atuin` (once) | Linux | atuin sync server, login and first sync, from Bitwarden |
| `after_25-install-tmux-plugins` | all | TPM plugins declared in `tmux.conf`; re-runs when it changes |
| `after_99-bw-lock` (every apply) | Linux | locks Bitwarden again if a script unlocked it |

The Ansible playbook installs zsh, tmux, Alacritty, starship, atuin, mise, eza, fzf, zoxide, Docker, Brave, VS Code,
Postman and the optional apps. On Arch those come from `packages.yaml` or ship with Omarchy.

### Externals

`.chezmoiexternal.toml.tmpl` downloads Oh My Zsh, zsh-autosuggestions, zsh-syntax-highlighting, TPM and (where used)
catppuccin/tmux, the eza zsh completion and the JetBrainsMono/FiraCode Nerd Fonts. Branch tarballs refresh weekly;
pinned versions live in `.chezmoidata/externals.yaml`. Oh My Zsh's own updater is disabled so it doesn't drift.
TPM is a `git-repo` external because TPM only treats a plugin directory with a git remote as installed.
On Arch the eza completion and Nerd Fonts come from packages instead.

---

## Omarchy

On Omarchy, Omarchy owns colors and styles and follows the selected theme; this repo only layers keybindings,
plugins and behavior on top of the configs Omarchy ships in `/usr/share/omarchy/config/`. Plain Arch and every
other OS get the full styled configs.

| Config | On Omarchy | Elsewhere |
|--------|------------|-----------|
| tmux | sources Omarchy's `tmux.conf`, then adds the `C-Space` prefix, bindings and TPM plugins | same, plus catppuccin and the status line |
| Alacritty | imports Omarchy's `alacritty.toml` and adds bindings (Alacritty appends imported arrays, so Omarchy's stay) | iTerm palette, font, padding, opacity |
| starship | not managed: Omarchy's prompt | `starship.toml` |
| git | Omarchy's `~/.config/git/config` loads first; `~/.gitconfig` adds identity and signing on top | `~/.gitconfig` |
| bash | `~/.bashrc` stays Omarchy's; `modify_dot_bashrc` appends a block sourcing `~/.config/shell/extras.bash` | same with the distro's `~/.bashrc` |

zsh is the login shell everywhere, with the same `.zshrc`.

---

## Git commit signing

Commits and tags are signed with the machine's SSH key; no GPG involved.

```
gpg.format = ssh
user.signingkey = ~/.ssh/id_ed25519.pub
commit.gpgsign = true
tag.gpgsign = true
gpg.ssh.allowedSignersFile = ~/.ssh/allowed_signers
```

## SSH keys

- One ed25519 key per machine, titled with the hostname on GitHub
- Generated locally, **never** stored in this repo or Bitwarden
- Registered for both authentication and commit signing; a stale key with the same title is replaced
- The setup script also writes `~/.ssh/allowed_signers`, adds a `Host github.com` block to `~/.ssh/config`
  and switches this repo's remote from HTTPS to SSH

---

## Bitwarden setup

Before bootstrapping a new machine, your Bitwarden vault needs these items (names must match exactly):

| Item name | Field | Value |
|-----------|-------|-------|
| `github-pat` | password | A GitHub fine-grained PAT |
| `atuin-account` | username | Your atuin account username |
| `atuin-account` | password | Your atuin account password |
| `atuin-key` | password | Your atuin encryption key (shown by `atuin key`) |
| `atuin-server` | uri | Your atuin sync server URL (e.g. `http://10.x.x.x:8888`) |

Required PAT permissions (fine-grained token, resource owner = your account):

| Permission | Access |
|------------|--------|
| Git SSH keys | Read and write |
| SSH signing keys | Read and write |

Scripts read items through `bw_get` in `.chezmoitemplates/bitwarden`. The session is cached in a 600-perm file under
`/tmp` so you unlock once per apply, and `run_after_99-bw-lock` removes it. Secrets are never written to disk.

---

## Maintenance

```bash
chezmoi diff                      # what apply would change
chezmoi apply --dry-run --verbose # same, including scripts
chezmoi cd                        # open the source repo
chezmoi execute-template < home/dot_gitconfig.tmpl   # render a template (from the repo root)

# Force scripts to re-run on the next apply
chezmoi state delete-bucket --bucket=entryState    # run_onchange_ scripts
chezmoi state delete-bucket --bucket=scriptState   # run_once_ scripts
```

`./reset-bootstrap.sh` clears both, and optionally the SSH key, atuin login and deployed files, to re-run the bootstrap from scratch.
