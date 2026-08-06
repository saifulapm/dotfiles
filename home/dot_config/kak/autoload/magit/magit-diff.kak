# magit-diff.kak — *magit-diff* buffer + diff transient.
# Renders arbitrary `git diff` invocations: unstaged / staged / commit /
# range / file. Flags accumulate in magit_diff_args (uses the existing
# transient framework's primitives).

provide-module magit-diff %{

# `magit-diff-staged` already exists in magit-git.kak; we route the `s`
# action through it for consistency. The dispatch and the rest live here.

declare-user-mode magit-diff
declare-option -hidden str magit_diff_args ''

define-command magit-diff-dispatch -docstring 'Magit diff transient' %{
    # magit-modeline-update lives in the lazily-loaded magit-transients
    # module; -safe loads it on first use. Once loaded, the magit-diff
    # user-mode keybindings and magit-diff-render can call it directly.
    magit-modeline-update-safe
    enter-user-mode magit-diff
}

# --- Flag toggles (uppercase to free the lowercase keys for actions) ---
map global magit-diff W ': magit-transient-toggle magit_diff_args --word-diff<ret>: magit-modeline-update<ret>: enter-user-mode magit-diff<ret>' -docstring 'toggle --word-diff'
map global magit-diff T ': magit-transient-toggle magit_diff_args --stat<ret>: magit-modeline-update<ret>: enter-user-mode magit-diff<ret>'        -docstring 'toggle --stat'
map global magit-diff R ': magit-transient-toggle magit_diff_args -R<ret>: magit-modeline-update<ret>: enter-user-mode magit-diff<ret>'             -docstring 'toggle -R (reverse)'

# --- Actions ---
map global magit-diff u ': magit-diff-unstaged<ret>'        -docstring 'unstaged (worktree vs index)'
map global magit-diff s ': magit-diff-staged-routed<ret>'   -docstring 'staged (index vs HEAD)'
map global magit-diff c ': magit-diff-commit-prompt<ret>'   -docstring 'show commit (prompt for ref)'
map global magit-diff r ': magit-diff-range-prompt<ret>'    -docstring 'range A..B (prompt)'
map global magit-diff f ': magit-diff-buffile<ret>'         -docstring 'current file (worktree vs index)'

# --- Shared renderer: take a label + a git argv tail, run, fill buffer ---
# Args: $1 = label (suffixed onto buffer name *magit-diff-<label>*)
#       $2.. = git argv tail (after `git`).
define-command -hidden -params 2.. magit-diff-render %{
    evaluate-commands %sh{
        OB=$(printf '\173'); CB=$(printf '\175')
        label=$1; shift
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
        if [ -z "$toplevel" ]; then
            echo "fail 'magit-diff: not in a git repo'"
            exit
        fi
        # Prepend accumulated flag args. Word-split is intentional —
        # flags are already space-separated tokens with no spaces inside.
        args="$kak_opt_magit_diff_args"
        tmp=$(mktemp "${TMPDIR:-/tmp}/magit-diff.XXXXXX")
        ( cd "$toplevel" && git "$@" $args --no-color ) > "$tmp" 2>/dev/null
        if [ ! -s "$tmp" ]; then
            rm -f "$tmp"
            printf "echo -markup '%sInformation%sNothing to diff (%s)'\n" "$OB" "$CB" "$label"
            # Clear flags so a second attempt isn't sticky.
            printf "set-option global magit_diff_args ''\n"
            printf "magit-modeline-update\n"
            exit
        fi
        printf "edit -scratch '*magit-diff-%s*'\n" "$label"
        printf "set-option buffer filetype git-diff\n"
        # Buffer-local quit binding so we don't shadow kak's `q`
        # (record-macro) for all git-diff buffers in the session.
        printf "map buffer normal q ': delete-buffer<ret>'\n"
        printf "map buffer normal '?' ': enter-user-mode magit-diff-view-keys<ret>'\n"
        printf "execute-keys '%%|cat %s<ret>gg'\n" "$tmp"
        printf "nop %%sh%s rm -f '%s' %s\n" "$OB" "$tmp" "$CB"
        # Clear flags after each render so they don't carry between actions.
        printf "set-option global magit_diff_args ''\n"
        printf "magit-modeline-update\n"
    }
}

# --- Action implementations ---
define-command -hidden magit-diff-unstaged %{
    magit-diff-render unstaged diff
}

# Route through existing `magit-diff-staged` so we keep one source of truth
# for that path. Flags accumulated via the transient still flow through:
# `magit-diff-staged` itself doesn't read them, so to honor flags we
# render-with-flags here using --cached.
define-command -hidden magit-diff-staged-routed %{
    magit-diff-render staged diff --cached
}

define-command -hidden magit-diff-commit-prompt %{
    prompt 'show commit (ref): ' magit-diff-commit-apply
}
define-command -hidden magit-diff-commit-apply %{
    evaluate-commands %sh{
        ref=$kak_text
        if [ -z "$ref" ]; then
            echo "fail 'magit-diff: empty ref'"
            exit
        fi
        # `git show` uses different args; word-diff/stat still apply.
        # Sanitize ref label for the buffer name (slashes/braces would
        # break the kak buffer-name token).
        safe=$(printf '%s' "$ref" | tr -c 'A-Za-z0-9_.-' '_')
        printf "magit-diff-render show-%s show %s\n" "$safe" "$ref"
    }
}

define-command -hidden magit-diff-range-prompt %{
    prompt 'range (A..B): ' magit-diff-range-apply
}
define-command -hidden magit-diff-range-apply %{
    evaluate-commands %sh{
        range=$kak_text
        if [ -z "$range" ]; then
            echo "fail 'magit-diff: empty range'"
            exit
        fi
        case "$range" in
            *..*) ;;
            *) echo "fail 'magit-diff: range must be of form A..B'"; exit ;;
        esac
        safe=$(printf '%s' "$range" | tr -c 'A-Za-z0-9_.-' '_')
        printf "magit-diff-render range-%s diff %s\n" "$safe" "$range"
    }
}

define-command -hidden magit-diff-buffile %{
    evaluate-commands %sh{
        case "$kak_buffile" in
            /*) ;;
            *) echo "fail 'magit-diff: not a file buffer'"; exit ;;
        esac
        toplevel=$(cd "$(dirname "$kak_buffile")" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)
        if [ -z "$toplevel" ]; then
            echo "fail 'magit-diff: file not in a git repo'"
            exit
        fi
        rel=${kak_buffile#"$toplevel/"}
        safe=$(printf '%s' "$rel" | tr -c 'A-Za-z0-9_.-' '_')
        printf "magit-diff-render file-%s diff -- %s\n" "$safe" "$rel"
    }
}

# Per-buffer `q` is added by `magit-diff-render` after `edit -scratch`,
# so we don't pollute every git-diff buffer in the session. No filetype
# hook needed here.

# --- DWIM dispatcher ---
# Context-aware diff:
#   magit-log     -> show commit at cursor (via magit-show-commit)
#   magit-reflog  -> show commit at cursor (via magit-show-commit)
#   magit-branches-> diff HEAD..<branch-at-cursor>
#   anything else -> magit-diff-buffile (worktree vs index for this file)
define-command -hidden magit-diff-dwim-branch-apply %{
    magit-branch-name-at-cursor d
    evaluate-commands %sh{
        br=$kak_reg_d
        # Header lines ("Local", "Remote") yield empty after the 2-char
        # strip, as do blank lines. magit-branches prefixes every name line
        # with "* " or "  "; "## Local" etc. start with '#', whose 2-char
        # strip leaves " Local". Reject names that contain whitespace or
        # are empty/start with #.
        case "$br" in
            ''|'#'*|*' '*|'Local'|'Remote')
                echo "echo -markup %{{Information}no branch on this line}"
                exit
                ;;
        esac
        safe=$(printf '%s' "$br" | tr -c 'A-Za-z0-9_.-' '_')
        printf "magit-diff-render 'branch-%s' diff 'HEAD..%s'\n" "$safe" "$br"
    }
}

define-command magit-diff-dwim -docstring 'context-aware diff at cursor' %{
    evaluate-commands %sh{
        ft=$kak_opt_filetype
        case "$ft" in
        magit-log)
            idx=$kak_cursor_line
            eval "set -- $kak_quoted_opt_magit_log_shas"
            if [ "$idx" -gt "$#" ] || [ "$idx" -lt 1 ]; then
                echo "echo -markup %{{Information}no commit on this line}"
                exit
            fi
            eval "sha=\${$idx}"
            if [ -z "$sha" ]; then
                echo "echo -markup %{{Information}graph-only line}"
                exit
            fi
            printf 'magit-show-commit %s\n' "$sha"
            ;;
        magit-reflog)
            idx=$kak_cursor_line
            eval "set -- $kak_quoted_opt_magit_reflog_shas"
            if [ "$idx" -gt "$#" ] || [ "$idx" -lt 1 ]; then
                echo "echo -markup %{{Information}no commit on this line}"
                exit
            fi
            eval "sha=\${$idx}"
            if [ -z "$sha" ]; then
                echo "echo -markup %{{Information}no sha on this line}"
                exit
            fi
            printf 'magit-show-commit %s\n' "$sha"
            ;;
        magit-branches)
            # Delegate to the existing helper so we don't duplicate the
            # line-parsing logic (and pick up its header/comment guards).
            printf 'magit-diff-dwim-branch-apply\n'
            ;;
        *)
            printf 'magit-diff-buffile\n'
            ;;
        esac
    }
}

}
