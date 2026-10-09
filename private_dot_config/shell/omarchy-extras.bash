# shellcheck shell=bash
# Sourced from ~/.bashrc on Omarchy (see run_onchange_after_30-omarchy-shell).
# Omarchy already sets up starship, zoxide, fzf, mise and the eza aliases.
[[ -f ~/.config/shell/aliases.sh ]] && source ~/.config/shell/aliases.sh

# atuin (loaded last so it wins the ctrl-r binding over fzf)
[[ -f ~/.bash-preexec.sh ]] && source ~/.bash-preexec.sh
command -v atuin >/dev/null && eval "$(atuin init bash)"
