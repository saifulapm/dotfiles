# magit-bisect.kak — bisect transient (`<space>g i`) and related actions.
# Thin wrappers over `git bisect <verb>` with error capture. State lives in
# .git/BISECT_LOG; status section (in magit-status.kak) renders progress.

provide-module magit-bisect %{

declare-user-mode magit-bisect

define-command magit-bisect-dispatch -docstring 'Magit bisect transient' %{
    enter-user-mode magit-bisect
}

map global magit-bisect B ': magit-bisect-start<ret>'     -docstring 'start bisect'
map global magit-bisect g ': magit-bisect-good<ret>'      -docstring 'good (mark HEAD good)'
map global magit-bisect b ': magit-bisect-bad<ret>'       -docstring 'bad (mark HEAD bad)'
map global magit-bisect k ': magit-bisect-skip<ret>'      -docstring 'skip current commit'
map global magit-bisect r ': magit-bisect-reset<ret>'     -docstring 'reset (end bisect)'
map global magit-bisect l ': magit-bisect-log<ret>'       -docstring 'show bisect log'
map global magit-bisect v ': magit-bisect-visualize<ret>' -docstring 'visualize (scratch)'

# Shared runner: $1 = verb, $2 = human label for success echo.
define-command -hidden -params 2 magit-bisect-run %{
    evaluate-commands %sh{
        verb=$1
        label=$2
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
        if [ -z "$toplevel" ]; then
            echo "fail 'magit-bisect: not in a git repo'"
            exit
        fi
        err=$(mktemp "${TMPDIR:-/tmp}/magit-bisect-err.XXXXXX")
        out=$(mktemp "${TMPDIR:-/tmp}/magit-bisect-out.XXXXXX")
        # Capture stdout too — git bisect writes the "X is the first bad commit"
        # conclusion AND dirty-worktree errors partly there, and we want any
        # message we can surface as the reason on failure.
        ( cd "$toplevel" && GIT_EDITOR=true GIT_SEQUENCE_EDITOR=true \
                git bisect "$verb" >"$out" 2>"$err" )
        rc=$?
        if [ "$rc" = 0 ]; then
            printf "echo -markup %%{{Information}bisect %s}\n" "$label"
        else
            # Prefer stderr (meaningful errors: "Your local changes…",
            # "waiting for…"), fall back to stdout, then a canned message.
            reason=$(grep -v '^$' "$err" | head -1 | tr -d "'{}" | tr '\n' ' ')
            [ -z "$reason" ] && reason=$(grep -v '^$' "$out" | head -1 | tr -d "'{}" | tr '\n' ' ')
            [ -z "$reason" ] && reason="exit $rc (no message)"
            printf "fail 'bisect %s: %s'\n" "$label" "$reason"
        fi
        rm -f "$err" "$out"
        printf "magit-refresh-after-mutation\n"
    }
}

define-command magit-bisect-start -docstring 'Start a bisect session' %{
    magit-bisect-run start started
}
define-command magit-bisect-good -docstring 'Mark HEAD good' %{
    magit-bisect-run good good
}
define-command magit-bisect-bad -docstring 'Mark HEAD bad' %{
    magit-bisect-run bad bad
}
define-command magit-bisect-skip -docstring 'Skip current commit' %{
    magit-bisect-run skip skipped
}
define-command magit-bisect-reset -docstring 'End bisect session' %{
    magit-bisect-run reset reset
}

define-command magit-bisect-log -docstring 'Show `git bisect log` in an info box' %{
    evaluate-commands %sh{
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
        [ -z "$toplevel" ] && { echo "fail 'magit-bisect: not in a git repo'"; exit; }
        gitdir=$(cd "$toplevel" && git rev-parse --git-dir 2>/dev/null)
        case "$gitdir" in /*) ;; *) gitdir="$toplevel/$gitdir" ;; esac
        if [ ! -f "$gitdir/BISECT_LOG" ]; then
            echo "fail 'magit-bisect: no bisect in progress'"
            exit
        fi
        out=$(cd "$toplevel" && git bisect log 2>/dev/null)
        if [ -z "$out" ]; then
            echo "echo -markup %{{Information}bisect log is empty}"
            exit
        fi
        body=$(printf '%s' "$out" | tr -d "'")
        printf "info -title bisect-log '%s'\n" "$body"
    }
}

define-command magit-bisect-visualize -docstring 'Visualize bisect range in a scratch buffer' %{
    evaluate-commands %sh{
        OB=$(printf '\173'); CB=$(printf '\175')
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
        [ -z "$toplevel" ] && { echo "fail 'magit-bisect: not in a git repo'"; exit; }
        gitdir=$(cd "$toplevel" && git rev-parse --git-dir 2>/dev/null)
        case "$gitdir" in /*) ;; *) gitdir="$toplevel/$gitdir" ;; esac
        if [ ! -f "$gitdir/BISECT_LOG" ]; then
            echo "fail 'magit-bisect: no bisect in progress'"
            exit
        fi
        tmp=$(mktemp "${TMPDIR:-/tmp}/magit-bisect-vis.XXXXXX")
        ( cd "$toplevel" && GIT_EDITOR=true \
            git bisect visualize --oneline --no-color ) > "$tmp" 2>/dev/null
        if [ ! -s "$tmp" ]; then
            rm -f "$tmp"
            echo "echo -markup %{{Information}bisect visualize: empty}"
            exit
        fi
        sed -i.bak 's/[[:space:]]*$//' "$tmp" && rm -f "$tmp.bak"
        printf "edit -scratch '*magit-bisect-visualize*'\n"
        printf "set-option buffer filetype git-log\n"
        printf "map buffer normal q ': delete-buffer<ret>'\n"
        printf "execute-keys %%%s%%|cat %s<ret>gg%s\n" "$OB" "$tmp" "$CB"
        printf "nop %%sh%s rm -f '%s' %s\n" "$OB" "$tmp" "$CB"
    }
}

}
