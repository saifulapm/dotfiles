# magit-gitignore.kak — append pattern to .gitignore / subdir .gitignore /
# .git/info/exclude. Idempotent (refuses to double-add an identical line).
# Pre-fills the prompt with the current buffer's path relative to the
# target dir.

provide-module magit-gitignore %{

declare-option -hidden str magit_gitignore_target ''

declare-user-mode magit-gitignore

define-command magit-gitignore-dispatch -docstring 'Magit gitignore transient' %{
    enter-user-mode magit-gitignore
}

map global magit-gitignore t ': magit-gitignore-begin top<ret>'    -docstring 'add to top-level .gitignore'
map global magit-gitignore s ': magit-gitignore-begin subdir<ret>' -docstring 'add to nearest-subdir .gitignore'
map global magit-gitignore g ': magit-gitignore-begin exclude<ret>' -docstring 'add to .git/info/exclude (local)'

define-command -hidden -params 1 magit-gitignore-begin %{
    set-option global magit_gitignore_target %arg{1}
    evaluate-commands %sh{
        target=$1
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
        if [ -z "$toplevel" ]; then
            echo "fail 'magit-gitignore: not in a git worktree'"
            exit
        fi

        # Pre-fill: relative path from the current buffer to the target's
        # base dir. For `top` and `exclude`, that's repo-root-relative; for
        # `subdir`, it's buffile-dir-relative (the name alone).
        buffile=$kak_buffile
        default=""
        if [ -n "$buffile" ] && [ -f "$buffile" ]; then
            case "$target" in
                top|exclude)
                    # Strip toplevel prefix; if buffile is outside the repo,
                    # leave default empty.
                    case "$buffile" in
                        "$toplevel/"*) default="${buffile#$toplevel/}" ;;
                    esac
                    ;;
                subdir)
                    default=$(basename "$buffile")
                    ;;
            esac
        fi
        esc_default=$(printf '%s' "$default" | sed "s/'/''/g")
        printf "prompt 'gitignore pattern: ' -init '%s' magit-gitignore-apply\n" "$esc_default"
    }
}

define-command -hidden magit-gitignore-apply %{
    evaluate-commands %sh{
        pattern=$(printf '%s' "$kak_text" | awk '{$1=$1; print}')
        target=$kak_opt_magit_gitignore_target
        if [ -z "$pattern" ]; then
            echo "fail 'magit-gitignore: empty pattern'"
            exit
        fi
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
        if [ -z "$toplevel" ]; then
            echo "fail 'magit-gitignore: not in a git worktree'"
            exit
        fi
        gitdir=$(git rev-parse --git-dir 2>/dev/null)
        case "$gitdir" in /*) ;; *) gitdir="$toplevel/$gitdir" ;; esac

        # Resolve destination file per target.
        case "$target" in
            top)     dest="$toplevel/.gitignore" ;;
            exclude) dest="$gitdir/info/exclude" ;;
            subdir)
                # nearest .gitignore upward from buffile's dir, or create one
                # in buffile's dir if none found within the repo.
                dir=""
                buffile=$kak_buffile
                if [ -n "$buffile" ] && [ -f "$buffile" ]; then
                    case "$buffile" in
                        "$toplevel/"*) dir=$(dirname "$buffile") ;;
                    esac
                fi
                [ -z "$dir" ] && dir="$toplevel"
                dest="$dir/.gitignore"
                ;;
            *) printf "fail 'magit-gitignore: unknown target %s'\n" "$target"; exit ;;
        esac

        # Idempotence: skip if the exact line already exists.
        if [ -f "$dest" ] && grep -Fxq "$pattern" "$dest"; then
            esc_pat=$(printf '%s' "$pattern" | tr -d "'")
            esc_dest=$(printf '%s' "$dest" | tr -d "'")
            printf "echo -markup %%{{Information}gitignore: '%s' already in %s}\n" "$esc_pat" "$esc_dest"
            exit
        fi

        # Ensure parent dir + trailing newline on the destination before we
        # append (so the new entry starts on its own line).
        mkdir -p "$(dirname "$dest")"
        if [ -f "$dest" ] && [ -s "$dest" ]; then
            # Append newline if file doesn't end with one.
            if [ "$(tail -c1 "$dest" | od -An -c | tr -d ' ')" != '\n' ]; then
                printf '\n' >> "$dest"
            fi
        fi
        printf '%s\n' "$pattern" >> "$dest"

        esc_pat=$(printf '%s' "$pattern" | tr -d "'")
        esc_dest=$(printf '%s' "$dest" | sed "s|^$toplevel/||" | tr -d "'")
        printf "echo -markup %%{{Information}gitignore: added '%s' to %s}\n" "$esc_pat" "$esc_dest"
        printf "set-option global magit_gitignore_target ''\n"
        printf 'magit-refresh-after-mutation\n'
    }
}

}
