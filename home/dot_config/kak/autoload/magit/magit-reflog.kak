# magit-reflog.kak — *magit-reflog* buffer: HEAD reflog viewer.
# Safety net for recovery after reset/rebase/etc. Mirrors magit-log.kak's
# shape: per-line SHA linemap, <ret> → magit-show-commit.

provide-module magit-reflog %{

declare-option -hidden str-list magit_reflog_shas
declare-option -hidden int magit_reflog_limit 100

define-command magit-reflog -docstring 'Open the HEAD reflog buffer' %{
    evaluate-commands %sh{
        if ! git rev-parse --git-dir >/dev/null 2>&1; then
            echo "fail 'magit-reflog: not a git repository'"
            exit
        fi
    }
    try %{
        buffer '*magit-reflog*'
    } catch %{
        edit -scratch '*magit-reflog*'
        set-option buffer filetype magit-reflog
    }
    magit-reflog-render
}

define-command -hidden magit-reflog-render %{
    evaluate-commands %sh{
        tmp=$(mktemp "${TMPDIR:-/tmp}/magit-reflog.XXXXXX")
        shas=$(mktemp "${TMPDIR:-/tmp}/magit-reflog-shas.XXXXXX")
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
        if [ -z "$toplevel" ]; then
            printf "fail 'magit-reflog-render: not in a git worktree'\n"
            rm -f "$tmp" "$shas"
            exit
        fi
        limit=${kak_opt_magit_reflog_limit:-100}
        # Format: "<full>__MAGITSEP__<short> <selector>: <subject>".
        #   %H = full SHA, %h = short SHA, %gd = selector like HEAD@{3},
        #   %gs = reflog subject like "commit: foo" / "reset: moving to HEAD~1".
        ( cd "$toplevel" && git reflog --format='%H__MAGITSEP__%h %gd: %gs' -"$limit" --no-color ) > "$tmp" 2>/dev/null
        if [ ! -s "$tmp" ]; then
            echo "(no reflog entries — empty or freshly-initialized repo)" > "$tmp"
            : > "$shas"
        else
            # Extract full SHA from before __MAGITSEP__.
            awk '
                {
                    idx = index($0, "__MAGITSEP__")
                    if (idx > 0) {
                        # Reflog has no graph prefix — SHA starts at column 1.
                        print substr($0, 1, idx - 1) > "'"$shas"'"
                    } else {
                        print "" > "'"$shas"'"
                    }
                }
            ' "$tmp"
            # Strip "<full>__MAGITSEP__" prefix, leaving display rows.
            sed -i.bak 's/[0-9a-f]\{40\}__MAGITSEP__//g' "$tmp"
            rm -f "${tmp}.bak"
        fi

        OB=$(printf '\173')
        CB=$(printf '\175')
        printf "set-option buffer magit_reflog_shas\n"
        while IFS= read -r sha; do
            printf "set-option -add buffer magit_reflog_shas '%s'\n" "$sha"
        done < "$shas"
        printf "execute-keys '%%|cat %s<ret>gg'\n" "$tmp"
        printf "nop %%sh%s rm -f '%s' '%s' %s\n" "$OB" "$tmp" "$shas" "$CB"
    }
}

define-command -hidden magit-reflog-visit %{
    evaluate-commands %sh{
        idx=$kak_cursor_line
        eval "set -- $kak_quoted_opt_magit_reflog_shas"
        if [ "$idx" -gt "$#" ] || [ "$idx" -lt 1 ]; then
            echo "echo -markup %{{Information}no reflog entry on this line}"
            exit
        fi
        eval "sha=\${$idx}"
        if [ -z "$sha" ]; then
            echo "echo -markup %{{Information}placeholder line, no commit}"
            exit
        fi
        printf 'magit-show-commit %s\n' "$sha"
    }
}

# `?` help mode — keep in sync with the buffer bindings below.
declare-user-mode magit-reflog-keys
map global magit-reflog-keys <ret> ': magit-reflog-visit<ret>'           -docstring 'show commit at cursor'
map global magit-reflog-keys R     ': magit-reflog-render<ret>'          -docstring 'refresh'
map global magit-reflog-keys q     ': delete-buffer *magit-reflog*<ret>' -docstring 'quit reflog'
map global magit-reflog-keys n     ': execute-keys j<ret>'               -docstring 'next entry'
map global magit-reflog-keys p     ': execute-keys k<ret>'               -docstring 'previous entry'

hook global WinSetOption filetype=magit-reflog %{
    add-highlighter window/magit-reflog group
    add-highlighter window/magit-reflog/sha      regex '^[0-9a-f]{7,12}\b'     0:yellow
    add-highlighter window/magit-reflog/selector regex 'HEAD@\{[0-9]+\}'       0:cyan
    add-highlighter window/magit-reflog/verb     regex ':\s(commit|reset|checkout|rebase|merge|pull|cherry-pick|revert|amend|stash)\b' 1:green

    map buffer normal <ret> ': magit-reflog-visit<ret>'             -docstring 'show commit at cursor'
    map buffer normal R     ': magit-reflog-render<ret>'            -docstring 'refresh'
    map buffer normal q     ': delete-buffer *magit-reflog*<ret>'   -docstring 'quit reflog'
    # Re-bind n/p to line motion (kak's search-next/prev are useless here).
    map buffer normal n     j -docstring 'next entry'
    map buffer normal p     k -docstring 'previous entry'
    map buffer normal '?'   ': enter-user-mode magit-reflog-keys<ret>' -docstring 'show keys (help)'

    hook -once -always window WinSetOption filetype=.* %{
        remove-highlighter window/magit-reflog
        unmap buffer normal <ret>
        unmap buffer normal R
        unmap buffer normal q
        unmap buffer normal n
        unmap buffer normal p
        unmap buffer normal '?'
    }
}

}
