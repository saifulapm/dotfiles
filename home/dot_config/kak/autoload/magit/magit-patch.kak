# magit-patch.kak — format-patch / apply / am transient.
# Actions:
#   c — create .patch files from a commit range (git format-patch)
#   a — apply a .patch file to worktree  (git apply)
#   m — apply an mbox via git am (can conflict → continue/abort)
#   C — am --continue
#   A — am --abort

provide-module magit-patch %{

declare-user-mode magit-patch

define-command magit-patch-dispatch -docstring 'Magit patch transient' %{
    enter-user-mode magit-patch
}

map global magit-patch c ': prompt %{format-patch base (e.g. HEAD~3): } magit-patch-create-apply<ret>' -docstring 'create .patch files for base..HEAD'
map global magit-patch a ': prompt %{apply .patch path: } magit-patch-apply-apply<ret>'                -docstring 'git apply <patch>'
map global magit-patch m ': prompt %{git am mbox path: } magit-patch-am-apply<ret>'                    -docstring 'git am <mbox>'
map global magit-patch C ': magit-patch-am-continue<ret>'                                              -docstring 'am --continue'
map global magit-patch A ': magit-patch-am-abort<ret>'                                                 -docstring 'am --abort'

define-command -hidden magit-patch-create-apply %{
    evaluate-commands %sh{
        base=$(printf '%s' "$kak_text" | awk '{$1=$1; print}')
        if [ -z "$base" ]; then
            echo "fail 'magit-patch-create: empty base'"
            exit
        fi
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
        [ -z "$toplevel" ] && { echo "fail 'not in a git worktree'"; exit; }
        if ! ( cd "$toplevel" && git rev-parse --verify "$base" ) >/dev/null 2>&1; then
            printf "fail 'magit-patch-create: unknown ref %s'\n" "$base"
            exit
        fi
        err=$(mktemp "${TMPDIR:-/tmp}/magit-patch-err.XXXXXX")
        out=$(mktemp "${TMPDIR:-/tmp}/magit-patch-out.XXXXXX")
        # -o writes patches to an explicit dir (worktree root, so paths in
        # subsequent apply prompts are stable). git format-patch prints the
        # generated filenames on stdout.
        if ( cd "$toplevel" && git format-patch -o "$toplevel" "$base..HEAD" >"$out" 2>"$err" ); then
            files=$(wc -l < "$out" | tr -d ' ')
            if [ "$files" = "0" ]; then
                printf "fail 'magit-patch-create: no commits in %s..HEAD'\n" "$base"
            else
                first=$(head -1 "$out" | tr -d "'\"")
                printf "echo -markup %%{{Information}wrote %s patch file(s), first: %s}\n" "$files" "$first"
            fi
        else
            reason=$(head -1 "$err" | tr -d "'\"")
            [ -z "$reason" ] && reason='git format-patch exited non-zero'
            printf "fail 'magit-patch-create: %s'\n" "$reason"
        fi
        rm -f "$err" "$out"
    }
}

define-command -hidden magit-patch-apply-apply %{
    evaluate-commands %sh{
        patch=$(printf '%s' "$kak_text" | awk '{$1=$1; print}')
        if [ -z "$patch" ]; then
            echo "fail 'magit-patch-apply: empty path'"
            exit
        fi
        case "$patch" in
            '~'|'~/'*) patch="$HOME${patch#\~}" ;;
        esac
        if [ ! -f "$patch" ]; then
            printf "fail 'magit-patch-apply: file not found: %s'\n" "$patch"
            exit
        fi
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
        [ -z "$toplevel" ] && { echo "fail 'not in a git worktree'"; exit; }

        err=$(mktemp "${TMPDIR:-/tmp}/magit-patch-err.XXXXXX")
        if ( cd "$toplevel" && git apply -- "$patch" >/dev/null 2>"$err" ); then
            printf "echo -markup %%{{Information}applied %s}\n" "$(basename "$patch" | tr -d "'\"")"
        else
            reason=$(head -1 "$err" | tr -d "'\"")
            [ -z "$reason" ] && reason='git apply exited non-zero'
            printf "fail 'magit-patch-apply: %s'\n" "$reason"
        fi
        rm -f "$err"
        printf 'magit-refresh-after-mutation\n'
    }
}

define-command -hidden magit-patch-am-apply %{
    evaluate-commands %sh{
        mbox=$(printf '%s' "$kak_text" | awk '{$1=$1; print}')
        if [ -z "$mbox" ]; then
            echo "fail 'magit-patch-am: empty path'"
            exit
        fi
        case "$mbox" in
            '~'|'~/'*) mbox="$HOME${mbox#\~}" ;;
        esac
        if [ ! -f "$mbox" ]; then
            printf "fail 'magit-patch-am: file not found: %s'\n" "$mbox"
            exit
        fi
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
        [ -z "$toplevel" ] && { echo "fail 'not in a git worktree'"; exit; }
        gitdir=$(cd "$toplevel" && git rev-parse --git-dir 2>/dev/null)
        case "$gitdir" in /*) ;; *) gitdir="$toplevel/$gitdir" ;; esac

        if [ -d "$gitdir/rebase-apply" ]; then
            echo "fail 'magit-patch-am: am already in progress — use am --continue or --abort'"
            exit
        fi

        err=$(mktemp "${TMPDIR:-/tmp}/magit-patch-am-err.XXXXXX")
        # --3way: on conflict, fall back to 3-way merge using the blob
        # SHAs in the patch's index lines. This writes proper conflict
        # markers into the worktree instead of just refusing, so the user
        # can resolve + continue. Magit-emacs also passes --3way by default.
        # GIT_EDITOR=true: if mbox carries an empty message, git am falls back
        # to opening COMMIT_EDITMSG; suppress that interactive path.
        if ( cd "$toplevel" && GIT_EDITOR=true git am --3way -- "$mbox" >/dev/null 2>"$err" ); then
            printf "echo -markup %%{{Information}am applied %s}\n" "$(basename "$mbox" | tr -d "'\"")"
        else
            reason=$(grep -iE 'conflict|patch failed|error' "$err" | head -1 | tr -d "'\"")
            [ -z "$reason" ] && reason=$(head -1 "$err" | tr -d "'\"")
            [ -z "$reason" ] && reason='git am exited non-zero'
            if [ -d "$gitdir/rebase-apply" ]; then
                printf "fail 'am conflict: %s — fix + stage, then <space>g N C to continue or <space>g N A to abort'\n" "$reason"
            else
                printf "fail 'magit-patch-am: %s'\n" "$reason"
            fi
        fi
        rm -f "$err"
        printf 'magit-refresh-after-mutation\n'
    }
}

define-command -hidden magit-patch-am-continue %{
    evaluate-commands %sh{
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
        [ -z "$toplevel" ] && { echo "fail 'not in a git worktree'"; exit; }
        gitdir=$(cd "$toplevel" && git rev-parse --git-dir 2>/dev/null)
        case "$gitdir" in /*) ;; *) gitdir="$toplevel/$gitdir" ;; esac
        if [ ! -d "$gitdir/rebase-apply" ]; then
            echo "fail 'magit-patch-am-continue: no am in progress'"
            exit
        fi
        err=$(mktemp "${TMPDIR:-/tmp}/magit-patch-am-cont-err.XXXXXX")
        if ( cd "$toplevel" && GIT_EDITOR=true git am --continue >/dev/null 2>"$err" ); then
            if [ -d "$gitdir/rebase-apply" ]; then
                printf "echo -markup %%{{Information}am still in progress — next patch}\n"
            else
                printf "echo am continued and finished\n"
            fi
        else
            reason=$(head -1 "$err" | tr -d "'\"")
            [ -z "$reason" ] && reason='git am --continue exited non-zero'
            printf "fail 'am --continue: %s'\n" "$reason"
        fi
        rm -f "$err"
        printf 'magit-refresh-after-mutation\n'
    }
}

define-command -hidden magit-patch-am-abort %{
    evaluate-commands %sh{
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
        [ -z "$toplevel" ] && { echo "fail 'not in a git worktree'"; exit; }
        gitdir=$(cd "$toplevel" && git rev-parse --git-dir 2>/dev/null)
        case "$gitdir" in /*) ;; *) gitdir="$toplevel/$gitdir" ;; esac
        if [ ! -d "$gitdir/rebase-apply" ]; then
            echo "fail 'magit-patch-am-abort: no am in progress'"
            exit
        fi
        ( cd "$toplevel" && git am --abort >/dev/null 2>&1 ) || true
        printf "echo am aborted\n"
        printf 'magit-refresh-after-mutation\n'
    }
}

}
