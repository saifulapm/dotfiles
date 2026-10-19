# magit-file.kak — file-dispatch transient: operate on the current file.
# `<space>g .` enters this user-mode. All actions resolve $kak_buffile,
# making them safe to invoke from any file buffer (status/log/etc. don't
# have a buffile path so the actions reject cleanly).
#
# Most actions delegate to existing commands. Only the file-scoped
# stage/unstage/discard/log are bespoke here — the others (diff/blame/
# log-line) already work because they read $kak_buffile themselves.

provide-module magit-file %{

declare-user-mode magit-file
define-command magit-file-dispatch -docstring 'Magit file dispatch (operate on current file)' %{
    enter-user-mode magit-file
}

map global magit-file s     ': magit-file-stage<ret>'        -docstring 'stage this file'
map global magit-file u     ': magit-file-unstage<ret>'      -docstring 'unstage this file'
map global magit-file D     ': magit-file-discard-prompt<ret>' -docstring 'discard worktree changes (confirm)'
map global magit-file d     ': magit-diff-buffile<ret>'      -docstring 'diff this file (worktree vs index)'
map global magit-file l     ': magit-file-log<ret>'          -docstring 'log this file'
map global magit-file b     ': magit-blame-toggle<ret>'      -docstring 'toggle blame'
map global magit-file <ret> ': magit-log-line<ret>'          -docstring 'last commit touching cursor line'

# --- Helpers --------------------------------------------------------
# Each command resolves a clean (toplevel, relative path) tuple from
# $kak_buffile. Returns nothing on failure; emits a kak `fail`/`echo`.
# Macro: every action runs this as the first thing in its %sh{} body.
# To keep brace-balance trivial under provide-module, we don't use a
# shell function — we inline the same 6 lines. Sorry, posterity.

define-command -hidden magit-file-stage %{
    evaluate-commands %sh{
        case "$kak_buffile" in
            /*) ;;
            *) echo "fail 'magit-file: not a file buffer'"; exit ;;
        esac
        toplevel=$(cd "$(dirname "$kak_buffile")" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)
        [ -z "$toplevel" ] && { echo "fail 'magit-file: not in a git repo'"; exit; }
        rel=${kak_buffile#"$toplevel/"}
        err=$(mktemp "${TMPDIR:-/tmp}/magit-file-err.XXXXXX")
        if ( cd "$toplevel" && git add -- "$rel" >/dev/null 2>"$err" ); then
            safe=$(printf '%s' "$rel" | tr -d "'")
            printf "echo -markup %%{{Information}staged %s}\n" "$safe"
        else
            reason=$(head -1 "$err" | tr -d "'")
            printf "fail 'stage failed: %s'\n" "$reason"
        fi
        rm -f "$err"
        printf "magit-refresh-after-mutation\n"
    }
}

define-command -hidden magit-file-unstage %{
    evaluate-commands %sh{
        case "$kak_buffile" in
            /*) ;;
            *) echo "fail 'magit-file: not a file buffer'"; exit ;;
        esac
        toplevel=$(cd "$(dirname "$kak_buffile")" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)
        [ -z "$toplevel" ] && { echo "fail 'magit-file: not in a git repo'"; exit; }
        rel=${kak_buffile#"$toplevel/"}
        err=$(mktemp "${TMPDIR:-/tmp}/magit-file-err.XXXXXX")
        if ( cd "$toplevel" && git reset HEAD -- "$rel" >/dev/null 2>"$err" ); then
            safe=$(printf '%s' "$rel" | tr -d "'")
            printf "echo -markup %%{{Information}unstaged %s}\n" "$safe"
        else
            reason=$(head -1 "$err" | tr -d "'")
            printf "fail 'unstage failed: %s'\n" "$reason"
        fi
        rm -f "$err"
        printf "magit-refresh-after-mutation\n"
    }
}

# Discard: prompt for confirmation (matches magit-confirm-discard
# pattern in magit-status.kak — same y/N idiom).
declare-option -hidden str magit_file_discard_path ''
define-command -hidden magit-file-discard-prompt %{
    evaluate-commands %sh{
        case "$kak_buffile" in
            /*) ;;
            *) echo "fail 'magit-file: not a file buffer'"; exit ;;
        esac
        toplevel=$(cd "$(dirname "$kak_buffile")" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)
        [ -z "$toplevel" ] && { echo "fail 'magit-file: not in a git repo'"; exit; }
        rel=${kak_buffile#"$toplevel/"}
        OB=$(printf '\173'); CB=$(printf '\175')
        printf "set-option global magit_file_discard_path %%%s%s%s\n" "$OB" "$rel" "$CB"
        printf "prompt 'Discard worktree changes to %s? (y/N): ' magit-file-discard-apply\n" "$rel"
    }
}

define-command -hidden magit-file-discard-apply %{
    evaluate-commands %sh{
        ans=$kak_text
        case "$ans" in
            y|Y|yes|YES) ;;
            *) echo "echo cancelled"; exit ;;
        esac
        rel=$kak_opt_magit_file_discard_path
        toplevel=$(cd "$(dirname "$kak_buffile")" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)
        [ -z "$toplevel" ] && { echo "fail 'magit-file: not in a git repo'"; exit; }
        err=$(mktemp "${TMPDIR:-/tmp}/magit-file-err.XXXXXX")
        if ( cd "$toplevel" && git checkout -- "$rel" >/dev/null 2>"$err" ); then
            safe=$(printf '%s' "$rel" | tr -d "'")
            printf "echo -markup %%{{Information}discarded changes to %s}\n" "$safe"
            # The buffer on disk just changed under kak — reload.
            printf "edit! %%{%s/%s}\n" "$toplevel" "$rel"
        else
            reason=$(head -1 "$err" | tr -d "'")
            printf "fail 'discard failed: %s'\n" "$reason"
        fi
        rm -f "$err"
        printf "set-option global magit_file_discard_path ''\n"
        printf "magit-refresh-after-mutation\n"
    }
}

# File log: render `git log --follow --pretty=format:'%h %s' -50` for the
# current file into a *magit-log-file-<name>* buffer. Per-buffer q close.
define-command -hidden magit-file-log %{
    evaluate-commands %sh{
        case "$kak_buffile" in
            /*) ;;
            *) echo "fail 'magit-file: not a file buffer'"; exit ;;
        esac
        toplevel=$(cd "$(dirname "$kak_buffile")" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)
        [ -z "$toplevel" ] && { echo "fail 'magit-file: not in a git repo'"; exit; }
        rel=${kak_buffile#"$toplevel/"}
        OB=$(printf '\173'); CB=$(printf '\175')
        # Sanitize name for the buffer label (kak buffer names tolerate
        # most chars but we keep it conservative).
        safe_label=$(printf '%s' "$rel" | tr -c 'A-Za-z0-9_.-' '_')
        tmp=$(mktemp "${TMPDIR:-/tmp}/magit-file-log.XXXXXX")
        ( cd "$toplevel" && git log --follow --pretty=format:'%h %s' -50 --no-color -- "$rel" ) > "$tmp" 2>/dev/null
        if [ ! -s "$tmp" ]; then
            rm -f "$tmp"
            printf "echo -markup %%{{Information}no log entries for %s}\n" "$rel"
            exit
        fi
        printf "edit -scratch '*magit-log-file-%s*'\n" "$safe_label"
        printf "set-option buffer filetype git-log\n"
        printf "map buffer normal q ': delete-buffer<ret>'\n"
        printf "execute-keys '%%|cat %s<ret>gg'\n" "$tmp"
        printf "nop %%sh%s rm -f '%s' %s\n" "$OB" "$tmp" "$CB"
    }
}

}
