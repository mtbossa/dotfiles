#!/bin/bash
# reset-bootstrap.sh
# Resets chezmoi state and undoes bootstrap actions so you can re-run from scratch.
# Does NOT uninstall system packages (bw, gh, ansible) — they're idempotent on re-run.

set -euo pipefail

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

confirm() {
    read -r -p "$1 [y/N] " response
    [[ "${response}" =~ ^[Yy]$ ]]
}

echo ""
echo -e "${YELLOW}Bootstrap reset${NC}"
echo "This will undo the bootstrap so you can re-run chezmoi apply from scratch."
echo ""

# --- 1. chezmoi script state ---
# This is the most important step — forces all run_once_ and run_onchange_ scripts to re-run.
echo -e "${GREEN}[1/5] Clearing chezmoi script state...${NC}"
chezmoi state delete-bucket --bucket=scriptState
echo "Done."

# --- 2. SSH key ---
echo ""
echo -e "${GREEN}[2/5] SSH key${NC}"
if [ -f "${HOME}/.ssh/id_ed25519" ]; then
    if confirm "Delete ~/.ssh/id_ed25519 and ~/.ssh/id_ed25519.pub? (a new key will be generated on re-run)"; then
        rm -f "${HOME}/.ssh/id_ed25519" "${HOME}/.ssh/id_ed25519.pub"
        rm -f "${HOME}/.ssh/allowed_signers"
        echo "SSH key removed."
        echo -e "${YELLOW}Note: the old key is still registered on GitHub — the setup script will replace it on re-run.${NC}"
    fi
else
    echo "No SSH key found, skipping."
fi

# --- 3. SSH config (GitHub block) ---
echo ""
echo -e "${GREEN}[3/5] SSH config${NC}"
if grep -q "Host github.com" "${HOME}/.ssh/config" 2>/dev/null; then
    if confirm "Remove 'Host github.com' block from ~/.ssh/config?"; then
        # Remove the block: from the blank line before "Host github.com" through "IdentitiesOnly yes"
        sed -i '/^$/{ N; /\nHost github\.com/{N;N;N;N;d} }' "${HOME}/.ssh/config"
        echo "GitHub SSH config block removed."
    fi
else
    echo "No GitHub block in ~/.ssh/config, skipping."
fi

# --- 4. Atuin ---
echo ""
echo -e "${GREEN}[4/5] Atuin${NC}"
if command -v atuin &>/dev/null && atuin account info &>/dev/null 2>&1; then
    if confirm "Log out of atuin and remove its config?"; then
        atuin logout 2>/dev/null || true
        rm -f "${HOME}/.config/atuin/config.toml"
        echo "Atuin logged out and config removed."
    fi
else
    echo "Atuin not logged in, skipping."
fi

# --- 5. Deployed dotfiles (optional, aggressive) ---
echo ""
echo -e "${GREEN}[5/5] Deployed dotfiles${NC}"
echo -e "${RED}WARNING: This removes all chezmoi-managed files from your home directory (.gitconfig, .zshrc, .bashrc, etc.)${NC}"
if confirm "Remove all chezmoi-managed dotfiles from \$HOME? (skip this if you just want scripts to re-run)"; then
    chezmoi destroy --force
    echo "All managed dotfiles removed."
else
    echo "Skipped — only script state was cleared."
fi

echo ""
echo -e "${GREEN}Reset complete.${NC}"
echo "Run 'chezmoi apply' to bootstrap again."
