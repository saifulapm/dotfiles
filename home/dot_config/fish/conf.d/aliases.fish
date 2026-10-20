alias c clear
alias reload "exec fish"
alias ll "lsd -l"
alias lt "lsd --tree"
alias ta "tmux attach"
# cd goes to real paths directly and jumps through zoxide for the rest.
alias cd zd

alias .. "cd .."
alias ... "cd ../.."
alias .... "cd ../../.."

alias s "npx skills"
alias cx "claude --allow-dangerously-skip-permissions"
alias pa "pi --approve"

alias p pnpm
alias pdev "pnpm run dev"
# The dev tunnel, whose config comes from home/private_dot_cloudflared.
alias dev "cloudflared tunnel --config ~/.cloudflared/config.dev.yaml run dev"

alias a "php artisan"
alias tinker "php artisan tinker"
alias seed "php artisan db:seed"
alias serve "php artisan serve"

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
alias push "git push"
alias resolve "git add . && git commit --no-edit"
alias stash "git stash -u"
alias unstage "git restore --staged ."
alias wip "commit wip"
