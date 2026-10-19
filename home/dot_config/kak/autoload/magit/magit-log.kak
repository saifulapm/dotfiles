# magit-log.kak — *magit-log* buffer: browse commit history.
# Render: `git log --oneline --graph -50`. Each line maps to a SHA;
# <ret> calls magit-show-commit from magit-show.kak.

provide-module magit-log %{

# Per-line SHA list. Index aligns with buffer line numbers. Entry may be
# empty (graph-only lines with no commit, e.g. `|/`).
declare-option -hidden str-list magit_log_shas

declare-option -hidden int magit_log_limit 50

# Accumulated filter args. Set via the magit-log-filter user-mode (entered
# with `T` inside *magit-log*). Examples: "--all", "--author=alice",
# "--grep=fix", "--since=2.weeks". Always passed verbatim to git log.
declare-option -hidden str magit_log_args ''

# Rev scope for *magit-log*. Empty → HEAD (current branch, default).
# Set via magit-log-other (`O` inside *magit-log*) to browse another branch
# or ref without checking it out. Preserved across `R` refresh.
declare-option -hidden str magit_log_rev ''

# Log margin: when true, append `· <author>, <relative-date>` to each
# commit line. Toggled via `~` inside *magit-log*. Default on — daily-use
# logs benefit from seeing who/when at a glance.
declare-option -hidden bool magit_log_margin true

define-command magit-log -docstring 'Open the magit log buffer' %{
    evaluate-commands %sh{
        if ! git rev-parse --git-dir >/dev/null 2>&1; then
            echo "fail 'magit-log: not a git repository'"
            exit
        fi
    }
    try %{
        buffer '*magit-log*'
    } catch %{
        edit -scratch '*magit-log*'
        set-option buffer filetype magit-log
    }
    magit-log-render
}

define-command -hidden magit-log-render %{
    evaluate-commands %sh{
        tmp=$(mktemp "${TMPDIR:-/tmp}/magit-log.XXXXXX")
        shas=$(mktemp "${TMPDIR:-/tmp}/magit-log-shas.XXXXXX")
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
        if [ -z "$toplevel" ]; then
            printf 'fail %s\n' "'magit-log-render: not in a git worktree'"
            rm -f "$tmp" "$shas"
            exit
        fi
        limit=${kak_opt_magit_log_limit:-50}
        # Render + SHA-per-line extraction. We run git log twice: once for
        # the display (with --graph), once plain to get unambiguous SHAs.
        # Reason: `git log --graph --pretty=%h` includes the graph glyphs
        # in the output; splitting the glyph from the SHA per-line is
        # fragile. Instead, render with graph but use `--graph --pretty=
        # format` with a leading marker so we can pick SHAs out.
        #
        # Approach: use a single `git log` with a unique separator, then
        # awk-split. Line format: "<graph+glyphs> <sha> <subject>".
        #   git log --graph --pretty=format:'%h %s' -<limit>
        # Graph-only lines (no commit) have no SHA field.
        # Pass --graph by default; user can override with `--no-graph` in
        # magit_log_args. User flags (--author=, --grep=, --since= etc.)
        # are word-split intentionally (no flag value contains spaces in
        # our prompts; the prompt body is a single token like
        # `--author=alice` or `--grep=fix`).
        args="$kak_opt_magit_log_args"
        rev=$kak_opt_magit_log_rev
        margin=$kak_opt_magit_log_margin
        # Pass the rev positionally after all flags. Empty rev → HEAD.
        # When margin is on, include %an/%ar in the pretty format so awk
        # can lay out "<graph> <short> <subject> · <author>, <age>" per line.
        # Delimiter `__|__` separates fields; it's unlikely to appear in
        # commit messages and the post-processor strips it before display.
        if [ "$margin" = "true" ]; then
            fmt='%H__MAGITSEP__%h %s__|__%an__|__%ar'
        else
            fmt='%H__MAGITSEP__%h %s'
        fi
        ( cd "$toplevel" && git log --graph --pretty=format:"$fmt" -"$limit" $args $rev --no-color ) > "$tmp" 2>/dev/null
        if [ ! -s "$tmp" ]; then
            # Empty repo / no commits. Display a placeholder + empty SHA list.
            echo "(no commits yet)" > "$tmp"
            : > "$shas"
        else
            # Extract the full SHA from each line (or empty for graph-only).
            # Full SHA is the first __MAGITSEP__-separated token in the record.
            # For display, replace the "<full>__MAGITSEP__" with nothing.
            awk '
                {
                    # If line contains the separator, SHA is the substring
                    # from end-of-graph to separator.
                    idx = index($0, "__MAGITSEP__")
                    if (idx > 0) {
                        # Walk backward from idx-1 to find the start of the
                        # graph-then-sha segment (non-space run).
                        i = idx - 1
                        while (i > 0 && substr($0, i, 1) != " ") i--
                        # sha = chars [i+1 .. idx-1]
                        sha = substr($0, i + 1, idx - i - 1)
                        print sha > "'"$shas"'"
                    } else {
                        # Graph-only line (continuation glyphs).
                        print "" > "'"$shas"'"
                    }
                }
            ' "$tmp"
            # Strip the SHA + separator from display, leaving "<graph> <short> <subject>[__|__author__|__age]".
            sed -i.bak 's/[0-9a-f]\{40\}__MAGITSEP__//g' "$tmp"
            rm -f "${tmp}.bak"
            # When margin is on, re-lay the line: "<graph+sha+subject>  ·  <author>, <age>".
            # Separator `__|__` divides the three fields (only present on commit lines,
            # graph-only lines have no fields → awk leaves them alone).
            if [ "$margin" = "true" ]; then
                awk -F '__\\|__' '
                    NF >= 3 { printf "%s  \xc2\xb7  %s, %s\n", $1, $2, $3; next }
                    { print }
                ' "$tmp" > "${tmp}.marg"
                mv "${tmp}.marg" "$tmp"
            fi
        fi

        OB=$(printf '\173')
        CB=$(printf '\175')
        # Load SHA list into the option, one add per line (empty lines OK).
        # Clear first. Use a timestamp bump to force kak to notice.
        printf "set-option buffer magit_log_shas\n"
        while IFS= read -r sha; do
            printf "set-option -add buffer magit_log_shas '%s'\n" "$sha"
        done < "$shas"
        printf "execute-keys '%%|cat %s<ret>gg'\n" "$tmp"
        printf "nop %%sh%s rm -f '%s' '%s' %s\n" "$OB" "$tmp" "$shas" "$CB"
    }
}

define-command -hidden magit-log-visit %{
    evaluate-commands %sh{
        OB=$(printf '\173'); CB=$(printf '\175')
        idx=$kak_cursor_line
        eval "set -- $kak_quoted_opt_magit_log_shas"
        if [ "$idx" -gt "$#" ] || [ "$idx" -lt 1 ]; then
            echo "echo -markup %{{Information}no commit on this line}"
            exit
        fi
        eval "sha=\${$idx}"
        if [ -z "$sha" ]; then
            echo "echo -markup %{{Information}graph-only line, no commit}"
            exit
        fi
        printf 'magit-show-commit %s\n' "$sha"
    }
}

# `O` inside *magit-log*: prompt for a ref, validate, re-render with it.
# Empty input clears the rev (back to HEAD). Invalid refs refuse.
define-command magit-log-other -docstring 'Show log for a prompted ref' %{
    prompt 'log for ref: ' magit-log-other-apply
}

define-command -hidden magit-log-other-apply %{
    evaluate-commands %sh{
        rev=$(printf '%s' "$kak_text" | awk '{$1=$1; print}')
        if [ -z "$rev" ]; then
            # Empty input → clear scope, render HEAD.
            printf "set-option global magit_log_rev ''\n"
            printf 'magit-log-render\n'
            printf "echo log scope cleared (HEAD)\n"
            exit
        fi
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
        [ -z "$toplevel" ] && { echo "fail 'not in a git worktree'"; exit; }
        if ! ( cd "$toplevel" && git rev-parse --verify "$rev" ) >/dev/null 2>&1; then
            printf "fail 'magit-log: unknown ref: %s'\n" "$rev"
            exit
        fi
        esc=$(printf '%s' "$rev" | sed "s/'/''/g")
        printf "set-option global magit_log_rev '%s'\n" "$esc"
        printf 'magit-log-render\n'
        printf "echo -markup %%{{Information}log scope: %s}\n" "$rev"
    }
}

# V in *magit-log*: revert the commit at cursor into the worktree only
# (leaves index + history untouched). Delegates to the shared worker in
# magit-show.kak. Silent no-op on graph-only lines — same UX as <ret>.
define-command -hidden magit-log-revert-at-cursor %{
    evaluate-commands %sh{
        idx=$kak_cursor_line
        eval "set -- $kak_quoted_opt_magit_log_shas"
        if [ "$idx" -gt "$#" ] || [ "$idx" -lt 1 ]; then
            echo "echo -markup %{{Information}no commit on this line}"
            exit
        fi
        eval "sha=\${$idx}"
        if [ -z "$sha" ]; then
            echo "echo -markup %{{Information}graph-only line, no commit}"
            exit
        fi
        printf 'magit-revert-to-worktree %s\n' "$sha"
    }
}

# --- Filter transient: T inside *magit-log* enters this mode ---------
# Args accumulate in magit_log_args. Toggles use the existing
# magit-transient-toggle helper. Prompts are bespoke single-token
# inputs (multi-word values like "fix the bug" won't word-split safely;
# users wanting that should pre-encode it in shell).
declare-user-mode magit-log-filter

# The log-filter user-mode keybindings call magit-modeline-update, which
# lives in the lazily-loaded magit-transients module. This loader requires
# it before entering the mode so those keys work on first use.
define-command -hidden magit-log-filter-enter -docstring 'Load transients, then enter the log filter mode' %{
    require-module magit-transients
    enter-user-mode magit-log-filter
}

map global magit-log-filter a ': magit-transient-toggle magit_log_args --all<ret>: magit-modeline-update<ret>: magit-log-render<ret>: enter-user-mode magit-log-filter<ret>'      -docstring 'toggle --all'
map global magit-log-filter g ': magit-transient-toggle magit_log_args --no-graph<ret>: magit-modeline-update<ret>: magit-log-render<ret>: enter-user-mode magit-log-filter<ret>' -docstring 'toggle --no-graph'

map global magit-log-filter A ': magit-log-filter-author-prompt<ret>'  -docstring 'filter by author (prompt)'
map global magit-log-filter G ': magit-log-filter-grep-prompt<ret>'    -docstring 'filter by message grep (prompt)'
map global magit-log-filter S ': magit-log-filter-since-prompt<ret>'   -docstring 'filter --since (e.g. "2 weeks ago" — single token)'
map global magit-log-filter U ': magit-log-filter-until-prompt<ret>'   -docstring 'filter --until'
map global magit-log-filter c ': magit-log-filter-clear<ret>'          -docstring 'clear all filters'
map global magit-log-filter r ': magit-log-render<ret>'                -docstring 'refresh'

# Each prompt: ask for the value, then append `--<flag>=<text>` to args.
# Re-render after.
define-command -hidden magit-log-filter-author-prompt %{
    prompt 'author: ' magit-log-filter-author-apply
}
define-command -hidden magit-log-filter-author-apply %{
    magit-log-filter-add-flag --author %val{text}
}

define-command -hidden magit-log-filter-grep-prompt %{
    prompt 'grep: ' magit-log-filter-grep-apply
}
define-command -hidden magit-log-filter-grep-apply %{
    magit-log-filter-add-flag --grep %val{text}
}

define-command -hidden magit-log-filter-since-prompt %{
    prompt 'since (single token, e.g. 2.weeks): ' magit-log-filter-since-apply
}
define-command -hidden magit-log-filter-since-apply %{
    magit-log-filter-add-flag --since %val{text}
}

define-command -hidden magit-log-filter-until-prompt %{
    prompt 'until (single token, e.g. 2024-01-01): ' magit-log-filter-until-apply
}
define-command -hidden magit-log-filter-until-apply %{
    magit-log-filter-add-flag --until %val{text}
}

# Append `<flag>=<value>` to magit_log_args, re-render.
define-command -hidden -params 2 magit-log-filter-add-flag %{
    evaluate-commands %sh{
        flag=$1; val=$2
        if [ -z "$val" ]; then
            echo "echo cancelled (empty value)"
            exit
        fi
        cur=$kak_opt_magit_log_args
        new="$flag=$val"
        if [ -n "$cur" ]; then
            combined="$cur $new"
        else
            combined="$new"
        fi
        OB=$(printf '\173'); CB=$(printf '\175')
        printf 'set-option global magit_log_args %%%s%s%s\n' "$OB" "$combined" "$CB"
        printf 'magit-modeline-update\n'
        printf 'magit-log-render\n'
    }
}

define-command -hidden magit-log-filter-clear %{
    set-option global magit_log_args ''
    magit-modeline-update
    magit-log-render
}

# `~` in *magit-log*: toggle the margin (author + relative date trailing column).
define-command magit-log-margin-toggle -docstring 'Toggle log margin (author + age)' %{
    evaluate-commands %sh{
        case "$kak_opt_magit_log_margin" in
            true)  printf 'set-option global magit_log_margin false\n' ;;
            *)     printf 'set-option global magit_log_margin true\n' ;;
        esac
    }
    magit-log-render
}

# `?` help mode: press `?` in the buffer to see an autoinfo listing of
# every buffer-local binding with its docstring. Bindings below are
# duplicated into `magit-log-keys` so pressing `?` then the key also
# works as an alternative (discoverable) execution path. Keep the two
# map blocks in sync — same key, same command, same docstring.
declare-user-mode magit-log-keys
map global magit-log-keys <ret> ': magit-log-visit<ret>'           -docstring 'show commit at cursor'
map global magit-log-keys R     ': magit-log-render<ret>'          -docstring 'refresh'
map global magit-log-keys q     ': delete-buffer *magit-log*<ret>' -docstring 'quit log'
map global magit-log-keys T     ': magit-log-filter-enter<ret>' -docstring 'filter (transient)'
map global magit-log-keys V     ': magit-log-revert-at-cursor<ret>' -docstring 'revert commit into worktree (index untouched)'
map global magit-log-keys O     ': magit-log-other<ret>'           -docstring 'log other ref (prompt)'
map global magit-log-keys '~'   ': magit-log-margin-toggle<ret>'   -docstring 'toggle margin (author + age)'
map global magit-log-keys n     ': execute-keys j<ret>'            -docstring 'next commit'
map global magit-log-keys p     ': execute-keys k<ret>'            -docstring 'previous commit'

hook global WinSetOption filetype=magit-log %{
    add-highlighter window/magit-log group
    # Match short SHAs (the part after any graph glyphs), used by the
    # --pretty=format. Short SHA is 7-12 hex chars preceded by whitespace
    # or one of git's graph glyphs.
    add-highlighter window/magit-log/sha     regex '\b[0-9a-f]{7,12}\b' 0:yellow
    add-highlighter window/magit-log/graph   regex '^[*|\\/_ ]+'        0:cyan

    map buffer normal <ret> ': magit-log-visit<ret>' -docstring 'show commit at cursor'
    map buffer normal R     ': magit-log-render<ret>' -docstring 'refresh'
    map buffer normal q     ': delete-buffer *magit-log*<ret>' -docstring 'quit log'
    map buffer normal T     ': magit-log-filter-enter<ret>' -docstring 'filter (transient)'
    map buffer normal V     ': magit-log-revert-at-cursor<ret>' -docstring 'revert commit into worktree (index untouched)'
    map buffer normal O     ': magit-log-other<ret>' -docstring 'log other ref (prompt)'
    map buffer normal '~'   ': magit-log-margin-toggle<ret>' -docstring 'toggle margin (author + age)'
    # n / p shadow kak's search-next/prev (which are useless here — there's
    # no useful search pattern in a log buffer). Re-bind to line motion so
    # the muscle-memory "next entry / previous entry" works as expected.
    map buffer normal n     j -docstring 'next commit'
    map buffer normal p     k -docstring 'previous commit'
    map buffer normal '?'   ': enter-user-mode magit-log-keys<ret>' -docstring 'show keys (help)'

    hook -once -always window WinSetOption filetype=.* %{
        remove-highlighter window/magit-log
        unmap buffer normal <ret>
        unmap buffer normal R
        unmap buffer normal q
        unmap buffer normal T
        unmap buffer normal V
        unmap buffer normal O
        unmap buffer normal '~'
        unmap buffer normal n
        unmap buffer normal p
        unmap buffer normal '?'
    }
}

}
