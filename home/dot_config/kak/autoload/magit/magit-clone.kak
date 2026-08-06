# magit-clone.kak — clone transient: regular / shallow / bare / mirror / sparse.
#
# Two-stage prompt: URL first, then destination. The URL is stashed in a
# hidden option so the destination-prompt callback can retrieve it. After
# git clone completes, cd the invoking client into the clone.

provide-module magit-clone %{

declare-option -hidden str magit_clone_url ''
declare-option -hidden str magit_clone_mode ''

declare-user-mode magit-clone

define-command magit-clone-dispatch -docstring 'Magit clone transient' %{
    enter-user-mode magit-clone
}

# One binding per variant. The `mode` identifier selects which extra git
# flags get passed at apply time.
map global magit-clone c ': magit-clone-begin regular<ret>'  -docstring 'regular clone'
map global magit-clone s ': magit-clone-begin shallow<ret>'  -docstring 'shallow --depth=1'
map global magit-clone b ': magit-clone-begin bare<ret>'     -docstring 'bare clone'
map global magit-clone m ': magit-clone-begin mirror<ret>'   -docstring 'mirror clone'
map global magit-clone p ': magit-clone-begin sparse<ret>'   -docstring 'sparse clone'

define-command -hidden -params 1 magit-clone-begin %{
    set-option global magit_clone_mode %arg{1}
    prompt 'clone URL: ' magit-clone-url-entered
}

define-command -hidden magit-clone-url-entered %{
    evaluate-commands %sh{
        url=$(printf '%s' "$kak_text" | awk '{$1=$1; print}')
        if [ -z "$url" ]; then
            echo "fail 'magit-clone: empty URL'"
            exit
        fi
        # Derive a sensible default dest: last path component, strip .git.
        default=$(printf '%s' "$url" | sed -E 's|/$||; s|.*/||; s|\.git$||')
        esc_default=$(printf '%s' "$default" | sed "s/'/''/g")
        esc_url=$(printf '%s' "$url" | sed "s/'/''/g")
        printf "set-option global magit_clone_url '%s'\n" "$esc_url"
        # Pre-fill the second prompt via -init.
        printf "prompt 'clone to (dir): ' -init '%s' magit-clone-dest-entered\n" "$esc_default"
    }
}

define-command -hidden magit-clone-dest-entered %{
    evaluate-commands %sh{
        dest=$(printf '%s' "$kak_text" | awk '{$1=$1; print}')
        url=$kak_opt_magit_clone_url
        mode=$kak_opt_magit_clone_mode
        if [ -z "$dest" ] || [ -z "$url" ] || [ -z "$mode" ]; then
            echo "fail 'magit-clone: missing url/dest/mode'"
            exit
        fi
        # Expand leading `~` by hand — kak's prompt passes the literal char.
        case "$dest" in
            '~'|'~/'*) dest="$HOME${dest#\~}" ;;
        esac

        # Refuse if dest already exists and isn't an empty dir. Git would
        # fail anyway; give a clean message.
        if [ -e "$dest" ]; then
            if [ -d "$dest" ] && [ -z "$(ls -A "$dest" 2>/dev/null)" ]; then
                :   # empty dir — git accepts it
            else
                printf "fail 'magit-clone: destination exists and is not empty: %s'\n" "$dest"
                exit
            fi
        fi

        args=""
        case "$mode" in
            shallow) args="--depth=1" ;;
            bare)    args="--bare" ;;
            mirror)  args="--mirror" ;;
            sparse)  args="--sparse --filter=blob:none" ;;
            regular) ;;
            *) printf "fail 'magit-clone: unknown mode %s'\n" "$mode"; exit ;;
        esac

        err=$(mktemp "${TMPDIR:-/tmp}/magit-clone-err.XXXXXX")
        # clone writes progress on stderr by default — don't mistake for error.
        if git clone $args -- "$url" "$dest" >/dev/null 2>"$err"; then
            rm -f "$err"
            printf "echo -markup %%{{Information}cloned %s into %s (%s)}\n" "$url" "$dest" "$mode"
            # cd the client into the clone, unless bare (no worktree) or mirror.
            case "$mode" in
                bare|mirror) ;;
                *)
                    esc_dest=$(printf '%s' "$dest" | sed "s/'/''/g")
                    printf "change-directory '%s'\n" "$esc_dest"
                    ;;
            esac
        else
            reason=$(tail -1 "$err" | tr -d "'\"")
            [ -z "$reason" ] && reason='git clone exited non-zero'
            rm -f "$err"
            printf "fail 'magit-clone: %s'\n" "$reason"
        fi
        printf "set-option global magit_clone_url ''\n"
        printf "set-option global magit_clone_mode ''\n"
    }
}

}
