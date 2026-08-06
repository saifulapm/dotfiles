# magit-worktree.kak — worktree transient: add / remove / visit / list.
# `<space>g w` enters the user-mode. The "Other worktrees" status
# section is rendered by magit-status.kak (this module owns the actions).

provide-module magit-worktree %{

declare-user-mode magit-worktree
declare-option -hidden str magit_worktree_scratch ''

define-command magit-worktree-dispatch -docstring 'Magit worktree transient' %{
    enter-user-mode magit-worktree
}

map global magit-worktree a ': magit-worktree-add-prompt<ret>'    -docstring 'add worktree (path → branch)'
map global magit-worktree k ': magit-worktree-remove-prompt<ret>' -docstring 'remove worktree'
map global magit-worktree v ': magit-worktree-visit-prompt<ret>'  -docstring 'visit (cd) worktree'
map global magit-worktree l ': magit-worktree-list<ret>'          -docstring 'list worktrees'

# --- add: path → branch (chained prompts via scratch option) ---
define-command -hidden magit-worktree-add-prompt %{
    prompt 'worktree path: ' magit-worktree-add-step2
}
define-command -hidden magit-worktree-add-step2 %{
    set-option global magit_worktree_scratch %val{text}
    prompt 'branch (existing or new): ' magit-worktree-add-apply
}
define-command -hidden magit-worktree-add-apply %{
    evaluate-commands %sh{
        path=$kak_opt_magit_worktree_scratch
        branch=$kak_text
        if [ -z "$path" ] || [ -z "$branch" ]; then
            echo "fail 'magit-worktree add: path and branch required'"
            exit
        fi
        # Tilde expansion: kak prompts pass `~` literally, so `~/foo` would
        # become a relative directory called `~/foo` rather than `$HOME/foo`.
        # Expand only a leading `~` or `~/` for safety (don't touch ~user).
        case "$path" in
            '~')   path=$HOME ;;
            '~/'*) path="$HOME/${path#~/}" ;;
        esac
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
        [ -z "$toplevel" ] && { echo "fail 'magit-worktree: not in a git worktree'"; exit; }
        err=$(mktemp "${TMPDIR:-/tmp}/magit-worktree-err.XXXXXX")
        # If the branch already exists, `git worktree add <path> <branch>`
        # checks it out. If it doesn't, git refuses unless we pass -b.
        # Detect and pick the right form.
        # CRITICAL: redirect stdout to /dev/null. git worktree writes
        # "HEAD is now at ..." to stdout, which would leak through our
        # %sh{} block's stdout and be re-evaluated by kak as kakscript.
        # Only stderr goes to $err.
        if ( cd "$toplevel" && git rev-parse --verify "refs/heads/$branch" >/dev/null 2>&1 ); then
            ( cd "$toplevel" && git worktree add "$path" "$branch" >/dev/null 2>"$err" )
            rc=$?
        else
            ( cd "$toplevel" && git worktree add -b "$branch" "$path" >/dev/null 2>"$err" )
            rc=$?
        fi
        if [ "$rc" = 0 ]; then
            sp=$(printf '%s' "$path"   | tr -d "'")
            sb=$(printf '%s' "$branch" | tr -d "'")
            printf "echo -markup %%{{Information}worktree added: %s -> %s}\n" "$sb" "$sp"
        else
            # git's "Preparing worktree (...)" and "HEAD is now at ..." lines
            # are informational. Skip them to find the real error. Strip
            # single quotes AND braces + newlines so the fail arg stays on
            # one line and doesn't confuse kak's quoting.
            reason=$(grep -vE '^(Preparing worktree|HEAD is now at)' "$err" \
                     | head -1 | tr -d "'{}" | tr '\n' ' ')
            [ -z "$reason" ] && reason=$(head -1 "$err" | tr -d "'{}" | tr '\n' ' ')
            [ -z "$reason" ] && reason="git worktree add exited $rc"
            printf "fail 'worktree add failed: %s'\n" "$reason"
        fi
        rm -f "$err"
        printf "set-option global magit_worktree_scratch ''\n"
        printf "magit-refresh-after-mutation\n"
    }
}

# --- remove: single prompt ---
define-command -hidden magit-worktree-remove-prompt %{
    prompt 'remove worktree (path): ' magit-worktree-remove-apply
}
define-command -hidden magit-worktree-remove-apply %{
    evaluate-commands %sh{
        path=$kak_text
        if [ -z "$path" ]; then
            echo "fail 'magit-worktree remove: path required'"
            exit
        fi
        case "$path" in
            '~')   path=$HOME ;;
            '~/'*) path="$HOME/${path#~/}" ;;
        esac
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
        [ -z "$toplevel" ] && { echo "fail 'magit-worktree: not in a git worktree'"; exit; }
        err=$(mktemp "${TMPDIR:-/tmp}/magit-worktree-err.XXXXXX")
        if ( cd "$toplevel" && git worktree remove "$path" >/dev/null 2>"$err" ); then
            sp=$(printf '%s' "$path" | tr -d "'")
            printf "echo -markup %%{{Information}worktree removed: %s}\n" "$sp"
        else
            reason=$(head -1 "$err" | tr -d "'")
            [ -z "$reason" ] && reason="git worktree remove failed"
            printf "fail 'worktree remove failed: %s'\n" "$reason"
        fi
        rm -f "$err"
        printf "magit-refresh-after-mutation\n"
    }
}

# --- visit: cd into the worktree so subsequent magit commands act there ---
define-command -hidden magit-worktree-visit-prompt %{
    prompt 'visit worktree (path): ' magit-worktree-visit-apply
}
define-command -hidden magit-worktree-visit-apply %{
    evaluate-commands %sh{
        path=$kak_text
        if [ -z "$path" ]; then
            echo "fail 'magit-worktree visit: path required'"
            exit
        fi
        case "$path" in
            '~')   path=$HOME ;;
            '~/'*) path="$HOME/${path#~/}" ;;
        esac
        if [ ! -d "$path" ]; then
            sp=$(printf '%s' "$path" | tr -d "'")
            printf "fail 'magit-worktree visit: not a directory: %s'\n" "$sp"
            exit
        fi
        sp=$(printf '%s' "$path" | tr -d "'")
        printf "change-directory '%s'\n" "$sp"
        printf "echo -markup %%{{Information}cd %s}\n" "$sp"
    }
}

# --- list: info box of git worktree list output ---
define-command -hidden magit-worktree-list %{
    evaluate-commands %sh{
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
        [ -z "$toplevel" ] && { echo "fail 'magit-worktree: not in a git worktree'"; exit; }
        out=$(cd "$toplevel" && git worktree list 2>/dev/null)
        if [ -z "$out" ]; then
            printf "echo -markup %%{{Information}no worktrees}\n"
            exit
        fi
        body=$(printf '%s' "$out" | tr -d "'")
        printf "info -title worktrees '%s'\n" "$body"
    }
}

}
