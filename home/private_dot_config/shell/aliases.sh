# shellcheck shell=bash
# Personal aliases shared by bash (via extras.bash) and zsh (via ~/.config/oh-my-zsh/aliases.zsh).
alias cl="clear"
alias lzg="lazygit"

alias sail="[ -f sail ] && bash sail || bash vendor/bin/sail"
alias s="sail"
alias sud="sail up -d"
alias sailrestart="sail down && sud"
alias sa="s artisan"
alias pf="clear && sail test --filter"
alias satp="sail artisan test --parallel"

alias dcud="docker compose up -d"

alias claude-personal="CLAUDE_CONFIG_DIR=~/.claude-personal claude"
alias claude-bsc="CLAUDE_CONFIG_DIR=~/.claude-bsc claude"
alias claude-packiyo="CLAUDE_CONFIG_DIR=~/.claude-packiyo claude"
