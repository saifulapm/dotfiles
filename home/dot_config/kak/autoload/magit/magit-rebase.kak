# magit-rebase.kak — interactive rebase UX with reword/edit support.
#
# Two flows:
#   A. Pure pick/squash/fixup/drop todo — one-shot synchronous rebase using
#      GIT_SEQUENCE_EDITOR=cp-shim. Same path as the MVP.
#   B. Todo contains `reword` and/or `edit` — collect all reword messages
#      in ONE kak buffer first, then run rebase with a GIT_EDITOR queue-shim
#      that pops the next pre-written message per invocation. `edit` verbs
#      naturally pause rebase; user uses `magit-rebase-continue` to resume.
#
# Design principle (Lesson 33 extended): zero async IPC, zero background
# processes. All editor interaction happens up-front, in sequence; git's
# editor hooks are satisfied by file-queue shims that already have the
# answers on disk.

provide-module magit-rebase %{

declare-option -hidden str magit_rebase_base ''
declare-option -hidden str magit_rebase_todo ''
declare-option -hidden str magit_rebase_msgbuf ''
declare-option -hidden str magit_rebase_msgqueue ''

define-command magit-rebase-interactive -docstring 'Interactive rebase (prompt for base)' %{
    prompt 'rebase interactively onto: ' magit-rebase-interactive-apply
}

define-command -hidden magit-rebase-interactive-apply %{
    evaluate-commands %sh{
        base=$kak_text
        if [ -z "$base" ]; then
            echo "fail 'magit-rebase-interactive: empty base'"
            exit
        fi
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
        if [ -z "$toplevel" ]; then
            echo "fail 'not in a git worktree'"
            exit
        fi
        if ! ( cd "$toplevel" && git rev-parse --verify "$base" ) >/dev/null 2>&1; then
            printf "fail 'magit-rebase: unknown ref: %s'\n" "$base"
            exit
        fi
        # Refuse up-front if the worktree has unresolved merge state.
        # --autostash would fail with `fatal: Cannot autostash` because
        # stashing unmerged index entries corrupts them. Detect via
        # `git ls-files -u` (unmerged index entries) or MERGE_HEAD
        # (live merge). NOTE: `.git/AUTO_MERGE` is NOT a reliable signal
        # — git writes it during merge-ort but doesn't clean it up on
        # completion/abort, so it lingers as a harmless stale artifact.
        gitdir=$(cd "$toplevel" && git rev-parse --git-dir 2>/dev/null)
        case "$gitdir" in /*) ;; *) gitdir="$toplevel/$gitdir" ;; esac
        unmerged=$(cd "$toplevel" && git ls-files -u 2>/dev/null | head -1)
        if [ -n "$unmerged" ] || [ -f "$gitdir/MERGE_HEAD" ]; then
            echo "fail 'magit-rebase: unresolved merge/conflict state — resolve or run :git merge --abort first'"
            exit
        fi
        # Clean up stale AUTO_MERGE left by a previously-completed merge —
        # harmless but confusing if the user inspects .git/.
        rm -f "$gitdir/AUTO_MERGE" 2>/dev/null || true
        # Clear any stale rebase-merge/rebase-apply state from a prior run.
        if [ -d "$gitdir/rebase-merge" ] || [ -d "$gitdir/rebase-apply" ]; then
            ( cd "$toplevel" && git rebase --abort >/dev/null 2>&1 ) || true
        fi
        todo=$(mktemp "${TMPDIR:-/tmp}/magit-rebase-todo.XXXXXX")
        ( cd "$toplevel" && git log --reverse --pretty='pick %h %s' "$base..HEAD" ) > "$todo"
        if [ ! -s "$todo" ]; then
            rm -f "$todo"
            printf "fail 'magit-rebase: no commits between %s and HEAD'\n" "$base"
            exit
        fi
        printf "set-option global magit_rebase_base '%s'\n" "$base"
        printf "set-option global magit_rebase_todo '%s'\n" "$todo"
        printf "edit '%s'\n" "$todo"
        printf "set-option buffer filetype git-rebase\n"
        printf "echo edit todo then press Enter to run (Q to cancel)\n"
    }
}

# Finish: write the edited todo, decide whether to batch reword messages.
define-command magit-rebase-interactive-finish -docstring 'run the rebase with edited todo' %{
    write
    evaluate-commands %sh{
        base=$kak_opt_magit_rebase_base
        todo=$kak_opt_magit_rebase_todo
        if [ -z "$base" ] || [ -z "$todo" ] || [ ! -f "$todo" ]; then
            echo "fail 'magit-rebase: no pending interactive rebase'"
            exit
        fi
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
        [ -z "$toplevel" ] && { echo "fail 'not in a git worktree'"; exit; }

        # First non-comment verb can't be squash/fixup.
        first_verb=$(grep -vE '^[[:space:]]*(#|$)' "$todo" | head -1 | awk '{print $1}')
        case "$first_verb" in
            squash|s|fixup|f)
                echo "fail 'magit-rebase: the first commit in the todo cannot be squash or fixup (nothing to meld into)'"
                exit
                ;;
        esac

        # Collect reword SHAs (in todo order). These are the commits whose
        # messages the user wants to edit; we batch them in one buffer below.
        reword_shas=$(awk '/^(reword|r)[[:space:]]/ { print $2 }' "$todo")

        if [ -z "$reword_shas" ]; then
            # Fast path: no rewords. Run rebase directly. `edit` verbs still
            # pause the rebase — user uses magit-rebase-continue afterward.
            echo 'magit-rebase-run-sync'
            exit
        fi

        # Reword path: build a combined message buffer with one section per
        # reword SHA. Format:
        #   # === reword <sha> <subject-preview> (message below; save to continue) ===
        #   <current commit subject>
        #   <blank or body lines>
        #   # === reword <sha> ... ===
        #   ...
        # The `# === ... ===` lines are our delimiters; git's --cleanup=strip
        # removes all `#`-leading lines so they never leak into commits.
        msgbuf=$(mktemp "${TMPDIR:-/tmp}/magit-rebase-reword.XXXXXX")
        queue=$(mktemp -d "${TMPDIR:-/tmp}/magit-rebase-queue.XXXXXX")
        {
            printf '# === Reword %s commit(s). Edit messages below. Save (:w) to run rebase. Q to abort. ===\n' "$(printf '%s\n' "$reword_shas" | wc -l | tr -d ' ')"
            printf '# === Delimiter lines (===) separate commits — do not remove them. ===\n'
            printf '\n'
            idx=1
            for sha in $reword_shas; do
                subj=$(cd "$toplevel" && git log -1 --format='%s' "$sha" 2>/dev/null)
                body=$(cd "$toplevel" && git log -1 --format='%B' "$sha" 2>/dev/null)
                # Delimiter carries the SHA so we can split back per-commit.
                printf '# === reword %s: %s ===\n' "$sha" "$subj"
                printf '%s\n' "$body"
                idx=$((idx + 1))
            done
        } > "$msgbuf"

        esc_msgbuf=$(printf '%s' "$msgbuf" | sed "s/'/''/g")
        printf "set-option global magit_rebase_msgbuf '%s'\n" "$esc_msgbuf"
        printf "set-option global magit_rebase_msgqueue '%s'\n" "$queue"
        # Close the todo buffer now — the user moves on to the message buffer.
        printf "try %%{ delete-buffer! '%s' }\n" "$(printf '%s' "$todo" | sed "s/'/''/g")"
        printf "edit '%s'\n" "$esc_msgbuf"
        printf "set-option buffer filetype git-commit\n"
        # Buffer-local finish / abort bindings on the message buffer.
        printf "hook -group magit-rebase-reword buffer BufWritePost '.*' magit-rebase-reword-apply\n"
        printf "map buffer normal Q ': magit-rebase-interactive-abort<ret>' -docstring 'abort rebase'\n"
        printf "echo edit messages then save (:w) to run rebase, Q to abort\n"
    }
}

# Fast path: no rewords. Runs rebase using the todo-shim only.
# `edit` verbs pause rebase naturally; we detect that and surface it.
define-command -hidden magit-rebase-run-sync %{
    evaluate-commands %sh{
        base=$kak_opt_magit_rebase_base
        todo=$kak_opt_magit_rebase_todo
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null)

        shim=$(mktemp "${TMPDIR:-/tmp}/magit-rebase-shim.XXXXXX")
        cat > "$shim" <<SHIM
#!/bin/sh
cp '$todo' "\$1"
SHIM
        chmod +x "$shim"

        err=$(mktemp "${TMPDIR:-/tmp}/magit-rebase-err.XXXXXX")
        out=$(mktemp "${TMPDIR:-/tmp}/magit-rebase-out.XXXXXX")
        # --autostash: git rebase refuses on a dirty worktree. Magit-emacs
        # also uses --autostash here. Preserves unstaged edits across the
        # rebase and re-applies them after (or on --abort). Staged changes
        # are also included in the autostash, so no work is lost.
        ( cd "$toplevel" && GIT_SEQUENCE_EDITOR="$shim" GIT_EDITOR=true \
                git rebase -i --autostash "$base" >"$out" 2>"$err" )
        rc=$?
        rm -f "$shim"

        gitdir=$(cd "$toplevel" && git rev-parse --git-dir 2>/dev/null)
        case "$gitdir" in /*) ;; *) gitdir="$toplevel/$gitdir" ;; esac

        if [ $rc -eq 0 ]; then
            if [ -d "$gitdir/rebase-merge" ] || [ -d "$gitdir/rebase-apply" ]; then
                # `edit` verb paused the rebase. Git exits 0 on an edit stop.
                printf "echo -markup %%{{Information}rebase paused — use <space>g r c to continue (or <space>g r Q to abort)}\n"
            else
                printf "echo rebase onto %s done\n" "$base"
            fi
            rm -f "$err" "$out"
        else
            # Normalize CR progress and concat streams (Lesson 46).
            both=$(mktemp "${TMPDIR:-/tmp}/magit-rebase-both.XXXXXX")
            { tr '\r' '\n' < "$out"; tr '\r' '\n' < "$err"; } > "$both"
            reason=$(grep -E '^CONFLICT' "$both" | head -1)
            [ -z "$reason" ] && reason=$(grep -E '^(error|fatal):' "$both" | head -1 | sed 's/^[[:space:]]*//')
            [ -z "$reason" ] && reason=$(head -1 "$both")
            [ -z "$reason" ] && reason="git rebase exited non-zero"
            reason=$(printf '%s' "$reason" | tr -d "'\"")
            rm -f "$err" "$out" "$both"

            if [ -d "$gitdir/rebase-merge" ] || [ -d "$gitdir/rebase-apply" ]; then
                # Conflict mid-rebase. Leave rebase-merge for the user to fix
                # and continue — do NOT auto-abort. Surface the sha in conflict.
                printf "fail 'rebase paused at conflict: %s — fix then <space>g r c, or <space>g r Q to abort'\n" "$reason"
            else
                printf "fail 'rebase failed: %s'\n" "$reason"
            fi
        fi

        # Close the todo buffer if still present (error fast-path).
        if [ -n "$todo" ] && [ -f "$todo" ]; then
            esc_todo=$(printf '%s' "$todo" | sed "s/'/''/g")
            printf "try %%{ delete-buffer! '%s' }\n" "$esc_todo"
            rm -f "$todo"
        fi
        printf "set-option global magit_rebase_base ''\n"
        printf "set-option global magit_rebase_todo ''\n"
        printf 'magit-refresh-after-mutation\n'
    }
}

# Reword-path continuation: BufWritePost on the reword message buffer fires
# this. Split the buffer back into per-SHA message files, then run rebase
# with a queue-editor shim that pops the next file per GIT_EDITOR call.
define-command -hidden magit-rebase-reword-apply %{
    evaluate-commands %sh{
        base=$kak_opt_magit_rebase_base
        todo=$kak_opt_magit_rebase_todo
        msgbuf=$kak_opt_magit_rebase_msgbuf
        queue=$kak_opt_magit_rebase_msgqueue
        if [ -z "$base" ] || [ -z "$todo" ] || [ ! -f "$todo" ] || [ -z "$msgbuf" ] || [ ! -f "$msgbuf" ] || [ -z "$queue" ] || [ ! -d "$queue" ]; then
            echo "fail 'magit-rebase-reword-apply: state missing'"
            exit
        fi
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
        [ -z "$toplevel" ] && { echo "fail 'not in a git worktree'"; exit; }

        # Split msgbuf on `# === reword <sha>: ... ===` lines. Per section:
        # drop the delimiter line (and the HEADER/instruction lines at top),
        # keep everything until the next delimiter. Write to $queue/NN.msg
        # in todo order (00, 01, ...).
        #
        # Using awk rather than shell pipes because we want index-by-order
        # output without mktemp-per-line overhead.
        awk -v dir="$queue" '
            BEGIN { idx = -1 }
            /^# === reword / {
                idx++
                # Fresh output file per section. Zero-pad index for lexical
                # sort — though we only iterate by counter so sorting is
                # actually not needed; keep it for humans inspecting the dir.
                file = sprintf("%s/%02d.msg", dir, idx)
                next
            }
            /^# === / { next }   # header/instruction delimiter lines
            idx >= 0 {
                print > file
            }
        ' "$msgbuf"

        # Count written messages; must equal number of reword-verbs in todo.
        reword_count=$(awk '/^(reword|r)[[:space:]]/ { c++ } END { print c+0 }' "$todo")
        queue_count=$(ls "$queue" 2>/dev/null | wc -l | tr -d ' ')
        if [ "$reword_count" != "$queue_count" ]; then
            printf "fail 'magit-rebase-reword-apply: expected %s message sections, got %s (preserve the === delimiter lines)'\n" "$reword_count" "$queue_count"
            exit
        fi

        # Todo shim: dump our todo into git's sequence file.
        todo_shim=$(mktemp "${TMPDIR:-/tmp}/magit-rebase-todo-shim.XXXXXX")
        cat > "$todo_shim" <<SHIM
#!/bin/sh
cp '$todo' "\$1"
SHIM
        chmod +x "$todo_shim"

        # Editor shim: each invocation reads $queue/.counter (default 0),
        # copies $queue/NN.msg over the path git hands us, increments the
        # counter. Robust against `edit` verbs: those invoke GIT_EDITOR with
        # a different filename (rebase-merge/COMMIT_EDITMSG is used for both
        # reword AND edit's amend). However the queue ONLY feeds reword
        # messages — edit-verb messages come from HEAD via --no-edit on the
        # user's subsequent `git commit --amend` / `rebase --continue`.
        #
        # To distinguish: when git invokes GIT_EDITOR for a `reword`, the
        # sequencer state file `rebase-merge/message` is pre-populated with
        # the commit's existing message. For `edit`, the sequencer does NOT
        # invoke GIT_EDITOR at all during replay — it just stops. So every
        # GIT_EDITOR call during rebase is a reword, and the queue order
        # matches todo order. This is a stable git-internals fact.
        editor_shim=$(mktemp "${TMPDIR:-/tmp}/magit-rebase-editor-shim.XXXXXX")
        cat > "$editor_shim" <<SHIM
#!/bin/sh
# Queue-pop editor: read next message from \$queue and write to \$1.
counter_file='$queue/.counter'
if [ -f "\$counter_file" ]; then
    n=\$(cat "\$counter_file")
else
    n=0
fi
msg=\$(printf '%s/%02d.msg' '$queue' "\$n")
if [ -f "\$msg" ]; then
    cp "\$msg" "\$1"
fi
echo \$((n + 1)) > "\$counter_file"
SHIM
        chmod +x "$editor_shim"

        err=$(mktemp "${TMPDIR:-/tmp}/magit-rebase-err.XXXXXX")
        out=$(mktemp "${TMPDIR:-/tmp}/magit-rebase-out.XXXXXX")
        ( cd "$toplevel" && \
            GIT_SEQUENCE_EDITOR="$todo_shim" \
            GIT_EDITOR="$editor_shim" \
            git rebase -i --autostash "$base" >"$out" 2>"$err" )
        rc=$?
        rm -f "$todo_shim" "$editor_shim"

        gitdir=$(cd "$toplevel" && git rev-parse --git-dir 2>/dev/null)
        case "$gitdir" in /*) ;; *) gitdir="$toplevel/$gitdir" ;; esac

        # Cleanup the reword buffer + state (always, success or failure
        # — paused or done). The queue dir stays until rebase ends if we
        # paused on an edit; otherwise remove it now.
        esc_msgbuf=$(printf '%s' "$msgbuf" | sed "s/'/''/g")
        esc_todo=$(printf '%s' "$todo" | sed "s/'/''/g")
        printf "try %%{ delete-buffer! '%s' }\n" "$esc_msgbuf"
        printf "try %%{ delete-buffer! '%s' }\n" "$esc_todo"
        rm -f "$msgbuf" "$todo"

        paused=0
        if [ -d "$gitdir/rebase-merge" ] || [ -d "$gitdir/rebase-apply" ]; then
            paused=1
        fi

        if [ $rc -eq 0 ]; then
            if [ $paused -eq 1 ]; then
                printf "echo -markup %%{{Information}rebase paused — use <space>g r c to continue (or <space>g r Q to abort)}\n"
            else
                printf "echo rebase onto %s done\n" "$base"
                rm -rf "$queue"
            fi
            rm -f "$err" "$out"
        else
            both=$(mktemp "${TMPDIR:-/tmp}/magit-rebase-both.XXXXXX")
            { tr '\r' '\n' < "$out"; tr '\r' '\n' < "$err"; } > "$both"
            reason=$(grep -E '^CONFLICT' "$both" | head -1)
            [ -z "$reason" ] && reason=$(grep -E '^(error|fatal):' "$both" | head -1 | sed 's/^[[:space:]]*//')
            [ -z "$reason" ] && reason=$(head -1 "$both")
            [ -z "$reason" ] && reason="git rebase exited non-zero"
            reason=$(printf '%s' "$reason" | tr -d "'\"")
            rm -f "$err" "$out" "$both"

            if [ $paused -eq 1 ]; then
                printf "fail 'rebase paused at conflict: %s — fix then <space>g r c, or <space>g r Q to abort'\n" "$reason"
            else
                printf "fail 'rebase failed: %s'\n" "$reason"
                rm -rf "$queue"
            fi
        fi

        printf "set-option global magit_rebase_base ''\n"
        printf "set-option global magit_rebase_todo ''\n"
        printf "set-option global magit_rebase_msgbuf ''\n"
        # Keep msgqueue option live iff paused — magit-rebase-continue may
        # need it (not currently; reword messages already consumed before
        # any edit-stop can occur). Clear unconditionally for now.
        printf "set-option global magit_rebase_msgqueue ''\n"
        printf 'magit-refresh-after-mutation\n'
    }
}

# Continue a paused rebase (after `edit` verb or conflict resolution).
define-command magit-rebase-continue -docstring 'Continue a paused interactive rebase' %{
    evaluate-commands %sh{
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
        [ -z "$toplevel" ] && { echo "fail 'not in a git worktree'"; exit; }
        gitdir=$(cd "$toplevel" && git rev-parse --git-dir 2>/dev/null)
        case "$gitdir" in /*) ;; *) gitdir="$toplevel/$gitdir" ;; esac
        if [ ! -d "$gitdir/rebase-merge" ] && [ ! -d "$gitdir/rebase-apply" ]; then
            echo "fail 'magit-rebase-continue: no rebase in progress'"
            exit
        fi

        err=$(mktemp "${TMPDIR:-/tmp}/magit-rebase-cont-err.XXXXXX")
        out=$(mktemp "${TMPDIR:-/tmp}/magit-rebase-cont-out.XXXXXX")
        # GIT_EDITOR=true: any remaining reword/amend editor pop-up uses
        # the existing message. Users who want to edit the edit-stop amend
        # message should use <space>g c w (reword) before --continue.
        ( cd "$toplevel" && GIT_EDITOR=true GIT_SEQUENCE_EDITOR=true \
            git rebase --continue >"$out" 2>"$err" )
        rc=$?

        if [ $rc -eq 0 ]; then
            if [ -d "$gitdir/rebase-merge" ] || [ -d "$gitdir/rebase-apply" ]; then
                printf "echo -markup %%{{Information}rebase still paused — next edit step}\n"
            else
                printf "echo rebase continued and finished\n"
            fi
            rm -f "$err" "$out"
        else
            both=$(mktemp "${TMPDIR:-/tmp}/magit-rebase-cont-both.XXXXXX")
            { tr '\r' '\n' < "$out"; tr '\r' '\n' < "$err"; } > "$both"
            reason=$(grep -E '^CONFLICT' "$both" | head -1)
            [ -z "$reason" ] && reason=$(grep -E '^(error|fatal):' "$both" | head -1 | sed 's/^[[:space:]]*//')
            [ -z "$reason" ] && reason=$(head -1 "$both")
            [ -z "$reason" ] && reason="git rebase --continue exited non-zero"
            reason=$(printf '%s' "$reason" | tr -d "'\"")
            rm -f "$err" "$out" "$both"
            printf "fail 'rebase --continue: %s'\n" "$reason"
        fi
        printf 'magit-refresh-after-mutation\n'
    }
}

# Cancel: discard the todo (or reword buffer) without rebasing. Also works
# when called post-start on a paused rebase — runs `git rebase --abort`.
define-command magit-rebase-interactive-abort -docstring 'abort interactive rebase' %{
    evaluate-commands %sh{
        todo=$kak_opt_magit_rebase_todo
        msgbuf=$kak_opt_magit_rebase_msgbuf
        queue=$kak_opt_magit_rebase_msgqueue

        # Close any pending buffers.
        if [ -n "$msgbuf" ] && [ -f "$msgbuf" ]; then
            esc_msgbuf=$(printf '%s' "$msgbuf" | sed "s/'/''/g")
            printf "try %%{ delete-buffer! '%s' }\n" "$esc_msgbuf"
            rm -f "$msgbuf"
        fi
        if [ -n "$todo" ] && [ -f "$todo" ]; then
            esc_todo=$(printf '%s' "$todo" | sed "s/'/''/g")
            printf "try %%{ delete-buffer! '%s' }\n" "$esc_todo"
            rm -f "$todo"
        fi
        [ -n "$queue" ] && [ -d "$queue" ] && rm -rf "$queue"

        # If a rebase is actually in progress, abort it.
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
        if [ -n "$toplevel" ]; then
            gitdir=$(cd "$toplevel" && git rev-parse --git-dir 2>/dev/null)
            case "$gitdir" in /*) ;; *) gitdir="$toplevel/$gitdir" ;; esac
            if [ -d "$gitdir/rebase-merge" ] || [ -d "$gitdir/rebase-apply" ]; then
                ( cd "$toplevel" && git rebase --abort >/dev/null 2>&1 ) || true
            fi
        fi

        printf "set-option global magit_rebase_base ''\n"
        printf "set-option global magit_rebase_todo ''\n"
        printf "set-option global magit_rebase_msgbuf ''\n"
        printf "set-option global magit_rebase_msgqueue ''\n"
        printf "echo rebase cancelled\n"
        printf 'magit-refresh-after-mutation\n'
    }
}

# Buffer-local verb-change: replace the first whitespace-delimited token on
# the current line with $1.
define-command -hidden -params 1 magit-rebase-verb-set %{
    execute-keys -draft "xs^\S+<ret>c%arg{1}<esc>"
}

# `?` help mode — keep in sync with the rebase-todo buffer bindings below.
declare-user-mode magit-rebase-todo-keys
map global magit-rebase-todo-keys p ': magit-rebase-verb-set pick<ret>'   -docstring 'pick'
map global magit-rebase-todo-keys r ': magit-rebase-verb-set reword<ret>' -docstring 'reword'
map global magit-rebase-todo-keys e ': magit-rebase-verb-set edit<ret>'   -docstring 'edit'
map global magit-rebase-todo-keys s ': magit-rebase-verb-set squash<ret>' -docstring 'squash'
map global magit-rebase-todo-keys f ': magit-rebase-verb-set fixup<ret>'  -docstring 'fixup'
map global magit-rebase-todo-keys d ': magit-rebase-verb-set drop<ret>'   -docstring 'drop'
map global magit-rebase-todo-keys <ret> ': magit-rebase-interactive-finish<ret>' -docstring 'run rebase'
map global magit-rebase-todo-keys Q     ': magit-rebase-interactive-abort<ret>'  -docstring 'cancel'

hook global WinSetOption filetype=git-rebase %{
    map buffer normal p ': magit-rebase-verb-set pick<ret>'    -docstring 'pick'
    map buffer normal r ': magit-rebase-verb-set reword<ret>'  -docstring 'reword'
    map buffer normal e ': magit-rebase-verb-set edit<ret>'    -docstring 'edit'
    map buffer normal s ': magit-rebase-verb-set squash<ret>'  -docstring 'squash'
    map buffer normal f ': magit-rebase-verb-set fixup<ret>'   -docstring 'fixup'
    map buffer normal d ': magit-rebase-verb-set drop<ret>'    -docstring 'drop'
    map buffer normal <ret> ': magit-rebase-interactive-finish<ret>' -docstring 'run rebase'
    map buffer normal Q     ': magit-rebase-interactive-abort<ret>'  -docstring 'cancel'
    map buffer normal '?'   ': enter-user-mode magit-rebase-todo-keys<ret>' -docstring 'show keys (help)'
    hook -once -always window WinSetOption filetype=.* %{
        unmap buffer normal p
        unmap buffer normal r
        unmap buffer normal e
        unmap buffer normal s
        unmap buffer normal f
        unmap buffer normal d
        unmap buffer normal <ret>
        unmap buffer normal Q
        unmap buffer normal '?'
    }
}

}
