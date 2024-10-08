alias cl="clear"
alias lzg="lazygit"

alias sail="[ -f sail ] && bash sail || bash vendor/bin/sail"
alias s="sail"
alias sud="sail up -d"
alias sailrestart="sail down && sud"
alias sa="sail artisan"
alias pf="clear && sail test --filter"
alias sdf="clear && sail dusk --filter"
alias satp="sail artisan test --parallel"
alias samfs="sail artisan migrate:fresh --seed" 
alias sailrestart="sail down && sud"
alias sa="s artisan"
alias sc="s composer"

alias dcud="docker compose up -d"

alias packiyo="cd /home/mtbossa/Development/packiyo/packiyo/docker"
alias jogai="cd /home/mtbossa/Development/jogai"
alias packiyo-work="docker compose exec -u laradock workspace zsh"