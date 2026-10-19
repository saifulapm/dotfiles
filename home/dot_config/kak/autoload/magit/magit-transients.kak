# magit-transients.kak — workflow transients (push/pull/fetch/merge/cherry/revert/rebase)
# and the generic `magit-transient-*` framework they use.
# Depends on magit.kak's magit-modeline-update and magit-transient-toggle.

provide-module magit-transients %{

# --- Generic transient framework ---------------------------------------
# 8 transients share the same shape. These primitives let each one be
# declared in ~8 lines instead of ~80. push + commit stay bespoke (editor
# paths + set-upstream semantics not yet worth abstracting).
#
# Primitives (all are kak-level commands that emit kakscript at load time):
#
#   magit-transient-mode NAME
#       Declare `magit_NAME_args` option, `magit-NAME` user-mode, and the
#       `magit-NAME-dispatch` entry command.
#
#   magit-transient-flag NAME KEY FLAG
#       Map KEY in magit-NAME to toggle FLAG in magit_NAME_args,
#       refresh modeline, re-enter mode.
#
#   magit-transient-run NAME KEY GITCMD LABEL EXTRA_ARGS
#       Map KEY in magit-NAME to: run
#       `git GITCMD <accumulated flags> EXTRA_ARGS` reporting under LABEL.
#       On success echoes `<GITCMD> <LABEL>`; on failure surfaces stderr.
#       Afterwards: clears args-opt, refreshes modeline + status.
#
#   magit-transient-subcmd NAME KEY GITCMD SUBARG MSG
#       Map KEY to: run `git GITCMD SUBARG` (ignores accumulated flags —
#       used for abort/continue/skip). Reports MSG on success.
#
#   magit-transient-prompt NAME KEY GITCMD PROMPT_MSG LABEL
#       Map KEY to: prompt user for text, run
#       `git GITCMD <accumulated flags> <user_text>` reporting under LABEL.
#
# Shared runtime helpers (called from the generated maps):
#
#   magit-transient-run-and-report OPT LABEL GITCMD [EXTRA...]
#       Runs git, captures stderr, emits toast/fail, clears OPT, refreshes.
#
#   magit-transient-subcmd-run GITCMD SUBARG MSG
#       Runs `git GITCMD SUBARG` (no flags), reports MSG/fail, refreshes.

define-command -hidden -params 3.. magit-transient-run-and-report %{
    evaluate-commands %sh{
        opt=$1
        label=$2
        gitcmd=$3
        shift 3
        # Remaining $@ are extra git args (literal).
        args=$(eval printf '%s ' "\$kak_opt_${opt}")
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
        if [ -z "$toplevel" ]; then
            echo "fail 'magit-transient: not in a git worktree'"
            exit
        fi
        err=$(mktemp "${TMPDIR:-/tmp}/magit-transient-err.XXXXXX")
        # Silence any editor git might spawn so we never hit the tty-not-a-
        # terminal vim error inside a headless kak %sh{}.
        if ( cd "$toplevel" && GIT_EDITOR=true GIT_SEQUENCE_EDITOR=true \
                git "$gitcmd" $args "$@" >/dev/null 2>"$err" ); then
            printf 'echo -markup %%{{Information}%s %s}\n' "$gitcmd" "$label"
            rm -f "$err"
        else
            reason=$(grep -E '^(error|fatal|CONFLICT):|^ !' "$err" | head -1 | sed 's/^[[:space:]]*//')
            [ -z "$reason" ] && reason=$(head -1 "$err")
            [ -z "$reason" ] && reason="git $gitcmd exited non-zero"
            reason=$(printf '%s' "$reason" | tr -d "'")
            printf "fail '%s %s failed: %s'\n" "$gitcmd" "$label" "$reason"
            rm -f "$err"
        fi
        printf 'set-option global %s ""\n' "$opt"
        printf 'magit-modeline-update\n'
        printf 'magit-refresh-after-mutation\n'
    }
}

define-command -hidden -params 3 magit-transient-subcmd-run %{
    evaluate-commands %sh{
        gitcmd=$1
        subarg=$2
        msg=$3
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
        if [ -z "$toplevel" ]; then
            echo "fail 'magit-transient: not in a git worktree'"
            exit
        fi
        err=$(mktemp "${TMPDIR:-/tmp}/magit-transient-err.XXXXXX")
        # Silence any editor git might spawn (e.g. rebase --continue opens an
        # editor for the merge-commit message). GIT_EDITOR=true no-ops it.
        if ( cd "$toplevel" && GIT_EDITOR=true GIT_SEQUENCE_EDITOR=true \
                git "$gitcmd" "$subarg" >/dev/null 2>"$err" ); then
            printf 'echo -markup %%{{Information}%s}\n' "$msg"
            rm -f "$err"
        else
            reason=$(head -1 "$err" | tr -d "'")
            [ -z "$reason" ] && reason="git $gitcmd $subarg exited non-zero"
            printf "fail '%s %s failed: %s'\n" "$gitcmd" "$subarg" "$reason"
            rm -f "$err"
        fi
        printf 'magit-refresh-after-mutation\n'
    }
}

# Definition-time primitives (run at load to emit the final transient).
define-command -hidden -params 1 magit-transient-mode %{
    evaluate-commands %sh{
        name=$1
        printf 'declare-option -hidden str magit_%s_args ""\n' "$name"
        printf 'declare-user-mode magit-%s\n' "$name"
        printf 'define-command magit-%s-dispatch -docstring "Magit %s transient" %%{\n' "$name" "$name"
        printf '    magit-modeline-update\n'
        printf '    enter-user-mode magit-%s\n' "$name"
        printf '}\n'
    }
}

define-command -hidden -params 3 magit-transient-flag %{
    evaluate-commands %sh{
        name=$1
        key=$2
        flag=$3
        printf "map global magit-%s %s ': magit-transient-toggle magit_%s_args %s<ret>: magit-modeline-update<ret>: enter-user-mode magit-%s<ret>' -docstring 'toggle %s'\n" \
            "$name" "$key" "$name" "$flag" "$name" "$flag"
    }
}

# Direct action: run git with accumulated flags + EXTRA args.
define-command -hidden -params 5 magit-transient-run %{
    evaluate-commands %sh{
        name=$1
        key=$2
        gitcmd=$3
        label=$4
        extra=$5
        printf "map global magit-%s %s ': magit-transient-run-and-report magit_%s_args %s %s %s<ret>' -docstring '%s %s'\n" \
            "$name" "$key" "$name" "$label" "$gitcmd" "$extra" "$gitcmd" "$label"
    }
}

# Subcommand action (abort/continue/skip): ignore flags.
define-command -hidden -params 5 magit-transient-subcmd %{
    evaluate-commands %sh{
        name=$1
        key=$2
        gitcmd=$3
        subarg=$4
        msg=$5
        printf "map global magit-%s %s ': magit-transient-subcmd-run %s %s %%{%s}<ret>' -docstring '%s'\n" \
            "$name" "$key" "$gitcmd" "$subarg" "$msg" "$msg"
    }
}

# Prompt action: prompt user, then run git with accumulated flags + user text.
define-command -hidden -params 5 magit-transient-prompt %{
    evaluate-commands %sh{
        name=$1
        key=$2
        gitcmd=$3
        prompt_msg=$4
        label=$5
        # Generate a private apply command per (name, key) pair.
        printf "map global magit-%s %s ': prompt %%{%s} magit-%s-prompt-%s-apply<ret>' -docstring '%s (prompt)'\n" \
            "$name" "$key" "$prompt_msg" "$name" "$key" "$label"
        printf "define-command -hidden magit-%s-prompt-%s-apply %%{\n" "$name" "$key"
        # Pass prompt text twice: once as LABEL (for the toast), once as the
        # final git argv positional. If the prompt yields a multi-word string
        # (e.g. "origin main"), the runtime helper's `"$@"` will split it
        # correctly because we pass via shell word-splitting through map.
        printf "    magit-transient-run-and-report magit_%s_args %%val{text} %s %%val{text}\n" "$name" "$gitcmd"
        printf "}\n"
    }
}

# Bespoke transients (commit + push + pull) declare their own option + mode.
# Generated transients (fetch + merge + cherry + revert + rebase) get theirs
# from `magit-transient-mode` at load time.
declare-option -hidden str magit_push_args ""
declare-option -hidden str magit_pull_args ""
declare-user-mode magit-push
declare-user-mode magit-pull

# Shared modeline refresher: scan every known transient-args opt and
# surface whichever are non-empty, joined with `|`. New transients add a
# line to the `segments` builder.
define-command -hidden magit-modeline-update %{
    evaluate-commands %sh{
        OB=$(printf '\173')
        CB=$(printf '\175')
        segments=
        add_segment() {
            label=$1; value=$2
            [ -z "$value" ] && return
            sep=$([ -n "$segments" ] && printf ' | ')
            segments="${segments}${sep}${label}: ${value}"
        }
        add_segment commit "$kak_opt_magit_commit_args"
        add_segment push   "$kak_opt_magit_push_args"
        add_segment fetch  "$kak_opt_magit_fetch_args"
        add_segment pull   "$kak_opt_magit_pull_args"
        add_segment merge  "$kak_opt_magit_merge_args"
        add_segment cherry "$kak_opt_magit_cherry_args"
        add_segment revert "$kak_opt_magit_revert_args"
        add_segment rebase "$kak_opt_magit_rebase_args"
        add_segment tag    "$kak_opt_magit_tag_args"
        add_segment stash  "$kak_opt_magit_stash_args"
        add_segment diff   "$kak_opt_magit_diff_args"
        add_segment log    "$kak_opt_magit_log_args"
        if [ -n "$segments" ]; then
            printf 'set-option global magit_modeline %%%s[magit: %s] %s\n' \
                "$OB" "$segments" "$CB"
        else
            printf 'set-option global magit_modeline %%%s%s\n' "$OB" "$CB"
        fi
    }
}

# Back-compat aliases — existing commit/push bindings call these names.
# Back-compat alias for push transient's call sites.
define-command -hidden magit-push-modeline-update %{ magit-modeline-update }

define-command magit-push-dispatch -docstring 'Magit push transient' %{
    magit-push-modeline-update
    enter-user-mode magit-push
}

# Flag toggles — same pattern as commit: re-enter after toggle.
map global magit-push F ': magit-transient-toggle magit_push_args --force-with-lease<ret>: magit-push-modeline-update<ret>: enter-user-mode magit-push<ret>' -docstring 'toggle --force-with-lease'
map global magit-push n ': magit-transient-toggle magit_push_args --no-verify<ret>: magit-push-modeline-update<ret>: enter-user-mode magit-push<ret>' -docstring 'toggle --no-verify'
map global magit-push t ': magit-transient-toggle magit_push_args --tags<ret>: magit-push-modeline-update<ret>: enter-user-mode magit-push<ret>' -docstring 'toggle --tags'
map global magit-push s ': magit-transient-toggle magit_push_args --set-upstream<ret>: magit-push-modeline-update<ret>: enter-user-mode magit-push<ret>' -docstring 'toggle --set-upstream'

# Actions — don't re-enter; mode auto-expires.
map global magit-push p ': magit-push-do upstream<ret>' -docstring 'push current → upstream'
map global magit-push P ': magit-push-do upstream<ret>' -docstring 'push current → upstream'
map global magit-push e ': magit-push-do elsewhere<ret>' -docstring 'push to elsewhere (prompt)'

define-command -hidden magit-push-do -params 1 %{
    evaluate-commands %sh{
        target=$1
        args=$kak_opt_magit_push_args
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
        if [ -z "$toplevel" ]; then
            echo "fail 'magit-push: not in a git worktree'"
            exit
        fi
        branch=$(cd "$toplevel" && git symbolic-ref --short HEAD 2>/dev/null)
        if [ -z "$branch" ]; then
            echo "fail 'magit-push: detached HEAD'"
            exit
        fi

        case "$target" in
            upstream)
                # Use configured upstream if present. With --set-upstream,
                # git ALSO requires an explicit `<remote> <branch>` since
                # there's no upstream to derive them from. Detect that
                # case and inject `origin <branch>` (the most common
                # default; users wanting another remote should use the
                # `e` (elsewhere) action instead).
                target_args=""
                case " $args " in
                    *" --set-upstream "*|*" -u "*)
                        # Only inject if no upstream is currently configured;
                        # otherwise git accepts --set-upstream silently with
                        # no extra args.
                        if ! ( cd "$toplevel" && git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1 ); then
                            target_args="origin $branch"
                        fi
                        ;;
                esac
                err=$(mktemp "${TMPDIR:-/tmp}/magit-push-err.XXXXXX")
                if ( cd "$toplevel" && git push $args $target_args >/dev/null 2>"$err" ); then
                    printf 'echo -markup %%{{Information}pushed %s}\n' "$branch"
                    rm -f "$err"
                else
                    # Extract the first hint/error line from stderr for the
                    # status-line message; full stderr still accessible by
                    # re-running `git push` in shell if the user wants it.
                    reason=$(grep -E '^(error|!|hint):|^ !' "$err" | head -1 | sed 's/^[[:space:]]*//')
                    [ -z "$reason" ] && reason=$(head -1 "$err")
                    [ -z "$reason" ] && reason="git push exited non-zero"
                    # Strip single quotes so the fail arg stays well-formed.
                    reason=$(printf '%s' "$reason" | tr -d "'")
                    printf "fail 'push failed: %s'\n" "$reason"
                    rm -f "$err"
                fi
                printf 'set-option global magit_push_args ""\n'
                printf 'magit-push-modeline-update\n'
                printf 'magit-refresh-after-mutation\n'
                ;;
            elsewhere)
                # Prompt user for "<remote> <branch>" then execute.
                printf "prompt 'push to (remote branch): ' magit-push-elsewhere-apply\n"
                ;;
        esac
    }
}

declare-option -hidden str magit_push_pending_args ""
define-command -hidden magit-push-elsewhere-apply %{
    evaluate-commands %sh{
        input=$kak_text
        # Expect "<remote> <branch>" — split on first space.
        remote=${input%% *}
        branch=${input#* }
        if [ -z "$remote" ] || [ "$remote" = "$input" ]; then
            echo "fail 'magit-push: expected <remote> <branch>'"
            exit
        fi
        args=$kak_opt_magit_push_args
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
        err=$(mktemp "${TMPDIR:-/tmp}/magit-push-err.XXXXXX")
        if ( cd "$toplevel" && git push $args "$remote" "$branch" >/dev/null 2>"$err" ); then
            printf 'echo -markup %%{{Information}pushed to %s %s}\n' "$remote" "$branch"
            rm -f "$err"
        else
            reason=$(grep -E '^(error|!|hint):|^ !' "$err" | head -1 | sed 's/^[[:space:]]*//')
            [ -z "$reason" ] && reason=$(head -1 "$err")
            [ -z "$reason" ] && reason="git push exited non-zero"
            reason=$(printf '%s' "$reason" | tr -d "'")
            printf "fail 'push to %s %s failed: %s'\n" "$remote" "$branch" "$reason"
            rm -f "$err"
        fi
        printf 'set-option global magit_push_args ""\n'
        printf 'magit-push-modeline-update\n'
        printf 'magit-refresh-after-mutation\n'
    }
}

# --- Fetch transient (Phase 3) -----------------------------------------
# Defined via the generic transient framework above. `<space>g F` enters.
magit-transient-mode fetch
magit-transient-flag   fetch p --prune
magit-transient-flag   fetch t --tags
magit-transient-flag   fetch A --all
magit-transient-run    fetch f fetch upstream ''
magit-transient-run    fetch a fetch 'all remotes' --all
magit-transient-prompt fetch e fetch 'fetch remote: ' remote

# --- Pull transient (Phase 3) ------------------------------------------
# Pulls DO mutate the worktree (fetch + merge/rebase). Refresh-after is
# essential. Flags --rebase/--no-rebase and --ff-only/--no-ff are mutually
# exclusive at git level; we don't enforce it — git will error cleanly
# and our stderr capture surfaces the message.

define-command magit-pull-dispatch -docstring 'Magit pull transient' %{
    magit-modeline-update
    enter-user-mode magit-pull
}

map global magit-pull r ': magit-transient-toggle magit_pull_args --rebase<ret>: magit-modeline-update<ret>: enter-user-mode magit-pull<ret>'    -docstring 'toggle --rebase'
map global magit-pull R ': magit-transient-toggle magit_pull_args --no-rebase<ret>: magit-modeline-update<ret>: enter-user-mode magit-pull<ret>' -docstring 'toggle --no-rebase'
map global magit-pull f ': magit-transient-toggle magit_pull_args --ff-only<ret>: magit-modeline-update<ret>: enter-user-mode magit-pull<ret>'   -docstring 'toggle --ff-only'
map global magit-pull F ': magit-transient-toggle magit_pull_args --no-ff<ret>: magit-modeline-update<ret>: enter-user-mode magit-pull<ret>'     -docstring 'toggle --no-ff'

map global magit-pull p ': magit-pull-do upstream<ret>'  -docstring 'pull upstream'
map global magit-pull e ': magit-pull-do elsewhere<ret>' -docstring 'pull from elsewhere (prompt)'

define-command -hidden -params 1 magit-pull-do %{
    evaluate-commands %sh{
        target=$1
        args=$kak_opt_magit_pull_args
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
        if [ -z "$toplevel" ]; then
            echo "fail 'magit-pull: not in a git worktree'"
            exit
        fi
        case "$target" in
            upstream)  : ;;
            elsewhere) printf "prompt 'pull from (remote branch): ' magit-pull-elsewhere-apply\n" ; exit ;;
        esac
        # git >= 2.27 requires an explicit reconciliation policy. If the user
        # didn't pick one via transient flags, default to --ff-only (safest:
        # never silently merges or rewrites history).
        case " $args " in
            *" --rebase "*|*" --no-rebase "*|*" --ff-only "*|*" --no-ff "*) ;;
            *) args="--ff-only $args" ;;
        esac
        err=$(mktemp "${TMPDIR:-/tmp}/magit-pull-err.XXXXXX")
        if ( cd "$toplevel" && GIT_EDITOR=true git pull $args >/dev/null 2>"$err" ); then
            printf 'echo -markup %%{{Information}pulled}\n'
            rm -f "$err"
        else
            reason=$(grep -E '^(error|fatal|CONFLICT):|^ !' "$err" | head -1 | sed 's/^[[:space:]]*//')
            [ -z "$reason" ] && reason=$(head -1 "$err")
            [ -z "$reason" ] && reason="git pull exited non-zero"
            reason=$(printf '%s' "$reason" | tr -d "'")
            printf "fail 'pull failed: %s'\n" "$reason"
            rm -f "$err"
        fi
        printf 'set-option global magit_pull_args ""\n'
        printf 'magit-modeline-update\n'
        printf 'magit-refresh-after-mutation\n'
    }
}

define-command -hidden magit-pull-elsewhere-apply %{
    evaluate-commands %sh{
        input=$kak_text
        remote=${input%% *}
        branch=${input#* }
        if [ -z "$remote" ] || [ "$remote" = "$input" ]; then
            echo "fail 'magit-pull: expected <remote> <branch>'"
            exit
        fi
        args=$kak_opt_magit_pull_args
        case " $args " in
            *" --rebase "*|*" --no-rebase "*|*" --ff-only "*|*" --no-ff "*) ;;
            *) args="--ff-only $args" ;;
        esac
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
        err=$(mktemp "${TMPDIR:-/tmp}/magit-pull-err.XXXXXX")
        if ( cd "$toplevel" && GIT_EDITOR=true git pull $args "$remote" "$branch" >/dev/null 2>"$err" ); then
            printf 'echo -markup %%{{Information}pulled from %s %s}\n' "$remote" "$branch"
            rm -f "$err"
        else
            reason=$(grep -E '^(error|fatal|CONFLICT):|^ !' "$err" | head -1 | sed 's/^[[:space:]]*//')
            [ -z "$reason" ] && reason=$(head -1 "$err")
            [ -z "$reason" ] && reason="git pull exited non-zero"
            reason=$(printf '%s' "$reason" | tr -d "'")
            printf "fail 'pull %s %s failed: %s'\n" "$remote" "$branch" "$reason"
            rm -f "$err"
        fi
        printf 'set-option global magit_pull_args ""\n'
        printf 'magit-modeline-update\n'
        printf 'magit-refresh-after-mutation\n'
    }
}

# --- Merge / Cherry-pick / Revert / Rebase transients ----------------
# All declared via the generic framework. Bespoke transients (commit, push,
# pull) live elsewhere due to editor paths / set-upstream / ff-only default.

magit-transient-mode merge
magit-transient-flag   merge f --ff-only
magit-transient-flag   merge F --no-ff
magit-transient-flag   merge S --squash
magit-transient-flag   merge n --no-verify
magit-transient-prompt merge m merge 'merge ref: ' ref
magit-transient-subcmd merge a merge --abort    'merge aborted'
magit-transient-subcmd merge c merge --continue 'merge continued'
# Bespoke variants: merge-preview (dry-run, scratch diff buffer),
# merge-nocommit (leaves MERGE_HEAD for manual commit), merge-editmsg
# (opens COMMIT_EDITMSG so user can edit the merge message before save).
map global magit-merge p ': prompt %{merge-preview ref: } magit-merge-preview-apply<ret>'  -docstring 'preview merge (dry-run)'
map global magit-merge N ': prompt %{merge-nocommit ref: } magit-merge-nocommit-apply<ret>' -docstring 'merge --no-commit (leave MERGE_HEAD)'
map global magit-merge e ': prompt %{merge-editmsg ref: } magit-merge-editmsg-apply<ret>'   -docstring 'merge --edit (prompt to edit message)'

magit-transient-mode cherry
magit-transient-flag   cherry e --edit
magit-transient-flag   cherry n --no-commit
magit-transient-flag   cherry x -x
magit-transient-prompt cherry p cherry-pick 'cherry-pick sha (range with ..): ' sha
magit-transient-subcmd cherry a cherry-pick --abort    'cherry-pick aborted'
magit-transient-subcmd cherry c cherry-pick --continue 'cherry-pick continued'
magit-transient-subcmd cherry s cherry-pick --skip     'cherry-pick skipped'

magit-transient-mode revert
magit-transient-flag   revert e --edit
magit-transient-flag   revert n --no-edit
magit-transient-flag   revert N --no-commit
magit-transient-prompt revert v revert 'revert sha: ' sha
magit-transient-subcmd revert a revert --abort    'revert aborted'
magit-transient-subcmd revert c revert --continue 'revert continued'
magit-transient-subcmd revert s revert --skip     'revert skipped'

magit-transient-mode rebase
magit-transient-flag   rebase s --autostash
magit-transient-flag   rebase S --no-autostash
magit-transient-flag   rebase k --keep-empty
magit-transient-prompt rebase r rebase 'rebase onto: ' base
magit-transient-run    rebase u rebase 'onto upstream' ''
magit-transient-subcmd rebase a rebase --abort    'rebase aborted'
magit-transient-subcmd rebase x rebase --skip     'rebase skipped'
# Interactive rebase + continue live in magit-rebase.kak (bespoke paths).
map global magit-rebase c ': magit-rebase-continue<ret>'    -docstring 'continue rebase'
map global magit-rebase i ': magit-rebase-interactive<ret>' -docstring 'interactive rebase (prompt)'

# --- Tag transient ----------------------------------------------------
# Create via framework. Delete is bespoke (needs `-d` prefix before the
# prompt text; the generic prompt helper only accumulates flags, not a
# positional before the user text).
magit-transient-mode tag
magit-transient-flag   tag f --force
magit-transient-flag   tag a --annotate
magit-transient-flag   tag s --sign
magit-transient-prompt tag t tag 'create tag: ' name

map global magit-tag k ': prompt %{delete tag: } magit-tag-delete-apply<ret>' -docstring 'delete tag (prompt)'
define-command -hidden magit-tag-delete-apply %{
    magit-transient-run-and-report magit_tag_args %val{text} tag -d %val{text}
}

# --- Reset transient --------------------------------------------------
# Six reset modes. Each prompts for a ref (default HEAD) and runs
#   git reset --MODE <ref>
# Bespoke rather than framework-generated: no flag accumulation, the
# "flag" IS the action. All six share one helper.
declare-user-mode magit-reset
define-command magit-reset-dispatch -docstring 'Magit reset transient' %{
    enter-user-mode magit-reset
}
map global magit-reset s ': magit-reset-prompt soft<ret>'     -docstring 'soft reset HEAD (keep index+worktree)'
map global magit-reset m ': magit-reset-prompt mixed<ret>'    -docstring 'mixed reset HEAD (keep worktree)'
map global magit-reset h ': magit-reset-prompt hard<ret>'     -docstring 'hard reset HEAD (destructive)'
map global magit-reset k ': magit-reset-prompt keep<ret>'     -docstring 'keep reset (abort if dirty)'
map global magit-reset i ': magit-reset-index-prompt<ret>'    -docstring 'reset index to a commit'
map global magit-reset w ': magit-reset-worktree-prompt<ret>' -docstring 'reset worktree paths to a commit'

declare-option -hidden str magit_reset_mode ''
define-command -hidden -params 1 magit-reset-prompt %{
    set-option global magit_reset_mode %arg{1}
    prompt 'reset target (ref): ' magit-reset-apply
}
define-command -hidden magit-reset-apply %{
    evaluate-commands %sh{
        mode=$kak_opt_magit_reset_mode
        ref=$kak_text
        [ -z "$ref" ] && ref=HEAD
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
        if [ -z "$toplevel" ]; then
            echo "fail 'magit-reset: not in a git worktree'"
            exit
        fi
        err=$(mktemp "${TMPDIR:-/tmp}/magit-reset-err.XXXXXX")
        if ( cd "$toplevel" && git reset "--$mode" "$ref" >/dev/null 2>"$err" ); then
            # Strip single quotes from the ref in the toast for safety.
            safe=$(printf '%s' "$ref" | tr -d "'")
            printf 'echo -markup %%{{Information}reset --%s to %s}\n' "$mode" "$safe"
        else
            reason=$(grep -E '^(error|fatal):' "$err" | head -1 | sed 's/^[[:space:]]*//')
            [ -z "$reason" ] && reason=$(head -1 "$err")
            [ -z "$reason" ] && reason="git reset exited non-zero"
            reason=$(printf '%s' "$reason" | tr -d "'")
            printf "fail 'reset --%s failed: %s'\n" "$mode" "$reason"
        fi
        rm -f "$err"
        printf 'magit-refresh-after-mutation\n'
    }
}

# Index-only reset: git reset <ref> -- <paths>. Two-stage prompt.
define-command -hidden magit-reset-index-prompt %{
    prompt 'reset index from (ref): ' magit-reset-index-apply
}
define-command -hidden magit-reset-index-apply %{
    set-option global magit_reset_mode %val{text}
    prompt 'paths (space-separated, empty = all): ' magit-reset-index-apply2
}
define-command -hidden magit-reset-index-apply2 %{
    evaluate-commands %sh{
        ref=$kak_opt_magit_reset_mode
        paths=$kak_text
        [ -z "$ref" ] && ref=HEAD
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
        if [ -z "$toplevel" ]; then
            echo "fail 'magit-reset: not in a git worktree'"
            exit
        fi
        err=$(mktemp "${TMPDIR:-/tmp}/magit-reset-err.XXXXXX")
        if [ -z "$paths" ]; then
            # Reset entire index to ref (NOT HEAD — that's --mixed).
            ok=$(cd "$toplevel" && git reset "$ref" -- >/dev/null 2>"$err" && echo ok)
        else
            ok=$(cd "$toplevel" && git reset "$ref" -- $paths >/dev/null 2>"$err" && echo ok)
        fi
        if [ "$ok" = ok ]; then
            printf 'echo -markup %%{{Information}reset index to %s}\n' "$(printf '%s' "$ref" | tr -d "'")"
        else
            reason=$(head -1 "$err" | tr -d "'")
            [ -z "$reason" ] && reason="git reset exited non-zero"
            printf "fail 'reset index failed: %s'\n" "$reason"
        fi
        rm -f "$err"
        printf 'magit-refresh-after-mutation\n'
    }
}

# Worktree-only reset: git checkout <ref> -- <paths>.
define-command -hidden magit-reset-worktree-prompt %{
    prompt 'reset worktree from (ref): ' magit-reset-worktree-apply
}
define-command -hidden magit-reset-worktree-apply %{
    set-option global magit_reset_mode %val{text}
    prompt 'paths (space-separated, required): ' magit-reset-worktree-apply2
}
define-command -hidden magit-reset-worktree-apply2 %{
    evaluate-commands %sh{
        ref=$kak_opt_magit_reset_mode
        paths=$kak_text
        if [ -z "$paths" ]; then
            echo "fail 'magit-reset worktree: paths required'"
            exit
        fi
        [ -z "$ref" ] && ref=HEAD
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
        if [ -z "$toplevel" ]; then
            echo "fail 'magit-reset: not in a git worktree'"
            exit
        fi
        err=$(mktemp "${TMPDIR:-/tmp}/magit-reset-err.XXXXXX")
        if ( cd "$toplevel" && git checkout "$ref" -- $paths >/dev/null 2>"$err" ); then
            printf 'echo -markup %%{{Information}reset worktree paths to %s}\n' "$(printf '%s' "$ref" | tr -d "'")"
        else
            reason=$(head -1 "$err" | tr -d "'")
            [ -z "$reason" ] && reason="git checkout exited non-zero"
            printf "fail 'reset worktree failed: %s'\n" "$reason"
        fi
        rm -f "$err"
        printf 'magit-refresh-after-mutation\n'
    }
}

map global magit-tag l ': magit-tag-list<ret>' -docstring 'list tags'
define-command -hidden magit-tag-list %{
    evaluate-commands %sh{
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
        if [ -z "$toplevel" ]; then
            echo "fail 'magit-tag: not in a git worktree'"
            exit
        fi
        out=$(cd "$toplevel" && git tag --sort=-creatordate 2>/dev/null)
        if [ -z "$out" ]; then
            printf 'echo -markup %%{{Information}no tags}\n'
            exit
        fi
        # Strip any stray single-quotes so info title/body stay well-formed.
        body=$(printf '%s' "$out" | tr -d "'")
        printf "info -title tags '%s'\n" "$body"
    }
}

# --- Stash (create) transient -----------------------------------------
# Acts on the worktree+index, not on existing stash entries (those are
# handled by the stash-actions in *magit-status*: a / A / <a-k>).
# Macro framework gives us mode + flag toggles; bespoke for actions
# that need git stash push semantics or prompts.
magit-transient-mode stash
magit-transient-flag stash u --include-untracked
magit-transient-flag stash a --all
magit-transient-flag stash k --keep-index

# `z` — push with accumulated flags (default: stash both index + worktree).
map global magit-stash z ': magit-stash-push-default<ret>'  -docstring 'stash both (index + worktree)'
# `m` — push with --message (chained prompt).
map global magit-stash m ': magit-stash-push-msg-prompt<ret>' -docstring 'stash with -m message'
# `i` — push --staged (git 2.35+; gracefully fails on older git).
map global magit-stash i ': magit-stash-push-staged<ret>'   -docstring 'stash --staged (index only, git 2.35+)'
# `b` — branch from existing stash@{0}.
map global magit-stash b ': magit-stash-branch-prompt<ret>' -docstring 'create branch from stash@{0}'

define-command -hidden magit-stash-push-default %{
    evaluate-commands %sh{
        args=$kak_opt_magit_stash_args
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
        [ -z "$toplevel" ] && { echo "fail 'magit-stash: not in a git worktree'"; exit; }
        # Check there's actually something to stash (avoids the "No local
        # changes to save" warning becoming a fail).
        if [ -z "$(cd "$toplevel" && git status --porcelain 2>/dev/null)" ]; then
            echo "fail 'magit-stash: nothing to stash'"
            exit
        fi
        err=$(mktemp "${TMPDIR:-/tmp}/magit-stash-err.XXXXXX")
        if ( cd "$toplevel" && git stash push $args >/dev/null 2>"$err" ); then
            printf "echo -markup %%{{Information}stash push%s}\n" \
                "$([ -n "$args" ] && printf ' (%s)' "$args")"
        else
            reason=$(head -1 "$err" | tr -d "'")
            [ -z "$reason" ] && reason="git stash push exited non-zero"
            printf "fail 'stash push failed: %s'\n" "$reason"
        fi
        rm -f "$err"
        printf "set-option global magit_stash_args ''\n"
        printf "magit-modeline-update\n"
        printf "magit-refresh-after-mutation\n"
    }
}

define-command -hidden magit-stash-push-msg-prompt %{
    prompt 'stash message: ' magit-stash-push-msg-apply
}
define-command -hidden magit-stash-push-msg-apply %{
    evaluate-commands %sh{
        msg=$kak_text
        if [ -z "$msg" ]; then
            echo "fail 'magit-stash: empty message'"
            exit
        fi
        args=$kak_opt_magit_stash_args
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
        [ -z "$toplevel" ] && { echo "fail 'magit-stash: not in a git worktree'"; exit; }
        if [ -z "$(cd "$toplevel" && git status --porcelain 2>/dev/null)" ]; then
            echo "fail 'magit-stash: nothing to stash'"
            exit
        fi
        err=$(mktemp "${TMPDIR:-/tmp}/magit-stash-err.XXXXXX")
        if ( cd "$toplevel" && git stash push $args -m "$msg" >/dev/null 2>"$err" ); then
            safe=$(printf '%s' "$msg" | tr -d "'")
            printf "echo -markup %%{{Information}stash: %s}\n" "$safe"
        else
            reason=$(head -1 "$err" | tr -d "'")
            [ -z "$reason" ] && reason="git stash push exited non-zero"
            printf "fail 'stash push failed: %s'\n" "$reason"
        fi
        rm -f "$err"
        printf "set-option global magit_stash_args ''\n"
        printf "magit-modeline-update\n"
        printf "magit-refresh-after-mutation\n"
    }
}

define-command -hidden magit-stash-push-staged %{
    evaluate-commands %sh{
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
        [ -z "$toplevel" ] && { echo "fail 'magit-stash: not in a git worktree'"; exit; }
        # --staged needs git >= 2.35. Quick capability check.
        if ! ( cd "$toplevel" && git stash push --help 2>/dev/null | grep -q -- '--staged' ); then
            echo "fail 'magit-stash --staged: requires git 2.35+'"
            exit
        fi
        if [ -z "$(cd "$toplevel" && git diff --cached --name-only 2>/dev/null)" ]; then
            echo "fail 'magit-stash --staged: nothing staged'"
            exit
        fi
        err=$(mktemp "${TMPDIR:-/tmp}/magit-stash-err.XXXXXX")
        if ( cd "$toplevel" && git stash push --staged >/dev/null 2>"$err" ); then
            printf "echo -markup %%{{Information}stash --staged}\n"
        else
            reason=$(head -1 "$err" | tr -d "'")
            [ -z "$reason" ] && reason="git stash push --staged exited non-zero"
            printf "fail 'stash --staged failed: %s'\n" "$reason"
        fi
        rm -f "$err"
        printf "magit-refresh-after-mutation\n"
    }
}

define-command -hidden magit-stash-branch-prompt %{
    prompt 'branch from stash@{0}: ' magit-stash-branch-apply
}
define-command -hidden magit-stash-branch-apply %{
    evaluate-commands %sh{
        branch=$kak_text
        if [ -z "$branch" ]; then
            echo "fail 'magit-stash branch: name required'"
            exit
        fi
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
        [ -z "$toplevel" ] && { echo "fail 'magit-stash: not in a git worktree'"; exit; }
        # Ensure there's a stash to branch from.
        if [ -z "$(cd "$toplevel" && git stash list 2>/dev/null | head -1)" ]; then
            echo "fail 'magit-stash branch: no stashes'"
            exit
        fi
        err=$(mktemp "${TMPDIR:-/tmp}/magit-stash-err.XXXXXX")
        # `stash@{0}` carries braces — single-quote per Lesson 29.
        if ( cd "$toplevel" && git stash branch "$branch" 'stash@{0}' >/dev/null 2>"$err" ); then
            sb=$(printf '%s' "$branch" | tr -d "'")
            printf "echo -markup %%{{Information}stash → branch %s}\n" "$sb"
        else
            reason=$(head -1 "$err" | tr -d "'")
            [ -z "$reason" ] && reason="git stash branch exited non-zero"
            printf "fail 'stash branch failed: %s'\n" "$reason"
        fi
        rm -f "$err"
        printf "magit-refresh-after-mutation\n"
    }
}

# --- Remote transient -------------------------------------------------
# Six actions: add / rename / remove / set-url / prune / list.
# Two-prompt actions (add/rename/set-url) chain prompts via a scratch
# option to carry the first prompt's text into the second.
declare-user-mode magit-remote
define-command magit-remote-dispatch -docstring 'Magit remote transient' %{
    enter-user-mode magit-remote
}
declare-option -hidden str magit_remote_scratch ''

map global magit-remote a ': magit-remote-add-prompt<ret>'    -docstring 'add remote'
map global magit-remote r ': magit-remote-rename-prompt<ret>' -docstring 'rename remote'
map global magit-remote k ': magit-remote-remove-prompt<ret>' -docstring 'remove remote'
map global magit-remote u ': magit-remote-seturl-prompt<ret>' -docstring 'set-url'
map global magit-remote p ': magit-remote-prune-prompt<ret>'  -docstring 'prune remote'
map global magit-remote l ': magit-remote-list<ret>'          -docstring 'list remotes'

# add: prompt name → prompt url → run
define-command -hidden magit-remote-add-prompt %{
    prompt 'remote name: ' magit-remote-add-step2
}
define-command -hidden magit-remote-add-step2 %{
    set-option global magit_remote_scratch %val{text}
    prompt 'url: ' magit-remote-add-apply
}
define-command -hidden magit-remote-add-apply %{
    evaluate-commands %sh{
        name=$kak_opt_magit_remote_scratch
        url=$kak_text
        if [ -z "$name" ] || [ -z "$url" ]; then
            echo "fail 'magit-remote add: name and url required'"
            exit
        fi
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
        [ -z "$toplevel" ] && { echo "fail 'magit-remote: not in a git worktree'"; exit; }
        err=$(mktemp "${TMPDIR:-/tmp}/magit-remote-err.XXXXXX")
        if ( cd "$toplevel" && git remote add "$name" "$url" >/dev/null 2>"$err" ); then
            safe_n=$(printf '%s' "$name" | tr -d "'")
            safe_u=$(printf '%s' "$url"  | tr -d "'")
            printf "echo -markup %%{{Information}added remote %s -> %s}\n" "$safe_n" "$safe_u"
        else
            reason=$(head -1 "$err" | tr -d "'")
            [ -z "$reason" ] && reason="git remote add failed"
            printf "fail 'remote add failed: %s'\n" "$reason"
        fi
        rm -f "$err"
        printf "set-option global magit_remote_scratch ''\n"
        printf "magit-refresh-after-mutation\n"
    }
}

# rename: prompt old → prompt new → run
define-command -hidden magit-remote-rename-prompt %{
    prompt 'rename remote: ' magit-remote-rename-step2
}
define-command -hidden magit-remote-rename-step2 %{
    set-option global magit_remote_scratch %val{text}
    prompt 'new name: ' magit-remote-rename-apply
}
define-command -hidden magit-remote-rename-apply %{
    evaluate-commands %sh{
        old=$kak_opt_magit_remote_scratch
        new=$kak_text
        if [ -z "$old" ] || [ -z "$new" ]; then
            echo "fail 'magit-remote rename: old and new names required'"
            exit
        fi
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
        [ -z "$toplevel" ] && { echo "fail 'magit-remote: not in a git worktree'"; exit; }
        err=$(mktemp "${TMPDIR:-/tmp}/magit-remote-err.XXXXXX")
        if ( cd "$toplevel" && git remote rename "$old" "$new" >/dev/null 2>"$err" ); then
            so=$(printf '%s' "$old" | tr -d "'"); sn=$(printf '%s' "$new" | tr -d "'")
            printf "echo -markup %%{{Information}renamed remote %s -> %s}\n" "$so" "$sn"
        else
            reason=$(head -1 "$err" | tr -d "'")
            [ -z "$reason" ] && reason="git remote rename failed"
            printf "fail 'remote rename failed: %s'\n" "$reason"
        fi
        rm -f "$err"
        printf "set-option global magit_remote_scratch ''\n"
        printf "magit-refresh-after-mutation\n"
    }
}

# set-url: prompt name → prompt new url → run
define-command -hidden magit-remote-seturl-prompt %{
    prompt 'set-url for remote: ' magit-remote-seturl-step2
}
define-command -hidden magit-remote-seturl-step2 %{
    set-option global magit_remote_scratch %val{text}
    prompt 'new url: ' magit-remote-seturl-apply
}
define-command -hidden magit-remote-seturl-apply %{
    evaluate-commands %sh{
        name=$kak_opt_magit_remote_scratch
        url=$kak_text
        if [ -z "$name" ] || [ -z "$url" ]; then
            echo "fail 'magit-remote set-url: name and url required'"
            exit
        fi
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
        [ -z "$toplevel" ] && { echo "fail 'magit-remote: not in a git worktree'"; exit; }
        err=$(mktemp "${TMPDIR:-/tmp}/magit-remote-err.XXXXXX")
        if ( cd "$toplevel" && git remote set-url "$name" "$url" >/dev/null 2>"$err" ); then
            sn=$(printf '%s' "$name" | tr -d "'"); su=$(printf '%s' "$url" | tr -d "'")
            printf "echo -markup %%{{Information}set-url %s -> %s}\n" "$sn" "$su"
        else
            reason=$(head -1 "$err" | tr -d "'")
            [ -z "$reason" ] && reason="git remote set-url failed"
            printf "fail 'remote set-url failed: %s'\n" "$reason"
        fi
        rm -f "$err"
        printf "set-option global magit_remote_scratch ''\n"
        printf "magit-refresh-after-mutation\n"
    }
}

# remove: single-prompt
define-command -hidden magit-remote-remove-prompt %{
    prompt 'remove remote: ' magit-remote-remove-apply
}
define-command -hidden magit-remote-remove-apply %{
    evaluate-commands %sh{
        name=$kak_text
        if [ -z "$name" ]; then
            echo "fail 'magit-remote remove: name required'"
            exit
        fi
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
        [ -z "$toplevel" ] && { echo "fail 'magit-remote: not in a git worktree'"; exit; }
        err=$(mktemp "${TMPDIR:-/tmp}/magit-remote-err.XXXXXX")
        if ( cd "$toplevel" && git remote remove "$name" >/dev/null 2>"$err" ); then
            sn=$(printf '%s' "$name" | tr -d "'")
            printf "echo -markup %%{{Information}removed remote %s}\n" "$sn"
        else
            reason=$(head -1 "$err" | tr -d "'")
            [ -z "$reason" ] && reason="git remote remove failed"
            printf "fail 'remote remove failed: %s'\n" "$reason"
        fi
        rm -f "$err"
        printf "magit-refresh-after-mutation\n"
    }
}

# prune: single-prompt; reports the (possibly empty) list of pruned refs
define-command -hidden magit-remote-prune-prompt %{
    prompt 'prune remote: ' magit-remote-prune-apply
}
define-command -hidden magit-remote-prune-apply %{
    evaluate-commands %sh{
        name=$kak_text
        if [ -z "$name" ]; then
            echo "fail 'magit-remote prune: name required'"
            exit
        fi
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
        [ -z "$toplevel" ] && { echo "fail 'magit-remote: not in a git worktree'"; exit; }
        err=$(mktemp "${TMPDIR:-/tmp}/magit-remote-err.XXXXXX")
        if ( cd "$toplevel" && git remote prune "$name" >/dev/null 2>"$err" ); then
            sn=$(printf '%s' "$name" | tr -d "'")
            printf "echo -markup %%{{Information}pruned %s}\n" "$sn"
        else
            reason=$(head -1 "$err" | tr -d "'")
            [ -z "$reason" ] && reason="git remote prune failed"
            printf "fail 'remote prune failed: %s'\n" "$reason"
        fi
        rm -f "$err"
        printf "magit-refresh-after-mutation\n"
    }
}

# list: info box of `git remote -v` output
define-command -hidden magit-remote-list %{
    evaluate-commands %sh{
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
        [ -z "$toplevel" ] && { echo "fail 'magit-remote: not in a git worktree'"; exit; }
        out=$(cd "$toplevel" && git remote -v 2>/dev/null)
        if [ -z "$out" ]; then
            printf "echo -markup %%{{Information}no remotes configured}\n"
            exit
        fi
        body=$(printf '%s' "$out" | tr -d "'")
        printf "info -title remotes '%s'\n" "$body"
    }
}

# --- Merge variants: preview / nocommit / editmsg -----------------------
# Shared precheck: refuse if a merge / rebase / am / etc. is already
# in progress, or if the named ref doesn't exist.
#
# Writes the following to stdout (parsed as kakscript by the caller):
#   - `fail '...'` + early exit on error  (uses `echo` + sentinel value)
#   - otherwise: sets vars toplevel + gitdir via stderr (caller reads).
# Called via `eval "$(cd ... && magit-merge--precheck "$rev")"`.
# Since we can't really eval like that in a %sh{} echo-kakscript pattern,
# just inline the precheck where needed.

define-command -hidden magit-merge-preview-apply %{
    evaluate-commands %sh{
        rev=$(printf '%s' "$kak_text" | awk '{$1=$1; print}')
        if [ -z "$rev" ]; then
            echo "fail 'magit-merge-preview: empty ref'"
            exit
        fi
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
        [ -z "$toplevel" ] && { echo "fail 'not in a git worktree'"; exit; }
        if ! ( cd "$toplevel" && git rev-parse --verify "$rev" ) >/dev/null 2>&1; then
            printf "fail 'magit-merge-preview: unknown ref: %s'\n" "$rev"
            exit
        fi
        # Read-only path via `git merge-tree --write-tree`. git 2.38+ emits
        # the merge-commit SHA (or conflict info) to stdout; `git diff`
        # against HEAD shows what the merge would introduce.
        out=$(mktemp "${TMPDIR:-/tmp}/magit-merge-preview.XXXXXX")
        tree_sha=$(cd "$toplevel" && git merge-tree --write-tree HEAD "$rev" 2>/dev/null | head -1)
        if [ -z "$tree_sha" ]; then
            rm -f "$out"
            echo "fail 'magit-merge-preview: git merge-tree failed (need git 2.38+)'"
            exit
        fi
        ( cd "$toplevel" && git diff HEAD "$tree_sha" ) > "$out" 2>/dev/null
        if [ ! -s "$out" ]; then
            printf "%s\n" "# No changes — $rev is already in HEAD or empty merge" > "$out"
        fi
        # Open scratch buffer `*magit-merge-preview-<short>*`.
        short=$(printf '%s' "$rev" | sed 's|[^A-Za-z0-9._/-]|_|g' | head -c 20)
        bufname="*magit-merge-preview-$short*"
        esc_bufname=$(printf '%s' "$bufname" | sed "s/'/''/g")
        esc_out=$(printf '%s' "$out" | sed "s/'/''/g")
        printf "edit -scratch '%s'\n" "$esc_bufname"
        printf "set-option buffer filetype diff\n"
        printf "execute-keys '%%%%|cat ''%s''<ret>gg'\n" "$esc_out"
        printf "map buffer normal q ': delete-buffer<ret>' -docstring 'quit preview'\n"
        printf "map buffer normal '?' ': enter-user-mode magit-diff-view-keys<ret>' -docstring 'show keys (help)'\n"
        printf "nop %%sh{ rm -f '%s' }\n" "$esc_out"
        printf "echo -markup %%{{Information}merge preview: HEAD..%s (q to close)}\n" "$rev"
    }
}

define-command -hidden magit-merge-nocommit-apply %{
    evaluate-commands %sh{
        rev=$(printf '%s' "$kak_text" | awk '{$1=$1; print}')
        if [ -z "$rev" ]; then
            echo "fail 'magit-merge-nocommit: empty ref'"
            exit
        fi
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
        [ -z "$toplevel" ] && { echo "fail 'not in a git worktree'"; exit; }
        gitdir=$(cd "$toplevel" && git rev-parse --git-dir 2>/dev/null)
        case "$gitdir" in /*) ;; *) gitdir="$toplevel/$gitdir" ;; esac
        if [ -f "$gitdir/MERGE_HEAD" ]; then
            echo "fail 'merge already in progress — use :git merge --abort first'"
            exit
        fi
        if ! ( cd "$toplevel" && git rev-parse --verify "$rev" ) >/dev/null 2>&1; then
            printf "fail 'magit-merge-nocommit: unknown ref: %s'\n" "$rev"
            exit
        fi
        err=$(mktemp "${TMPDIR:-/tmp}/magit-merge-nocommit-err.XXXXXX")
        args=$kak_opt_magit_merge_args
        if ( cd "$toplevel" && GIT_EDITOR=true git merge --no-commit --no-ff $args "$rev" >/dev/null 2>"$err" ); then
            printf "echo -markup %%{{Information}merge staged (no commit) — inspect + commit, or git merge --abort}\n"
        else
            reason=$(head -1 "$err" | tr -d "'\"")
            [ -z "$reason" ] && reason='merge failed'
            if [ -f "$gitdir/MERGE_HEAD" ]; then
                printf "fail 'merge conflict: %s — resolve + stage + commit, or :git merge --abort'\n" "$reason"
            else
                printf "fail 'merge-nocommit: %s'\n" "$reason"
            fi
        fi
        rm -f "$err"
        printf 'magit-refresh-after-mutation\n'
    }
}

define-command -hidden magit-merge-editmsg-apply %{
    evaluate-commands %sh{
        rev=$(printf '%s' "$kak_text" | awk '{$1=$1; print}')
        if [ -z "$rev" ]; then
            echo "fail 'magit-merge-editmsg: empty ref'"
            exit
        fi
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
        [ -z "$toplevel" ] && { echo "fail 'not in a git worktree'"; exit; }
        gitdir=$(cd "$toplevel" && git rev-parse --git-dir 2>/dev/null)
        case "$gitdir" in /*) ;; *) gitdir="$toplevel/$gitdir" ;; esac
        if [ -f "$gitdir/MERGE_HEAD" ]; then
            echo "fail 'merge already in progress — use :git merge --abort first'"
            exit
        fi
        if ! ( cd "$toplevel" && git rev-parse --verify "$rev" ) >/dev/null 2>&1; then
            printf "fail 'magit-merge-editmsg: unknown ref: %s'\n" "$rev"
            exit
        fi
        # Stage the merge via --no-commit so MERGE_MSG is written but no
        # commit happens yet. Then open MERGE_MSG for editing; on save,
        # the BufWritePost hook runs `git commit -F MERGE_MSG` to finalize.
        err=$(mktemp "${TMPDIR:-/tmp}/magit-merge-editmsg-err.XXXXXX")
        args=$kak_opt_magit_merge_args
        if ! ( cd "$toplevel" && GIT_EDITOR=true git merge --no-commit --no-ff $args "$rev" >/dev/null 2>"$err" ); then
            reason=$(head -1 "$err" | tr -d "'\"")
            [ -z "$reason" ] && reason='merge failed'
            rm -f "$err"
            if [ -f "$gitdir/MERGE_HEAD" ]; then
                printf "fail 'merge conflict: %s — resolve + stage + commit, or :git merge --abort'\n" "$reason"
            else
                printf "fail 'merge-editmsg: %s'\n" "$reason"
            fi
            exit
        fi
        rm -f "$err"

        msgfile="$gitdir/MERGE_MSG"
        if [ ! -f "$msgfile" ]; then
            echo "fail 'magit-merge-editmsg: MERGE_MSG not written'"
            exit
        fi
        esc_msgfile=$(printf '%s' "$msgfile" | sed "s/'/''/g")
        esc_toplevel=$(printf '%s' "$toplevel" | sed "s/'/''/g")
        printf "edit '%s'\n" "$esc_msgfile"
        printf "set-option buffer filetype git-commit\n"
        # One-shot BufWritePost: commit using the edited MERGE_MSG, then
        # clean the hook (via the hook group + delete-buffer).
        printf "hook -group magit-merge-editmsg buffer BufWritePost '.*MERGE_MSG' %%{\n"
        printf "    evaluate-commands %%sh%s\n" "$(printf '\173')"
        printf "        if ( cd '%s' && git commit -F '%s' --cleanup=strip >/dev/null 2>&1 ); then\n" \
            "$esc_toplevel" "$esc_msgfile"
        printf "            printf 'echo -markup %%%%%s{Information}merge committed%%%%%s; delete-buffer; magit-refresh-after-mutation\\\\n' '%s' '%s'\n" \
            "$(printf '\173')" "$(printf '\175')" "$(printf '\173')" "$(printf '\175')"
        printf "        else\n"
        printf "            echo 'fail magit-merge-editmsg: git commit failed'\n"
        printf "        fi\n"
        printf "    %s\n" "$(printf '\175')"
        printf "}\n"
        printf "echo -markup %%{{Information}edit merge message, :w to commit, or :git merge --abort to cancel}\n"
    }
}


}
