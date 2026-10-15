# shellcheck shell=bash
# Sourced from ~/.bashrc (see modify_dot_bashrc). Works on top of Omarchy's defaults,
# which already set up starship, zoxide, fzf, mise and the eza aliases.
[[ -f ~/.config/shell/aliases.sh ]] && source ~/.config/shell/aliases.sh

# atuin (loaded last so it wins the ctrl-r binding over fzf); curl-installed copy lives in ~/.atuin/bin
[[ -d ~/.atuin/bin ]] && PATH="$HOME/.atuin/bin:$PATH"
[[ -f ~/.bash-preexec.sh ]] && source ~/.bash-preexec.sh
command -v atuin >/dev/null && eval "$(atuin init bash)"
