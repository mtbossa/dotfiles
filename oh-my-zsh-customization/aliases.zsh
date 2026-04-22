alias ls="eza --icons"
alias ll="eza -lh --icons --git"
alias la="eza -lah --icons --git"
alias lt="eza --tree --icons"

alias cl="clear"
alias lzg="lazygit"

alias sail="[ -f sail ] && bash sail || bash vendor/bin/sail"
alias s="sail"
alias sud="sail up -d"
alias sailrestart="sail down && sud"
alias sa="sail artisan"
alias pf="clear && sail test --filter"
alias satp="sail artisan test --parallel"
alias sa="s artisan"

alias dcud="docker compose up -d"

alias claude-personal="CLAUDE_CONFIG_DIR=~/.claude-personal claude"
alias claude-bsc="CLAUDE_CONFIG_DIR=~/.claude-bsc claude"
alias claude-packiyo="CLAUDE_CONFIG_DIR=~/.claude-packiyo claude"

alias bup="sudo wg-quick up bhouse"
alias bdown="sudo wg-quick down bhouse"
