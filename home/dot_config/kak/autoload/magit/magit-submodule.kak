# magit-submodule.kak — submodule transient: add / init / update / deinit.
# `<space>g o` enters this user-mode (Magit-emacs uses `o` for submodule).
# Status section "Submodules" is rendered by magit-status.kak.

provide-module magit-submodule %{

declare-user-mode magit-submodule
declare-option -hidden str magit_submodule_scratch ''

define-command magit-submodule-dispatch -docstring 'Magit submodule transient' %{
    enter-user-mode magit-submodule
}

map global magit-submodule a ': magit-submodule-add-prompt<ret>'    -docstring 'add submodule (url → path)'
map global magit-submodule i ': magit-submodule-init-run<ret>'      -docstring 'init (registers .gitmodules)'
map global magit-submodule u ': magit-submodule-update-run<ret>'    -docstring 'update --init --recursive'
map global magit-submodule d ': magit-submodule-deinit-prompt<ret>' -docstring 'deinit --force (prompt path)'
map global magit-submodule l ': magit-submodule-list<ret>'          -docstring 'list submodules'

# --- add: chained url → path ---
define-command -hidden magit-submodule-add-prompt %{
    prompt 'submodule url: ' magit-submodule-add-step2
}
define-command -hidden magit-submodule-add-step2 %{
    set-option global magit_submodule_scratch %val{text}
    prompt 'path (relative to repo root): ' magit-submodule-add-apply
}
define-command -hidden magit-submodule-add-apply %{
    evaluate-commands %sh{
        url=$kak_opt_magit_submodule_scratch
        path=$kak_text
        if [ -z "$url" ] || [ -z "$path" ]; then
            echo "fail 'magit-submodule add: url and path required'"
            exit
        fi
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
        [ -z "$toplevel" ] && { echo "fail 'magit-submodule: not in a git worktree'"; exit; }
        err=$(mktemp "${TMPDIR:-/tmp}/magit-submodule-err.XXXXXX")
        if ( cd "$toplevel" && git submodule add "$url" "$path" >/dev/null 2>"$err" ); then
            su=$(printf '%s' "$url" | tr -d "'")
            sp=$(printf '%s' "$path" | tr -d "'")
            printf "echo -markup %%{{Information}submodule added: %s -> %s}\n" "$sp" "$su"
        else
            reason=$(head -1 "$err" | tr -d "'")
            [ -z "$reason" ] && reason="git submodule add failed"
            printf "fail 'submodule add failed: %s'\n" "$reason"
        fi
        rm -f "$err"
        printf "set-option global magit_submodule_scratch ''\n"
        printf "magit-refresh-after-mutation\n"
    }
}

# --- init: no prompt; registers config from .gitmodules ---
define-command -hidden magit-submodule-init-run %{
    evaluate-commands %sh{
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
        [ -z "$toplevel" ] && { echo "fail 'magit-submodule: not in a git worktree'"; exit; }
        err=$(mktemp "${TMPDIR:-/tmp}/magit-submodule-err.XXXXXX")
        if ( cd "$toplevel" && git submodule init >/dev/null 2>"$err" ); then
            printf "echo -markup %%{{Information}submodule init}\n"
        else
            reason=$(head -1 "$err" | tr -d "'")
            [ -z "$reason" ] && reason="git submodule init failed"
            printf "fail 'submodule init failed: %s'\n" "$reason"
        fi
        rm -f "$err"
        printf "magit-refresh-after-mutation\n"
    }
}

# --- update: --init --recursive (sensible default) ---
define-command -hidden magit-submodule-update-run %{
    evaluate-commands %sh{
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
        [ -z "$toplevel" ] && { echo "fail 'magit-submodule: not in a git worktree'"; exit; }
        err=$(mktemp "${TMPDIR:-/tmp}/magit-submodule-err.XXXXXX")
        if ( cd "$toplevel" && git submodule update --init --recursive >/dev/null 2>"$err" ); then
            printf "echo -markup %%{{Information}submodule update --init --recursive}\n"
        else
            reason=$(head -1 "$err" | tr -d "'")
            [ -z "$reason" ] && reason="git submodule update failed"
            printf "fail 'submodule update failed: %s'\n" "$reason"
        fi
        rm -f "$err"
        printf "magit-refresh-after-mutation\n"
    }
}

# --- deinit: prompt path; --force to handle dirty submodules ---
define-command -hidden magit-submodule-deinit-prompt %{
    prompt 'deinit submodule (path): ' magit-submodule-deinit-apply
}
define-command -hidden magit-submodule-deinit-apply %{
    evaluate-commands %sh{
        path=$kak_text
        if [ -z "$path" ]; then
            echo "fail 'magit-submodule deinit: path required'"
            exit
        fi
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
        [ -z "$toplevel" ] && { echo "fail 'magit-submodule: not in a git worktree'"; exit; }
        err=$(mktemp "${TMPDIR:-/tmp}/magit-submodule-err.XXXXXX")
        if ( cd "$toplevel" && git submodule deinit --force "$path" >/dev/null 2>"$err" ); then
            sp=$(printf '%s' "$path" | tr -d "'")
            printf "echo -markup %%{{Information}submodule deinit: %s}\n" "$sp"
        else
            reason=$(head -1 "$err" | tr -d "'")
            [ -z "$reason" ] && reason="git submodule deinit failed"
            printf "fail 'submodule deinit failed: %s'\n" "$reason"
        fi
        rm -f "$err"
        printf "magit-refresh-after-mutation\n"
    }
}

# --- list: info box ---
define-command -hidden magit-submodule-list %{
    evaluate-commands %sh{
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
        [ -z "$toplevel" ] && { echo "fail 'magit-submodule: not in a git worktree'"; exit; }
        out=$(cd "$toplevel" && git submodule status 2>/dev/null)
        if [ -z "$out" ]; then
            printf "echo -markup %%{{Information}no submodules}\n"
            exit
        fi
        body=$(printf '%s' "$out" | tr -d "'")
        printf "info -title submodules '%s'\n" "$body"
    }
}

}
