# magit-commit.kak — commit transient + gitcommit buffer bindings.
# Depends on magit.kak's state (magit_modeline) and magit-transient-toggle.

provide-module magit-commit %{

# --- Commit transient (REQ-9) ------------------------------------------
declare-user-mode magit-commit

# Modeline integration: we expose the commit transient's accumulated flags
# as a dedicated modeline segment so they remain visible while the user
# stacks them. The segment is empty when flags are empty, so the modeline
# is clean during normal use. We prepend a `%opt{magit_modeline}` atom to
# the global modelinefmt once at load time.
declare-option -hidden str magit_modeline
set-face global MagitModeline "+b@StatusLineInfo"

# Prepend the atom to modelinefmt if not already present. We put the face
# tag INSIDE the format string because kak escapes open-brace in expanded
# values (see kak source client.cc:187 — it calls escape on open-brace).
# Only the raw format-string text can contain markup tags; option
# expansions cannot.
evaluate-commands %sh{
    case "$kak_opt_modelinefmt" in
        *magit_modeline*) ;;
        *)
            OB=$(printf '\173')
            CB=$(printf '\175')
            # New modelinefmt prefix: `{MagitModeline}%opt{magit_modeline}{Default}<rest>`
            # Option value carries its own trailing space when non-empty so
            # that no stray space appears when flags are cleared.
            printf 'set-option global modelinefmt %%%s%sMagitModeline%s%%opt%smagit_modeline%s%sDefault%s%s%s\n' \
                "$OB" \
                "$OB" "$CB" \
                "$OB" "$CB" \
                "$OB" "$CB" \
                "$kak_opt_modelinefmt" "$CB"
            ;;
    esac
}

# Backward-compat alias: commit transient's call sites use
# `magit-commit-modeline-update`. The shared renderer (magit-modeline-update)
# lives in the lazily-loaded magit-transients module, so route through the
# -safe loader which requires it on first use.
define-command -hidden magit-commit-modeline-update %{
    magit-modeline-update-safe
}

# Commit transient. We do NOT use `enter-user-mode -lock` because kak's
# source (commands.cc:2719) re-pushes the locked mode after every non-Esc
# key, regardless of what the mapping did. The only way to exit the lock
# is an interactive keyboard <esc> received as the next-key input — a
# mapping cannot un-lock itself programmatically.
#
# Instead: toggle keys explicitly re-enter the mode (staying transient);
# action keys just run and the mode naturally expires after one key.
# Flag state is surfaced persistently in the modeline, not via `echo`
# (which gets clobbered by the next status-line write).
define-command magit-commit-dispatch -docstring 'Magit commit transient' %{
    magit-commit-modeline-update
    enter-user-mode magit-commit
}

# Toggle keys: after flipping the flag, re-enter the mode so the user can
# keep stacking flags. Action keys don't re-enter — the mode auto-expires.
map global magit-commit s ': magit-transient-toggle magit_commit_args --signoff<ret>: magit-commit-modeline-update<ret>: enter-user-mode magit-commit<ret>' -docstring 'toggle --signoff'
map global magit-commit n ': magit-transient-toggle magit_commit_args --no-verify<ret>: magit-commit-modeline-update<ret>: enter-user-mode magit-commit<ret>' -docstring 'toggle --no-verify'
map global magit-commit a ': magit-transient-toggle magit_commit_args --all<ret>: magit-commit-modeline-update<ret>: enter-user-mode magit-commit<ret>'       -docstring 'toggle --all'
map global magit-commit e ': magit-transient-toggle magit_commit_args --allow-empty<ret>: magit-commit-modeline-update<ret>: enter-user-mode magit-commit<ret>' -docstring 'toggle --allow-empty'
map global magit-commit c ': magit-commit-do commit<ret>' -docstring 'commit'
map global magit-commit A ': magit-commit-do amend<ret>'  -docstring 'amend (--amend --edit)'
map global magit-commit E ': magit-commit-do extend<ret>' -docstring 'extend (--amend --no-edit)'
map global magit-commit w ': magit-commit-do reword<ret>' -docstring 'reword (--amend --only --edit)'
map global magit-commit f ': magit-commit-fixup-or-squash fixup<ret>'         -docstring 'fixup (--fixup=SHA)'
map global magit-commit S ': magit-commit-fixup-or-squash squash<ret>'        -docstring 'squash (--squash=SHA)'
map global magit-commit F ': magit-commit-fixup-or-squash instant-fixup<ret>' -docstring 'instant fixup (fixup + autosquash rebase)'
map global magit-commit I ': magit-commit-fixup-or-squash instant-squash<ret>' -docstring 'instant squash (squash + autosquash rebase)'

define-command -hidden magit-commit-do -params 1 %{
    evaluate-commands %sh{
        args=$kak_opt_magit_commit_args
        needs_editor=yes
        case "$1" in
            commit) ;;
            amend)  args="$args --amend" ;;
            extend) args="$args --amend --no-edit"; needs_editor=no ;;
            reword) args="$args --amend --only" ;;
        esac

        # Non-editing path (extend): run git directly, no COMMIT_EDITMSG
        # buffer. Must cd to worktree root explicitly — the shell's cwd
        # when `%sh{}` fires is kak's client cwd, which may be anywhere.
        if [ "$needs_editor" = "no" ]; then
            toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
            if [ -z "$toplevel" ]; then
                echo "fail 'magit-commit-do: not in a git worktree'"
                exit
            fi
            if ( cd "$toplevel" && git commit $args >/dev/null 2>&1 ); then
                printf 'echo -markup %%{{Information}commit %s succeeded}\n' "$1"
            else
                printf 'fail %%{magit-commit-do %s: git commit failed (see debug)}\n' "$1"
            fi
            printf 'set-option global magit_commit_args ""\n'
            printf 'magit-commit-modeline-update\n'
            printf 'magit-refresh-after-mutation\n'
            exit
        fi

        # Editing path: open an empty COMMIT_EDITMSG, register a write hook
        # that runs the commit with that message, then delete the buffer.
        # We own the whole flow here — no dependency on git.kak's commit()
        # function, which has cwd assumptions that don't hold when called
        # from an arbitrary client context.
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
        gitdir=$(git rev-parse --git-dir 2>/dev/null)
        if [ -z "$toplevel" ] || [ -z "$gitdir" ]; then
            echo "fail 'magit-commit-do: not in a git worktree'"
            exit
        fi
        # Make gitdir absolute if it's relative.
        case "$gitdir" in
            /*) ;;
            *) gitdir="$toplevel/$gitdir" ;;
        esac
        msgfile="$gitdir/COMMIT_EDITMSG"
        # Pre-populate the message file with the default template (branch
        # info, untracked, etc.) by running `git commit` with no editor
        # — it will write COMMIT_EDITMSG and exit non-zero.
        ( cd "$toplevel" && GIT_EDITOR=true EDITOR=true git commit $args >/dev/null 2>&1 )

        # Escape single-quotes in paths for kak single-quoted strings.
        esc_msgfile=$(printf '%s' "$msgfile" | sed "s/'/''/g")
        esc_toplevel=$(printf '%s' "$toplevel" | sed "s/'/''/g")
        esc_args=$(printf '%s' "$args" | sed "s/'/''/g")

        # Emit:
        #  - edit the COMMIT_EDITMSG file
        #  - install a one-shot BufWritePost hook that cd's to toplevel and
        #    runs the commit
        printf "edit '%s'\n" "$esc_msgfile"
        printf "hook -group magit-commit buffer BufWritePost '.*COMMIT_EDITMSG' %%{\n"
        printf "    evaluate-commands %%sh%s\n" "$(printf '\173')"
        printf "        if ( cd '%s' && git commit -F '%s' --cleanup=strip %s >/dev/null 2>&1 ); then\n" \
            "$esc_toplevel" "$esc_msgfile" "$esc_args"
        printf "            printf 'echo -markup %%%%%s{Information}commit succeeded%%%%%s; delete-buffer; magit-refresh-after-mutation\\\\n' '%s' '%s'\n" \
            "$(printf '\173')" "$(printf '\175')" "$(printf '\173')" "$(printf '\175')"
        printf "        else\n"
        printf "            echo 'fail magit-commit: git commit failed'\n"
        printf "        fi\n"
        printf "    %s\n" "$(printf '\175')"
        printf "}\n"

        # Clear accumulated flags + wipe modeline marker. No need for `info`
        # — the user-mode auto-expires after one key (we don't use -lock),
        # so the autoinfo popup dismisses naturally.
        printf 'set-option global magit_commit_args ""\n'
        printf 'magit-commit-modeline-update\n'
    }
}


# --- Fixup / squash / instant-fixup / instant-squash -------------------
# Entry command: resolves target SHA either from *magit-log* cursor line
# (via magit_log_shas) or by prompting, then calls the apply helper.
#
# `verb` is one of: fixup, squash, instant-fixup, instant-squash.
define-command -hidden -params 1 magit-commit-fixup-or-squash %{
    evaluate-commands %sh{
        verb=$1
        case "$verb" in
            fixup|squash|instant-fixup|instant-squash) ;;
            *)
                printf "fail 'magit-commit-fixup-or-squash: unknown verb: %s'\n" "$verb"
                exit
                ;;
        esac
        # If we're in *magit-log*, read the SHA at the cursor line.
        # Use $kak_bufname not $kak_buffile: scratch buffers have no file
        # on disk, so buffile is empty while bufname carries the scratch
        # name ("*magit-log*").
        case "$kak_bufname" in
            \*magit-log\*)
                idx=$kak_cursor_line
                eval "set -- $kak_quoted_opt_magit_log_shas"
                if [ "$idx" -le "$#" ] && [ "$idx" -ge 1 ]; then
                    eval "sha=\${$idx}"
                    if [ -n "$sha" ]; then
                        printf "magit-commit-fixup-or-squash-apply %s '%s'\n" "$verb" "$sha"
                        exit
                    fi
                fi
                ;;
        esac
        # Otherwise prompt. The filled-in text comes back via %val{text}.
        printf "prompt '%s target: ' %%{ magit-commit-fixup-or-squash-apply %s %%val{text} }\n" \
            "$verb" "$verb"
    }
}

# Apply helper: runs git commit --fixup/--squash, optionally chases with
# `git rebase -i --autosquash <sha>^`. Both paths use GIT_EDITOR=true to
# auto-accept default messages; squash-with-editing is a future addition.
define-command -hidden -params 2 magit-commit-fixup-or-squash-apply %{
    evaluate-commands %sh{
        verb=$1
        sha=$2
        if [ -z "$sha" ]; then
            echo "fail 'magit-commit-fixup-or-squash: empty target'"
            exit
        fi
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
        if [ -z "$toplevel" ]; then
            echo "fail 'magit-commit-fixup-or-squash: not in a git worktree'"
            exit
        fi
        # Validate the target commit exists.
        if ! ( cd "$toplevel" && git rev-parse --verify "$sha^{commit}" ) >/dev/null 2>&1; then
            printf "fail 'magit-commit-fixup-or-squash: unknown commit: %s'\n" "$sha"
            exit
        fi
        # Map verb → --fixup= or --squash= flag for the initial commit.
        case "$verb" in
            fixup|instant-fixup)   commit_flag="--fixup=$sha" ;;
            squash|instant-squash) commit_flag="--squash=$sha" ;;
        esac

        # Pre-check: fixup/squash need something staged. `git commit` with
        # no staged changes exits non-zero but writes the "no changes
        # added" message to STDOUT, not stderr — our stderr-capture leaves
        # $err empty and the fallback reason ("git commit <flag> failed")
        # is unhelpful. Check index cleanliness up front and give a clear
        # error pointing at the real problem.
        if ( cd "$toplevel" && git diff --cached --quiet ) 2>/dev/null; then
            printf "fail '%s: nothing staged — stage changes first (s in magit-status)'\n" "$verb"
            exit
        fi

        args=$kak_opt_magit_commit_args
        err=$(mktemp "${TMPDIR:-/tmp}/magit-fs-err.XXXXXX")
        out=$(mktemp "${TMPDIR:-/tmp}/magit-fs-out.XXXXXX")
        # Use GIT_EDITOR=true so --squash's default message is accepted
        # without popping an editor. --fixup never opens an editor.
        # Capture stdout too (git writes some failure messages there, e.g.
        # "no changes added to commit") so we have a real reason to show
        # when stderr is empty.
        if ! ( cd "$toplevel" && GIT_EDITOR=true EDITOR=true \
                git commit $commit_flag $args >"$out" 2>"$err" ); then
            reason=$(grep -vE '^[[:space:]]*$' "$err" | head -1 | sed 's/^[[:space:]]*//' | tr -d "'\"")
            [ -z "$reason" ] && reason=$(grep -vE '^[[:space:]]*$' "$out" | head -1 | sed 's/^[[:space:]]*//' | tr -d "'\"")
            [ -z "$reason" ] && reason="git commit $commit_flag failed"
            rm -f "$err" "$out"
            printf "fail '%s: %s'\n" "$verb" "$reason"
            exit
        fi
        rm -f "$err" "$out"

        # Instant variants: chase with autosquash rebase onto sha^. If the
        # target is a root commit, `<sha>^` has no parent — use --root.
        # --autostash: if the worktree has unstaged edits, git stashes
        # them, runs the rebase, and pops the stash back. Without this,
        # rebase refuses with "cannot rebase: You have unstaged changes"
        # and leaves the fixup commit dangling at HEAD. Magit-emacs
        # uses --autostash for the same reason. On autostash-pop merge
        # conflict, git stops with clear instructions — user's recourse.
        case "$verb" in
            instant-fixup|instant-squash)
                # Stale rebase-merge/apply from a prior run → abort first.
                if [ -d "$toplevel/.git/rebase-merge" ] || [ -d "$toplevel/.git/rebase-apply" ]; then
                    ( cd "$toplevel" && git rebase --abort >/dev/null 2>&1 ) || true
                fi
                if ( cd "$toplevel" && git rev-parse --verify "$sha^" ) >/dev/null 2>&1; then
                    rb_base="$sha^"
                    use_root=
                else
                    rb_base=
                    use_root=--root
                fi
                err=$(mktemp "${TMPDIR:-/tmp}/magit-fs-rb.XXXXXX")
                out=$(mktemp "${TMPDIR:-/tmp}/magit-fs-rb-out.XXXXXX")
                # Capture stdout too — git writes the CONFLICT line there,
                # not stderr. Normalize CR (git uses \r for progress bars)
                # to \n before parsing, otherwise "Rebasing (1/4)\rerror:..."
                # looks like one line to head -1.
                if ! ( cd "$toplevel" && \
                        GIT_SEQUENCE_EDITOR=true GIT_EDITOR=true EDITOR=true \
                        git rebase -i --autosquash --autostash $use_root $rb_base >"$out" 2>"$err" ); then
                    both=$(mktemp "${TMPDIR:-/tmp}/magit-fs-rb-all.XXXXXX")
                    { tr '\r' '\n' < "$out"; tr '\r' '\n' < "$err"; } > "$both"
                    # Priority order: CONFLICT > error: > fatal: > first
                    # non-progress non-hint line > generic template.
                    reason=$(grep -E '^CONFLICT' "$both" | head -1 | sed 's/^[[:space:]]*//' | tr -d "'\"")
                    [ -z "$reason" ] && reason=$(grep -E '^(error|fatal):' "$both" | head -1 | sed 's/^[[:space:]]*//' | tr -d "'\"")
                    [ -z "$reason" ] && reason=$(grep -vE '^(Rebasing |hint:|Created autostash|Applied autostash|HEAD is now |[[:space:]]*$)' "$both" | head -1 | sed 's/^[[:space:]]*//' | tr -d "'\"")
                    [ -z "$reason" ] && reason="autosquash rebase failed"
                    rm -f "$both"
                    # Order matters: abort FIRST (pops autostash, clears
                    # .git/rebase-merge/), THEN soft-reset to remove the
                    # just-created fixup commit. Soft-reset keeps the staged
                    # changes in the index so the user can retry or redirect.
                    ( cd "$toplevel" && git rebase --abort >/dev/null 2>&1 ) || true
                    ( cd "$toplevel" && git reset --soft HEAD~1 >/dev/null 2>&1 ) || true
                    rm -f "$err" "$out"
                    printf "fail '%s: %s — rolled back (staged changes preserved)'\n" "$verb" "$reason"
                    exit
                fi
                rm -f "$err" "$out"
                ;;
        esac

        printf 'echo -markup %%{{Information}%s on %s succeeded}\n' "$verb" "$sha"
        printf 'set-option global magit_commit_args ""\n'
        printf 'magit-commit-modeline-update\n'
        printf 'magit-refresh-after-mutation\n'
    }
}


# --- gitcommit buffer bindings (REQ-10) -------------------------------
# Layer buffer-local bindings on top of the existing tree-sitter-backed
# `gitcommit` filetype (wired in autoload/filetypes/detection.kak:133).
#
# Note: kak's `map` takes exactly one key — multi-key chords like `<c-c><c-s>`
# fail with "only a single key can be mapped". We use single-key shortcuts
# in the commit-mode user-mode instead (declared below); the user enters
# that mode with `\` (local leader) while in the commit buffer.
declare-user-mode magit-commit-msg
map global magit-commit-msg s ': magit-insert-signed-off-by<ret>' -docstring 'insert Signed-off-by trailer'
# d diff-preview disabled until magit-git.kak provides :magit-diff-staged.

hook global WinSetOption filetype=git-commit %{
    map buffer normal '\' ': enter-user-mode magit-commit-msg<ret>' -docstring 'magit-commit helpers'
    hook -once -always window WinSetOption filetype=.* %{
        unmap buffer normal '\'
    }
}

define-command -hidden magit-insert-signed-off-by %{
    evaluate-commands %sh{
        name=$(git config user.name 2>/dev/null || true)
        mail=$(git config user.email 2>/dev/null || true)
        if [ -n "$name" ] && [ -n "$mail" ]; then
            OB=$(printf '\173')
            CB=$(printf '\175')
            # Go to buffer end (ge), open a newline after (o), insert trailer,
            # exit to normal mode.
            # Keys must be emitted as a single execute-keys call.
            printf 'execute-keys geo<ret>Signed-off-by: %s <lt>%s<gt><esc>' "$name" "$mail"
        else
            echo "echo -markup %{Error}git user.name/email not set%{Default}"
        fi
    }
}


}
