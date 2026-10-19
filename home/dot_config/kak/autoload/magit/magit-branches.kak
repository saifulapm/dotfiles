# magit-branches.kak — branch buffer UX.
# Depends on magit.kak's magit-refresh-after-mutation and magit-modeline-update.

provide-module magit-branches %{

# --- Branch buffer -----------------------------------------------------
# `*magit-branches*` lists current + local + remote branches with a single
# keystroke-driven workflow: <ret> checkout, d delete (confirm), c create,
# R refresh, q quit. Rewritten from git-extra.kak.disabled's dense state
# machine into something flatter and easier to extend.

define-command magit-branch-dispatch -docstring 'Open the magit branch buffer' %{
    evaluate-commands %sh{
        if ! git rev-parse --git-dir >/dev/null 2>&1; then
            echo "fail 'magit-branch: not a git repository'"
            exit
        fi
    }
    try %{
        buffer '*magit-branches*'
    } catch %{
        edit -scratch '*magit-branches*'
    }
    # Always (re)set filetype so the filetype hook fires and re-binds the
    # mappings. Safe to re-set: add-highlighter is wrapped in `try`, map
    # redefinitions override silently.
    set-option buffer filetype magit-branches
    magit-branches-render
}

define-command -hidden magit-branches-render %{
    evaluate-commands -save-regs '/' %{
        # Capture branch name at cursor BEFORE re-render so we can restore.
        # Only overwrite register b if the caller hasn't pre-seeded it (e.g.
        # magit-branch-create-apply sets b to the new branch name so cursor
        # lands on the new entry after render).
        evaluate-commands %sh{
            if [ -z "$kak_reg_b" ]; then
                echo "try %{ magit-branch-name-at-cursor b } catch %{ set-register b '' }"
            fi
        }
        evaluate-commands %sh{
            OB=$(printf '\173'); CB=$(printf '\175')
            toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
            [ -z "$toplevel" ] && { printf "fail 'magit-branch: no toplevel'\n"; exit; }
            tmp=$(mktemp "${TMPDIR:-/tmp}/magit-branches.XXXXXX")
            current=$(cd "$toplevel" && git symbolic-ref --short HEAD 2>/dev/null || echo '')
            {
                printf '# Branches in %s\n' "$toplevel"
                printf '# <ret> checkout   d delete   c create   m rename   s spinoff   o orphan   R refresh   q quit\n'
                printf '\n'
                printf '## Local\n'
                # Unborn-orphan case: current branch has no commit yet, so
                # `for-each-ref refs/heads/` won't list it. Detect and emit
                # a synthetic row so the user sees where HEAD actually is.
                current_listed=0
                ( cd "$toplevel" && git for-each-ref --sort=-committerdate \
                    --format='%(refname:short) %(objectname:short) %(contents:subject)' \
                    refs/heads/ ) > "$tmp.heads"
                if [ -n "$current" ] && ! awk -v c="$current" '$1==c {found=1} END {exit !found}' "$tmp.heads"; then
                    printf '* %s (orphan, no commits yet)\n' "$current"
                fi
                while IFS= read -r line; do
                    name=${line%% *}
                    if [ "$name" = "$current" ]; then
                        printf '* %s\n' "$line"
                    else
                        printf '  %s\n' "$line"
                    fi
                done < "$tmp.heads"
                rm -f "$tmp.heads"
                printf '\n'
                printf '## Remote\n'
                ( cd "$toplevel" && git for-each-ref --sort=-committerdate \
                    --format='%(refname:short) %(objectname:short) %(contents:subject)' \
                    refs/remotes/ ) | sed 's/^/  /'
            } > "$tmp"
            # Strip trailing whitespace (Lesson 20).
            sed -i.bak 's/[[:space:]]*$//' "$tmp" && rm -f "$tmp.bak"
            # %|cat<ret> leaves the whole buffer selected; gh collapses the
            # selection to line start (Lesson 19-ish). We also want to avoid
            # any residual selection that would make the default `R` key
            # replace-yank on whatever is selected.
            printf "execute-keys '%%|cat %s<ret>gg<a-h>'\n" "$tmp"
            printf "nop %%sh%s rm -f '%s' %s\n" "$OB" "$tmp" "$CB"
        }
        # Restore cursor on previously-focused branch, if any.
        try %{
            evaluate-commands %sh{
                if [ -n "$kak_reg_b" ]; then
                    printf "try %%{ execute-keys '/%s<ret>' }\n" "$kak_reg_b"
                fi
            }
        }
    }
}

define-command -hidden magit-branch-name-at-cursor -params 1 %{
    # Select the current line, yank to the target register, then in %sh{}
    # parse the branch name out of the yanked text. The branch buffer has
    # 2-char prefixes ("* " or "  ") followed by the name.
    evaluate-commands -save-regs l %{
        execute-keys -draft 'gh<a-l>"ly'
        evaluate-commands %sh{
            line=$kak_reg_l
            # Strip leading "* " or "  " prefix, then take first whitespace field.
            stripped=${line#??}
            name=${stripped%% *}
            printf "set-register %s '%s'\n" "$1" "$name"
        }
    }
}

define-command magit-branch-checkout -docstring 'Checkout the branch at cursor' %{
    magit-branch-name-at-cursor c
    evaluate-commands %sh{
        name=$kak_reg_c
        if [ -z "$name" ]; then
            echo "fail 'no branch at cursor'"
            exit
        fi
        # Strip remote prefix for tracking branches (origin/foo -> foo).
        local_name=${name#*/}
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
        # Silence both stdout + stderr — git's "Switched to branch 'foo'" would
        # otherwise get re-parsed as kakscript (Lesson 28).
        if ( cd "$toplevel" && git switch "$local_name" >/dev/null 2>&1 ); then
            # Pre-seed register b so render lands cursor on the now-current
            # branch (the one we just switched to), not the previous line.
            printf "set-register b '%s'\n" "$local_name"
            printf "echo -markup '{Information}Switched to %s'\n" "$local_name"
        else
            printf "fail 'checkout failed: %s'\n" "$local_name"
        fi
    }
    magit-branches-render
}

define-command magit-branch-delete -docstring 'Delete the branch at cursor (with confirm)' %{
    magit-branch-name-at-cursor c
    evaluate-commands %sh{
        name=$kak_reg_c
        [ -z "$name" ] && { echo "fail 'no branch at cursor'"; exit; }
        case "$name" in
            */*) echo "fail 'refuse to delete remote-tracking branch'" ; exit ;;
        esac
        current=$(git symbolic-ref --short HEAD 2>/dev/null || echo '')
        [ "$name" = "$current" ] && { echo "fail 'cannot delete current branch'"; exit; }
        printf "set-option buffer magit_branch_pending_delete '%s'\n" "$name"
        printf "prompt 'Delete branch %s? (y/N): ' magit-branch-delete-apply\n" "$name"
    }
}

declare-option -hidden str magit_branch_pending_delete ''

define-command -hidden magit-branch-delete-apply %{
    evaluate-commands %sh{
        ans=$kak_text
        name=$kak_opt_magit_branch_pending_delete
        if [ "$ans" != "y" ] && [ "$ans" != "Y" ]; then
            printf "echo -markup '{Information}cancelled'\n"
            exit
        fi
        if git branch -d "$name" >/dev/null 2>&1; then
            # After delete, cursor lands on current branch (deleted row is gone).
            cur=$(git symbolic-ref --short HEAD 2>/dev/null || echo '')
            [ -n "$cur" ] && printf "set-register b '%s'\n" "$cur"
            printf "echo -markup '{Information}deleted %s'\n" "$name"
        else
            printf "fail 'delete failed (unmerged? use git branch -D)'\n"
        fi
    }
    magit-branches-render
}

define-command magit-branch-create -docstring 'Prompt for branch name; create and switch' %{
    prompt 'New branch: ' magit-branch-create-apply
}

define-command -hidden magit-branch-create-apply %{
    evaluate-commands %sh{
        name=$kak_text
        if [ -z "$name" ]; then
            echo "fail 'empty branch name'"
            exit
        fi
        if git switch -c "$name" >/dev/null 2>&1; then
            # Pre-seed register b so render restores cursor onto the new branch.
            printf "set-register b '%s'\n" "$name"
            printf "echo -markup '{Information}created and switched to %s'\n" "$name"
        else
            printf "fail 'create failed: %s'\n" "$name"
        fi
    }
    magit-branches-render
}

# --- Rename -----------------------------------------------------------
# `m` on any local branch → prompt for new name → git branch -m <old> <new>.
# If the cursor is on the CURRENT branch (or on no branch at all), we
# rename HEAD — git branch -m <new> accepts exactly one arg in that case.
# Remote-tracking branches (origin/foo) are rejected, same policy as
# delete.
define-command magit-branch-rename -docstring 'Rename the branch at cursor' %{
    magit-branch-name-at-cursor c
    evaluate-commands %sh{
        name=$kak_reg_c
        if [ -z "$name" ]; then
            echo "fail 'no branch at cursor'"; exit
        fi
        case "$name" in
            */*) echo "fail 'refuse to rename remote-tracking branch'"; exit ;;
        esac
        printf "set-option buffer magit_branch_pending_rename '%s'\n" "$name"
        printf "prompt 'Rename %s to: ' magit-branch-rename-apply\n" "$name"
    }
}

declare-option -hidden str magit_branch_pending_rename ''

define-command -hidden magit-branch-rename-apply -params ..1 %{
    # Accept the new name as a param (for tests / programmatic callers)
    # or fall back to $kak_text (the prompt path).
    evaluate-commands %sh{
        newname=${1:-$kak_text}
        newname=$(printf '%s' "$newname" | awk '{$1=$1; print}')   # trim ws
        oldname=$kak_opt_magit_branch_pending_rename
        if [ -z "$newname" ]; then
            printf "echo -markup '{Information}cancelled'\n"; exit
        fi
        current=$(git symbolic-ref --short HEAD 2>/dev/null || echo '')
        if [ "$oldname" = "$current" ]; then
            # Renaming current: git branch -m <new> — no old-name arg.
            set -- -m "$newname"
        else
            set -- -m "$oldname" "$newname"
        fi
        err=$(mktemp "${TMPDIR:-/tmp}/magit-branch-rename-err.XXXXXX")
        if git branch "$@" >/dev/null 2>"$err"; then
            printf "set-register b '%s'\n" "$newname"
            safe_new=$(printf '%s' "$newname" | tr -d "'")
            safe_old=$(printf '%s' "$oldname" | tr -d "'")
            printf "echo -markup '{Information}renamed %s -> %s'\n" "$safe_old" "$safe_new"
        else
            reason=$(head -1 "$err" | tr -d "'\"")
            printf "fail 'rename failed: %s'\n" "$reason"
        fi
        rm -f "$err"
    }
    magit-branches-render
}

# --- Spinoff ----------------------------------------------------------
# `s` creates a new branch at HEAD and resets the CURRENT branch back
# to its upstream. Use case: "I've accumulated N commits on main,
# actually they're a feature — spin off 'feature' to hold them, and
# move main back to origin/main". Requires an upstream; without one,
# we refuse with a pointed message rather than prompt for a start-point
# (keep the UX one-prompt).
define-command magit-branch-spinoff -docstring 'Spin off a new branch from HEAD, reset current to upstream' %{
    evaluate-commands %sh{
        current=$(git symbolic-ref --short HEAD 2>/dev/null || echo '')
        [ -z "$current" ] && { echo "fail 'spinoff: detached HEAD'"; exit; }
        # Check upstream exists.
        if ! git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
            echo "fail 'spinoff: $current has no upstream (set one first)'"
            exit
        fi
        # Pre-check: git switch -c would fail later on uncommitted conflicts.
        # Spinoff's `switch -c <new>` keeps the worktree, so only files that
        # differ between HEAD and the new branch tip matter — but since we
        # create at HEAD, unstaged edits are safe. HOWEVER: the SUBSEQUENT
        # `git branch -f <orig> <upstream_sha>` is a ref-move, not a
        # checkout; it also doesn't touch the worktree. So spinoff actually
        # WORKS with dirty worktree. Skip the check — unlike orphan.
        printf "set-option buffer magit_branch_pending_spinoff '%s'\n" "$current"
        echo "prompt 'Spin off into new branch: ' magit-branch-spinoff-apply"
    }
}

declare-option -hidden str magit_branch_pending_spinoff ''

define-command -hidden magit-branch-spinoff-apply -params ..1 %{
    evaluate-commands %sh{
        newname=${1:-$kak_text}
        # Trim leading/trailing whitespace. kak's prompt path can leave
        # surrounding whitespace depending on dispatch shape; git rejects
        # any branch name with leading/trailing space as invalid.
        newname=$(printf '%s' "$newname" | awk '{$1=$1; print}')
        orig=$kak_opt_magit_branch_pending_spinoff
        if [ -z "$newname" ]; then
            printf "echo -markup '{Information}cancelled'\n"; exit
        fi
        err=$(mktemp "${TMPDIR:-/tmp}/magit-branch-spinoff-err.XXXXXX")
        # Resolve upstream SHA BEFORE we switch branches — @{u} is
        # branch-scoped; the resolution must happen against $orig.
        upstream_sha=$(git rev-parse "$orig@{u}" 2>/dev/null)
        if [ -z "$upstream_sha" ]; then
            echo "fail 'spinoff: lost upstream for $orig'"
            rm -f "$err"; exit
        fi
        # 1) Create + switch to new branch (at current HEAD).
        if ! git switch -c "$newname" >/dev/null 2>"$err"; then
            reason=$(head -1 "$err" | tr -d "'\"")
            printf "fail 'spinoff: create failed: %s'\n" "$reason"
            rm -f "$err"; exit
        fi
        # 2) Reset the ORIGINAL branch (not HEAD, which is now newname)
        #    back to upstream. `git branch -f` moves a non-checked-out
        #    branch ref — safe because we already switched away.
        if ! git branch -f "$orig" "$upstream_sha" >/dev/null 2>"$err"; then
            reason=$(head -1 "$err" | tr -d "'\"")
            # Try to undo the create to leave the tree coherent.
            git switch "$orig" >/dev/null 2>&1
            git branch -D "$newname" >/dev/null 2>&1
            printf "fail 'spinoff: reset %s failed: %s — rolled back'\n" "$orig" "$reason"
            rm -f "$err"; exit
        fi
        rm -f "$err"
        printf "set-register b '%s'\n" "$newname"
        safe_new=$(printf '%s' "$newname" | tr -d "'")
        safe_orig=$(printf '%s' "$orig" | tr -d "'")
        printf "echo -markup '{Information}spun off %s from %s (reset to upstream)'\n" "$safe_new" "$safe_orig"
    }
    magit-branches-render
}

# --- Orphan -----------------------------------------------------------
# `o` prompts for a name, `git switch --orphan <name>`. Creates a
# branch with no parent commit. Rare but useful for gh-pages,
# documentation branches, vendor imports, etc.
define-command magit-branch-orphan -docstring 'Create an orphan branch (no parent)' %{
    evaluate-commands %sh{
        # Pre-check: git switch --orphan would fail later with an opaque
        # "Your local changes ... would be overwritten" if the worktree
        # has uncommitted edits (staged OR unstaged). Refuse up-front
        # with a clear message — user can stash/commit first.
        if ! git diff --quiet HEAD 2>/dev/null; then
            echo "fail 'orphan: worktree has uncommitted changes (stash or commit first)'"
            exit
        fi
        echo "prompt 'New orphan branch: ' magit-branch-orphan-apply"
    }
}

define-command -hidden magit-branch-orphan-apply -params ..1 %{
    evaluate-commands %sh{
        name=${1:-$kak_text}
        name=$(printf '%s' "$name" | awk '{$1=$1; print}')   # trim ws
        if [ -z "$name" ]; then
            printf "echo -markup '{Information}cancelled'\n"; exit
        fi
        err=$(mktemp "${TMPDIR:-/tmp}/magit-branch-orphan-err.XXXXXX")
        if git switch --orphan "$name" >/dev/null 2>"$err"; then
            printf "set-register b '%s'\n" "$name"
            safe=$(printf '%s' "$name" | tr -d "'")
            printf "echo -markup '{Information}created orphan branch %s'\n" "$safe"
        else
            reason=$(head -1 "$err" | tr -d "'\"")
            printf "fail 'orphan failed: %s'\n" "$reason"
        fi
        rm -f "$err"
    }
    magit-branches-render
}

# `?` help mode — keep in sync with the buffer bindings below.
declare-user-mode magit-branches-keys
map global magit-branches-keys <ret> ': magit-branch-checkout<ret>' -docstring 'checkout'
map global magit-branches-keys d    ': magit-branch-delete<ret>'   -docstring 'delete (confirm)'
map global magit-branches-keys c    ': magit-branch-create<ret>'   -docstring 'create'
map global magit-branches-keys m    ': magit-branch-rename<ret>'   -docstring 'rename'
map global magit-branches-keys s    ': magit-branch-spinoff<ret>'  -docstring 'spinoff (reset current to upstream)'
map global magit-branches-keys o    ': magit-branch-orphan<ret>'   -docstring 'orphan (no-parent branch)'
map global magit-branches-keys R    ': magit-branches-render<ret>' -docstring 'refresh'
map global magit-branches-keys q    ': delete-buffer *magit-branches*<ret>' -docstring 'quit'

hook global WinSetOption filetype=magit-branches %{
    add-highlighter window/magit-branches group
    add-highlighter window/magit-branches/ regex '^#.*$' 0:comment
    add-highlighter window/magit-branches/ regex '^## (Local|Remote)$' 0:header
    add-highlighter window/magit-branches/ regex '^\* \S+' 0:green
    add-highlighter window/magit-branches/ regex '^  \S+' 0:default
    map buffer normal <ret> ': magit-branch-checkout<ret>' -docstring 'checkout'
    map buffer normal d    ': magit-branch-delete<ret>'   -docstring 'delete (confirm)'
    map buffer normal c    ': magit-branch-create<ret>'   -docstring 'create'
    map buffer normal m    ': magit-branch-rename<ret>'   -docstring 'rename'
    map buffer normal s    ': magit-branch-spinoff<ret>'  -docstring 'spinoff (reset current to upstream)'
    map buffer normal o    ': magit-branch-orphan<ret>'   -docstring 'orphan (no-parent branch)'
    map buffer normal R    ': magit-branches-render<ret>' -docstring 'refresh'
    map buffer normal q    ': delete-buffer *magit-branches*<ret>' -docstring 'quit'
    map buffer normal '?'  ': enter-user-mode magit-branches-keys<ret>' -docstring 'show keys (help)'
    hook -once -always window WinSetOption filetype=.* %{
        remove-highlighter window/magit-branches
        unmap buffer normal <ret>
        unmap buffer normal d
        unmap buffer normal c
        unmap buffer normal m
        unmap buffer normal s
        unmap buffer normal o
        unmap buffer normal R
        unmap buffer normal q
        unmap buffer normal '?'
    }
}


}
