# Aliases (managed by chezmoi) — port of the mac alias.zsh, minus mac-only
# tools (opencode, hacker-news-tui) until they exist here. fish aliases are
# functions, so they win over PATH commands the same way zsh aliases did.

alias c "clear"
alias k kak_session # per-directory kakoune daemon+client (bin/kak_session)
alias et "emacsclient -t" # terminal Emacs via the running daemon
alias reload "exec fish"
alias cd zd
alias ll "lsd -l"
alias lt "lsd --tree"
alias ta "tmux attach"

# Directories
alias .. "cd .."
alias ... "cd ../.."
alias .... "cd ../../.."

# Agents
alias cx 'printf "\033[2J\033[3J\033[H" && claude --allow-dangerously-skip-permissions'
alias s "npx skills"

# Laravel
alias a "php artisan"
alias tinker "php artisan tinker"
alias seed "php artisan db:seed"
alias serve "php artisan serve"

# Git
alias g git
alias gst "git status"
alias gb "git branch"
alias gc "git commit"
alias gl "git log --oneline --decorate --color"
alias amend "git add . && git commit --amend --no-edit"
alias commit "git add . && git commit -m"
alias diff "git diff"
alias force "git push --force"
alias nuke "git clean -df && git reset --hard"
alias pop "git stash pop"
alias pull "git pull"
alias push "git push -u origin main"
alias resolve "git add . && git commit --no-edit"
alias stash "git stash -u"
alias unstage "git restore --staged ."
alias wip "commit wip"

# Others
alias dev "cloudflared tunnel --config ~/.cloudflared/config.dev.yaml run dev"
alias p pnpm
alias pdev "pnpm run dev"
