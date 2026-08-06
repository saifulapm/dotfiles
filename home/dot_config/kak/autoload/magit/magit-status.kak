# magit-status.kak — *magit-status* buffer: render, linemap, dispatchers,
# stash actions, hunk-level staging, section navigation, filetype bindings.
# Depends on magit.kak's state + magit-refresh-after-mutation.

provide-module magit-status %{

# --- Status buffer ------------------------------------------------------
define-command magit-status -docstring 'Open the magit status buffer' %{
    evaluate-commands %sh{
        if ! git rev-parse --git-dir >/dev/null 2>&1; then
            echo "fail 'magit-status: not a git repository'"
            exit
        fi
    }
    try %{
        buffer '*magit-status*'
    } catch %{
        edit -scratch '*magit-status*'
        set-option buffer filetype magit-status
    }
    magit-status-folds-load
    magit-status-render
}

# Render the status buffer. Implementation strategy: build the full content
# into a tempfile in shell, then replace buffer contents with one
# `execute-keys %|cat <tempfile><ret>` — avoids shell→kakscript text escaping.
define-command -hidden magit-status-render %{
    set-option buffer magit_in_refresh true
    evaluate-commands -save-regs 'a/' %{
        # Capture the linemap entry at cursor BEFORE re-render.
        # `magit-at-cursor a` sets reg a to "section|file|file_line".
        try %{ magit-at-cursor a } catch %{ set-register a 'blank||0' }
        evaluate-commands %sh{
            tmp=$(mktemp "${TMPDIR:-/tmp}/magit-status.XXXXXX")
            map=$(mktemp "${TMPDIR:-/tmp}/magit-linemap.XXXXXX")
            # emit <text> <section> [<file> [<file_line>]]
            # Writes <text>\n to $tmp AND a "section|file|file_line" entry to $map.
            # Uses env-export so sub-pipelines can see the paths.
            export MAGIT_TMP="$tmp" MAGIT_MAP="$map"
            emit() {
                # args: text section [file] [file_line]
                printf '%s\n' "$1" >> "$MAGIT_TMP"
                printf '%s|%s|%s\n' "${2:-blank}" "${3:-}" "${4:-0}" >> "$MAGIT_MAP"
            }
            export -f emit 2>/dev/null || true   # bash export; harmless on dash

            # Folding: surrounding spaces make `case` matching straightforward.
            FOLDED=" $kak_opt_magit_status_collapsed "
            is_folded() {
                case "$FOLDED" in *" $1 "*) return 0 ;; *) return 1 ;; esac
            }

            # In an empty repo, `git rev-parse --abbrev-ref HEAD` prints HEAD
            # to stdout AND exits non-zero. A naive `$(cmd || echo fallback)`
            # concatenates both (HEAD\n(detached)). Check exit separately.
            if branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null); then
                [ "$branch" = "HEAD" ] && branch='(detached)'
            else
                if [ -f "$(git rev-parse --git-dir 2>/dev/null)/HEAD" ]; then
                    # Empty repo: HEAD points to a ref that doesn't exist yet.
                    branch=$(sed -n 's|^ref: refs/heads/||p' "$(git rev-parse --git-dir)/HEAD" 2>/dev/null)
                    [ -n "$branch" ] && branch="$branch (no commits yet)"
                fi
                [ -z "$branch" ] && branch='(detached)'
            fi
            upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)
            head_summary=$(git log -1 --pretty='%h %s' 2>/dev/null || true)
            if is_folded head; then
                emit "## Head …" head
            else
                emit "## Head" head
                emit "Branch:   $branch" head
                [ -n "$upstream" ]     && emit "Upstream: $upstream" head
                [ -n "$head_summary" ] && emit "HEAD:     $head_summary" head
            fi
            emit "" blank

            # Rebase in progress (if any). git uses one of two state dirs:
            # .git/rebase-merge (interactive) or .git/rebase-apply (legacy).
            gitdir=$(git rev-parse --git-dir 2>/dev/null)
            rbdir=""
            if [ -n "$gitdir" ]; then
                case "$gitdir" in /*) ;; *) gitdir="$(pwd)/$gitdir" ;; esac
                if [ -d "$gitdir/rebase-merge" ]; then
                    rbdir="$gitdir/rebase-merge"
                elif [ -d "$gitdir/rebase-apply" ]; then
                    rbdir="$gitdir/rebase-apply"
                fi
            fi
            if [ -n "$rbdir" ]; then
                rb_onto=$(cat "$rbdir/onto" 2>/dev/null | head -c 8)
                rb_head=$(cat "$rbdir/head-name" 2>/dev/null | sed 's|^refs/heads/||')
                rb_step=$(cat "$rbdir/msgnum" 2>/dev/null || echo '?')
                rb_end=$(cat "$rbdir/end" 2>/dev/null || echo '?')
                # `stopped-sha` is written when an `edit` verb pauses the
                # rebase; `message` holds the current commit's message.
                # Either presence indicates an edit-stop (vs. a conflict,
                # which leaves a MERGE_MSG / index conflicts instead).
                rb_stopped=""
                if [ -f "$rbdir/stopped-sha" ]; then
                    rb_stopped=$(head -c 8 "$rbdir/stopped-sha" 2>/dev/null)
                fi
                rb_hdr="## Rebase in progress ($rb_head onto $rb_onto, step $rb_step/$rb_end)"
                if is_folded rebase-progress; then
                    emit "$rb_hdr …" rebase-progress
                else
                    emit "$rb_hdr" rebase-progress
                    if [ -n "$rb_stopped" ]; then
                        emit "  paused at $rb_stopped — <space>g r c to continue, <space>g r a to abort" rebase-progress
                    else
                        emit "  <space>g r c to continue, <space>g r a to abort, <space>g r x to skip" rebase-progress
                    fi
                    if [ -f "$rbdir/git-rebase-todo" ]; then
                        remaining=$(grep -vE '^[[:space:]]*(#|$)' "$rbdir/git-rebase-todo" 2>/dev/null || true)
                        if [ -n "$remaining" ]; then
                            OLD_IFS=$IFS; IFS='
'
                            for l in $remaining; do
                                emit "  $l" rebase-todo-line
                            done
                            IFS=$OLD_IFS
                        fi
                    fi
                fi
                emit "" blank
            fi

            # Bisect in progress: .git/BISECT_LOG is written on `git bisect start`
            # and removed on `git bisect reset`. Summarize good/bad counts.
            if [ -n "$gitdir" ] && [ -f "$gitdir/BISECT_LOG" ]; then
                # grep -c prints 0 on no matches; exit code 1 is harmless here.
                # Don't add `|| echo 0` — it would concatenate a second 0 onto
                # the output (one from grep, one from echo) and produce
                # multi-line variable content that breaks `emit`.
                bs_good=$(grep -c '^# good:' "$gitdir/BISECT_LOG" 2>/dev/null; true)
                bs_bad=$(grep  -c '^# bad:'  "$gitdir/BISECT_LOG" 2>/dev/null; true)
                bs_hdr="## Bisecting ($bs_good good / $bs_bad bad)"
                if is_folded bisect-progress; then
                    emit "$bs_hdr …" bisect-progress
                else
                    emit "$bs_hdr" bisect-progress
                    emit "  use <space>g i for transient: g/b/k/r/l/v" bisect-progress
                fi
                emit "" blank
            fi

            # Other worktrees: only render if there are siblings.
            # `git worktree list --porcelain` chunks: blank-separated records
            # each starting with "worktree <path>" then optional "HEAD <sha>"
            # / "branch refs/heads/<name>" / "bare" / "detached" lines.
            #
            # Note: $toplevel here is set by the magit-log-render? Actually it's
            # set AT THE TOP of magit-status-render. Need to make sure it's
            # available here. Defensive re-fetch in case scope went weird.
            current_wt=$(git rev-parse --show-toplevel 2>/dev/null)
            wt_tmp="${tmp}.wt"
            git worktree list --porcelain 2>/dev/null > "$wt_tmp"
            # Parse into "<path>|<sha>|<branch>" lines, skip current.
            wt_lines=$(awk -v current="$current_wt" '
                /^worktree / { flush(); path=substr($0, 10); sha=""; branch=""; next }
                /^HEAD /     { sha=substr($0, 6); next }
                /^branch refs\/heads\// { branch=substr($0, 19); next }
                /^detached/  { branch="(detached)"; next }
                /^bare/      { branch="(bare)"; next }
                END { flush() }
                function flush() {
                    if (path == "") return
                    if (path == current) { path=""; return }
                    short = (sha != "") ? substr(sha, 1, 8) : "--------"
                    bdisp = (branch != "") ? branch : "(detached)"
                    printf "%s|%s|%s\n", path, short, bdisp
                    path=""
                }
            ' "$wt_tmp")
            rm -f "$wt_tmp"
            if [ -n "$wt_lines" ]; then
                wt_count=$(printf '%s\n' "$wt_lines" | wc -l | tr -d ' ')
                if is_folded worktree; then
                    emit "## Other worktrees ($wt_count) …" worktree
                else
                    emit "## Other worktrees ($wt_count)" worktree
                    OLD_IFS=$IFS; IFS='
'
                    for l in $wt_lines; do
                        # Format: "  <short> <branch> <path>"
                        path=${l%%|*}; rest=${l#*|}
                        short=${rest%%|*}; branch=${rest#*|}
                        emit "  $short $branch $path" worktree-entry "$path"
                    done
                    IFS=$OLD_IFS
                fi
                emit "" blank
            fi

            # Submodules: only render if .gitmodules exists. `git submodule
            # status` prints one line per registered submodule:
            #   <status-char><sha> <path> (<describe>)
            # status-char: ' ' clean, '-' not initialized, '+' SHA differs from
            # superproject, 'U' merge conflict.
            sm_tmp="${tmp}.sm"
            if [ -f "$current_wt/.gitmodules" ]; then
                ( cd "$current_wt" && git submodule status 2>/dev/null ) > "$sm_tmp"
            else
                : > "$sm_tmp"
            fi
            if [ -s "$sm_tmp" ]; then
                sm_count=$(wc -l < "$sm_tmp" | tr -d ' ')
                if is_folded submodule; then
                    emit "## Submodules ($sm_count) …" submodule
                else
                    emit "## Submodules ($sm_count)" submodule
                    OLD_IFS=$IFS; IFS='
'
                    while IFS= read -r l || [ -n "$l" ]; do
                        # Trim leading whitespace for clean display, but keep
                        # the status char (col 1 of the original output).
                        st=$(printf '%s' "$l" | cut -c1)
                        body=$(printf '%s' "$l" | sed 's/^.//')
                        # body now: "<sha> <path> (<describe>)"
                        sha=$(printf '%s' "$body" | awk '{print $1}')
                        short=$(printf '%s' "$sha" | cut -c1-8)
                        rest=$(printf '%s' "$body" | sed -n 's/^[^ ]* //p')
                        # rest = "<path> (<describe>)"
                        path=$(printf '%s' "$rest" | sed 's/ (.*$//')
                        emit "  $st $short $rest" submodule-entry "$path"
                    done < "$sm_tmp"
                    IFS=$OLD_IFS
                fi
                emit "" blank
            fi
            rm -f "$sm_tmp"

            # Untracked
            untracked=$(git ls-files --others --exclude-standard)
            if [ -n "$untracked" ]; then
                count=$(printf '%s\n' "$untracked" | wc -l | tr -d ' ')
                if is_folded untracked; then
                    emit "## Untracked files ($count) …" untracked
                else
                    emit "## Untracked files ($count)" untracked
                    OLD_IFS=$IFS; IFS='
'
                    for f in $untracked; do
                        emit "  ## $f" untracked "$f"
                    done
                    IFS=$OLD_IFS
                fi
                emit "" blank
            fi

            # Unstaged (worktree vs index)
            unstaged_files=$(git diff --name-only)
            if [ -n "$unstaged_files" ]; then
                ucount=$(printf '%s\n' "$unstaged_files" | wc -l | tr -d ' ')
                if is_folded unstaged; then
                    emit "## Unstaged changes ($ucount) …" unstaged
                    emit "" blank
                else
                emit "## Unstaged changes ($ucount)" unstaged
                OLD_IFS=$IFS; IFS='
'
                for f in $unstaged_files; do
                    if is_folded "unstaged:$f"; then
                        emit "  ## $f …" unstaged "$f"
                        continue
                    fi
                    emit "  ## $f" unstaged "$f"
                    # Per-file diff without the `diff --git`/index/---/+++ preamble.
                    # Stream into a tempfile to keep emit calls in the parent shell.
                    diff_tmp=$(mktemp "${TMPDIR:-/tmp}/magit-diff.XXXXXX")
                    git diff --no-color -- "$f" | awk '
                        /^diff --git/ {skip=1; next}
                        /^index / && skip {next}
                        /^--- /  && skip {next}
                        /^\+\+\+/ && skip {skip=0; next}
                        {print}
                    ' > "$diff_tmp"
                    cur=0
                    IFS_INNER=$IFS; IFS=''
                    while IFS= read -r line || [ -n "$line" ]; do
                        case "$line" in
                            @@*)
                                newstart=$(printf '%s' "$line" | sed -n 's/.*+\([0-9][0-9]*\).*/\1/p')
                                [ -z "$newstart" ] && newstart=0
                                emit "    $line" "unstaged-hunk" "$f" "$newstart"
                                cur=$newstart
                                ;;
                            +*)
                                emit "    $line" "unstaged-line" "$f" "$cur"
                                cur=$((cur+1))
                                ;;
                            -*)
                                emit "    $line" "unstaged-line" "$f" "$cur"
                                ;;
                            *)
                                emit "    $line" "unstaged-ctx" "$f" "$cur"
                                cur=$((cur+1))
                                ;;
                        esac
                    done < "$diff_tmp"
                    IFS=$IFS_INNER
                    rm -f "$diff_tmp"
                done
                IFS=$OLD_IFS
                emit "" blank
                fi
            fi

            # Staged (index vs HEAD)
            staged_files=$(git diff --cached --name-only)
            if [ -n "$staged_files" ]; then
                scount=$(printf '%s\n' "$staged_files" | wc -l | tr -d ' ')
                if is_folded staged; then
                    emit "## Staged changes ($scount) …" staged
                    emit "" blank
                else
                emit "## Staged changes ($scount)" staged
                OLD_IFS=$IFS; IFS='
'
                for f in $staged_files; do
                    if is_folded "staged:$f"; then
                        emit "  ## $f …" staged "$f"
                        continue
                    fi
                    emit "  ## $f" staged "$f"
                    diff_tmp=$(mktemp "${TMPDIR:-/tmp}/magit-diff.XXXXXX")
                    git diff --cached --no-color -- "$f" | awk '
                        /^diff --git/ {skip=1; next}
                        /^index / && skip {next}
                        /^--- /  && skip {next}
                        /^\+\+\+/ && skip {skip=0; next}
                        {print}
                    ' > "$diff_tmp"
                    cur=0
                    IFS_INNER=$IFS; IFS=''
                    while IFS= read -r line || [ -n "$line" ]; do
                        case "$line" in
                            @@*)
                                newstart=$(printf '%s' "$line" | sed -n 's/.*+\([0-9][0-9]*\).*/\1/p')
                                [ -z "$newstart" ] && newstart=0
                                emit "    $line" "staged-hunk" "$f" "$newstart"
                                cur=$newstart
                                ;;
                            +*) emit "    $line" "staged-line" "$f" "$cur"; cur=$((cur+1)) ;;
                            -*) emit "    $line" "staged-line" "$f" "$cur" ;;
                            *)  emit "    $line" "staged-ctx"  "$f" "$cur"; cur=$((cur+1)) ;;
                        esac
                    done < "$diff_tmp"
                    IFS=$IFS_INNER
                    rm -f "$diff_tmp"
                done
                IFS=$OLD_IFS
                emit "" blank
                fi
            fi

            # Stashes
            stash_tmp="${tmp}.stash"
            git stash list --format='%gd %s' 2>/dev/null > "$stash_tmp"
            if [ -s "$stash_tmp" ]; then
                stash_count=$(wc -l < "$stash_tmp" | tr -d ' ')
                if is_folded stash; then
                    emit "## Stashes ($stash_count) …" stash
                else
                    emit "## Stashes ($stash_count)" stash
                    OLD_IFS=$IFS; IFS=''
                    while IFS= read -r l || [ -n "$l" ]; do
                        ref=${l%% *}   # e.g. stash@{0}
                        emit "  $l" stash-entry "$ref"
                    done < "$stash_tmp"
                    IFS=$OLD_IFS
                fi
                emit "" blank
            fi
            rm -f "$stash_tmp"

            # Unpulled / Unpushed — only when an upstream is configured.
            upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)
            if [ -n "$upstream" ]; then
                unpulled_tmp="${tmp}.unpulled"
                git log --no-color --pretty='%h %s' "HEAD..$upstream" 2>/dev/null > "$unpulled_tmp"
                if [ -s "$unpulled_tmp" ]; then
                    up_count=$(wc -l < "$unpulled_tmp" | tr -d ' ')
                    if is_folded unpulled; then
                        emit "## Unpulled from $upstream ($up_count) …" unpulled
                    else
                        emit "## Unpulled from $upstream ($up_count)" unpulled
                        OLD_IFS=$IFS; IFS=''
                        while IFS= read -r l || [ -n "$l" ]; do
                            sha=${l%% *}
                            emit "  $l" unpulled-commit "$sha"
                        done < "$unpulled_tmp"
                        IFS=$OLD_IFS
                    fi
                    emit "" blank
                fi
                rm -f "$unpulled_tmp"

                unpushed_tmp="${tmp}.unpushed"
                git log --no-color --pretty='%h %s' "$upstream..HEAD" 2>/dev/null > "$unpushed_tmp"
                if [ -s "$unpushed_tmp" ]; then
                    up2_count=$(wc -l < "$unpushed_tmp" | tr -d ' ')
                    if is_folded unpushed; then
                        emit "## Unpushed to $upstream ($up2_count) …" unpushed
                    else
                        emit "## Unpushed to $upstream ($up2_count)" unpushed
                        OLD_IFS=$IFS; IFS=''
                        while IFS= read -r l || [ -n "$l" ]; do
                            sha=${l%% *}
                            emit "  $l" unpushed-commit "$sha"
                        done < "$unpushed_tmp"
                        IFS=$OLD_IFS
                    fi
                    emit "" blank
                fi
                rm -f "$unpushed_tmp"
            fi

            # Recent commits (last 10). Each entry stores "<sha> <subject>" as
            # the "file" slot so magit-visit-at-cursor can open the commit.
            # Skip the whole section in an empty repo (git log has nothing
            # to say; emitting a bare header looks broken).
            git log -10 --pretty='%h %s' 2>/dev/null > "${tmp}.log"
            if [ -s "${tmp}.log" ]; then
                if is_folded recent; then
                    emit "## Recent commits …" recent
                else
                    emit "## Recent commits" recent
                    OLD_IFS=$IFS; IFS=''
                    while IFS= read -r l || [ -n "$l" ]; do
                        sha=${l%% *}
                        emit "  $l" recent-commit "$sha"
                    done < "${tmp}.log"
                    IFS=$OLD_IFS
                fi
            fi
            rm -f "${tmp}.log"

            # Strip trailing whitespace from every line of the rendered
            # tempfile. Users commonly have a global `show-whitespaces
            # -only-trailing` highlighter (e.g. in kakrc) which would
            # render dots / pipes on diff-context lines that carry trailing
            # blanks — visual noise in the status buffer.
            sed -i.bak 's/[[:space:]]*$//' "$tmp" && rm -f "$tmp.bak"

            # Emit the kakscript to load buffer contents and linemap.
            # 1) Replace buffer with tempfile contents.
            # 2) Load linemap into the option as a str-list.
            #    str-list is colon-separated in option syntax, and each entry
            #    needs kak-quoting. The safest path: set the option via
            #    `set-option ... %file{path}` — but %file isn't supported for
            #    str-list population directly. Instead, we build the option
            #    value as a single kak-quoted str-list using %arg tokens.
            printf 'execute-keys %%{%%|cat %s<ret>}\n' "$tmp"

            # Convert map entries to a kak str-list set-option.
            # Each entry becomes a percent-braced token. We build the brace
            # chars via printf-escape so they do not appear literally in this
            # shell body — kak counts braces in the enclosing percent-sh
            # block and a stray char would close it early. Phase 1 assumes
            # linemap values themselves never contain brace chars.
            OB=$(printf '\173')
            CB=$(printf '\175')
            printf 'set-option buffer magit_status_linemap'
            while IFS= read -r entry; do
                printf ' %%%s%s%s' "$OB" "$entry" "$CB"
            done < "$map"
            printf '\n'

            printf 'nop %%sh{ rm -f %s %s }\n' "$tmp" "$map"
        }
        # Collapse the whole-buffer selection left over from `%|cat ...` AND
        # jump to line 1 so the viewport starts at the top.
        # `gg` goes to buffer start AND collapses the selection to one char.
        execute-keys 'gg'
        # Restore cursor by finding the first buffer-line whose linemap entry
        # matches the one we saved (register a). Falls back to line 1 if the
        # old entry no longer exists (e.g. the file was staged away).
        magit-status-restore-cursor %reg{a}
    }
    set-option buffer magit_in_refresh false
}

define-command -hidden magit-status-restore-cursor -params 1 %{
    evaluate-commands %sh{
        target=$1
        [ -z "$target" ] || [ "$target" = 'blank||0' ] && exit 0
        eval "set -- $kak_quoted_opt_magit_status_linemap"
        line=0
        idx=0
        for e; do
            idx=$((idx+1))
            if [ "$e" = "$target" ]; then
                line=$idx
                break
            fi
        done
        # If exact match not found, try looser match on section+file (file may
        # now be staged/unstaged etc. — target line inside the file is gone).
        if [ $line -eq 0 ]; then
            tsec=${target%%|*}
            tsec_prefix=${tsec%%-*}
            rest=${target#*|}
            tfile=${rest%%|*}
            if [ -n "$tfile" ]; then
                idx=0
                for e; do
                    idx=$((idx+1))
                    efile=$(printf '%s' "$e" | cut -d'|' -f2)
                    esec=$(printf '%s' "$e" | cut -d'|' -f1)
                    esec_prefix=${esec%%-*}
                    if [ "$efile" = "$tfile" ] && [ "$esec_prefix" = "$tsec_prefix" ]; then
                        line=$idx
                        break
                    fi
                done
            fi
        fi
        if [ $line -gt 0 ]; then
            printf 'execute-keys %%{%dg}\n' "$line"
        fi
    }
}

# Resolve the linemap entry at cursor into a register.
# Usage: magit-at-cursor <reg>
# Register is set to "section|file|file_line"; if cursor is past the linemap
# bounds, the register is set to "blank||0".
define-command -hidden magit-at-cursor -params 1 %{
    evaluate-commands %sh{
        # Build brace chars via printf-escape so this shell body keeps its
        # braces balanced from kak-s perspective (kak counts braces when
        # parsing percent-sh blocks).
        OB=$(printf '\173')
        CB=$(printf '\175')
        # kak exposes str-list options two ways: $kak_opt_NAME (raw, joined
        # by spaces — lossy if entries contain spaces) and
        # $kak_quoted_opt_NAME (each entry single-quoted so eval-set-- works
        # correctly). We use the quoted form.
        idx=$kak_cursor_line
        # The register arg $1 is NOT a shell $1 here because we are inside
        # a percent-sh block invoked as a define-command-with-params; kak
        # passes params via $1..$n — they clobber shell positional. Capture
        # it before the set-- call below.
        reg=$1
        eval "set -- $kak_quoted_opt_magit_status_linemap"
        if [ "$idx" -le "$#" ] && [ "$idx" -ge 1 ]; then
            eval "entry=\${$idx}"
            printf 'set-register %s %%%s%s%s' "$reg" "$OB" "$entry" "$CB"
        else
            printf 'set-register %s %%%sblank||0%s' "$reg" "$OB" "$CB"
        fi
    }
}

# --- Dispatchers: stage / unstage / discard / visit --------------------
# Each takes the linemap entry as a single "section|file|file_line" string.
# Hunk-section entries (unstaged-hunk / staged-hunk) route to Task 6b's
# magit-do-stage-hunk. Line/ctx entries without a region fall to the hunk
# case for Phase 1.

define-command -hidden magit-do-stage -params 1 %{
    evaluate-commands %sh{
        entry=$1
        section=${entry%%|*}; rest=${entry#*|}
        file=${rest%%|*}
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null) || {
            echo "echo -markup {Error}magit-do-stage: not in a git repository"
            exit
        }
        cd "$toplevel"
        case "$section" in
            unstaged)
                if [ -n "$file" ]; then
                    git add -- "$file" && echo "echo -markup {Information}staged $file"
                else
                    git add -u && echo "echo -markup {Information}staged all unstaged"
                fi ;;
            untracked)
                if [ -n "$file" ]; then
                    git add -- "$file" && echo "echo -markup {Information}tracked $file"
                else
                    git ls-files --others --exclude-standard | xargs -I{} git add -- '{}' \
                       && echo "echo -markup {Information}tracked all untracked"
                fi ;;
            staged|staged-hunk|staged-line|staged-ctx)
                echo "echo -markup {Information}already staged" ;;
            unstaged-hunk|unstaged-line|unstaged-ctx)
                # Route to Task 6b hunk stager (defined below).
                echo "magit-do-stage-hunk stage" ;;
            head|recent|recent-commit|stash|stash-entry|unpulled|unpulled-commit|unpushed|unpushed-commit|rebase-progress|rebase-todo-line|worktree|worktree-entry|submodule|submodule-entry|bisect-progress|blank)
                echo "echo -markup {Information}nothing to stage at cursor" ;;
            *)
                echo "echo -markup {Information}no stage action for section: $section" ;;
        esac
    }
    magit-refresh-after-mutation
}

define-command -hidden magit-do-unstage -params 1 %{
    evaluate-commands %sh{
        entry=$1
        section=${entry%%|*}; rest=${entry#*|}
        file=${rest%%|*}
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null) || exit
        cd "$toplevel"
        case "$section" in
            staged)
                if [ -n "$file" ]; then
                    git reset HEAD -- "$file" >/dev/null \
                        && echo "echo -markup {Information}unstaged $file"
                else
                    git reset HEAD >/dev/null \
                        && echo "echo -markup {Information}unstaged all staged"
                fi ;;
            staged-hunk|staged-line|staged-ctx)
                echo "magit-do-stage-hunk unstage" ;;
            unstaged|unstaged-hunk|unstaged-line|unstaged-ctx|untracked)
                echo "echo -markup {Information}already unstaged" ;;
            *)
                echo "echo -markup {Information}no unstage action for section: $section" ;;
        esac
    }
    magit-refresh-after-mutation
}

# magit-reverse: reverse-apply a staged diff (file or hunk) to the worktree.
# Source = `git diff --cached` (index vs HEAD), apply = `git apply -R` with
# NO --cached flag — the reverse lands in the worktree, leaving the index
# untouched. Use case: "staged a refactor, want to test the pre-refactor
# code locally without unstaging." Unstaged targets have no corresponding
# reverse operation (the worktree IS the diff); those land on the
# "nothing to reverse" info branch.
define-command -hidden magit-do-reverse -params 1 %{
    evaluate-commands %sh{
        entry=$1
        section=${entry%%|*}; rest=${entry#*|}
        file=${rest%%|*}
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null) || {
            echo "fail 'magit-reverse: not in a git repository'"
            exit
        }
        cd "$toplevel"
        OB=$(printf '\173'); CB=$(printf '\175')
        case "$section" in
            staged)
                # Plain `git apply -R` requires the worktree's 3-line
                # context around each hunk to match the patch. If the file
                # has an UNSTAGED edit layered on top of the staged one,
                # that context may not match — git refuses with `patch
                # failed`. We can't fix this without either clobbering the
                # unstaged edits (bad) or conflict-marking (surprising).
                # Instead: detect the dirty-stacked case via
                # `git diff --name-only` (unstaged changes list) ∩ target
                # files, and surface a clearer error pointing at the real
                # issue. User's recourse: stash the unstaged edits first.
                if [ -z "$file" ]; then
                    patch=$(git diff --cached --no-color 2>/dev/null)
                    if [ -z "$patch" ]; then
                        echo "echo -markup {Information}nothing staged to reverse"
                        exit
                    fi
                    staged_files=$(git diff --cached --name-only 2>/dev/null)
                    dirty_stack=""
                    for sf in $staged_files; do
                        if ! git diff --quiet -- "$sf" 2>/dev/null; then
                            dirty_stack="$dirty_stack $sf"
                        fi
                    done
                    if [ -n "$dirty_stack" ]; then
                        printf "fail 'magit-reverse: refusing — these files have unstaged edits on top of staged:%s  (stash or discard unstaged first)'\n" "$dirty_stack"
                        exit
                    fi
                    if printf '%s\n' "$patch" | git apply -R 2>/tmp/magit-reverse.err; then
                        echo "echo -markup {Information}reversed all staged (worktree updated)"
                    else
                        err=$(head -1 /tmp/magit-reverse.err 2>/dev/null | tr -d "'\"")
                        [ -z "$err" ] && err="git apply -R failed"
                        printf "fail 'magit-reverse: %s'\n" "$err"
                    fi
                    rm -f /tmp/magit-reverse.err
                else
                    patch=$(git diff --cached --no-color -- "$file" 2>/dev/null)
                    if [ -z "$patch" ]; then
                        printf "echo -markup %s Information%s %s has no staged changes to reverse%s\n" \
                            "$OB" "$CB" "$file" ""
                        exit
                    fi
                    if ! git diff --quiet -- "$file" 2>/dev/null; then
                        printf "fail 'magit-reverse: %s has unstaged edits on top of staged — stash or discard unstaged first'\n" "$file"
                        exit
                    fi
                    if printf '%s\n' "$patch" | git apply -R 2>/tmp/magit-reverse.err; then
                        printf "echo -markup %sInformation%sreversed staged %s in worktree\n" \
                            "$OB" "$CB" "$file"
                    else
                        err=$(head -1 /tmp/magit-reverse.err 2>/dev/null | tr -d "'\"")
                        [ -z "$err" ] && err="git apply -R failed"
                        printf "fail 'magit-reverse: %s'\n" "$err"
                    fi
                    rm -f /tmp/magit-reverse.err
                fi ;;
            staged-hunk|staged-line|staged-ctx)
                # Route to hunk-level reverse (defined below).
                echo "magit-do-reverse-hunk" ;;
            unstaged|unstaged-hunk|unstaged-line|unstaged-ctx|untracked)
                echo "echo -markup {Information}nothing to reverse (target is unstaged; use discard instead)" ;;
            *)
                echo "echo -markup {Information}no reverse action for section: $section" ;;
        esac
    }
    magit-refresh-after-mutation
}

define-command -hidden magit-do-discard -params 1 %{
    evaluate-commands %sh{
        entry=$1
        section=${entry%%|*}; rest=${entry#*|}
        file=${rest%%|*}
        OB=$(printf '\173')
        CB=$(printf '\175')
        case "$section" in
            unstaged)
                if [ -n "$file" ]; then
                    printf 'magit-confirm-discard unstaged %%%s%s%s\n' "$OB" "$file" "$CB"
                else
                    # Section heading: discard all unstaged.
                    printf 'magit-confirm-discard unstaged-all %%%sall%s\n' "$OB" "$CB"
                fi ;;
            untracked)
                if [ -n "$file" ]; then
                    printf 'magit-confirm-discard untracked %%%s%s%s\n' "$OB" "$file" "$CB"
                else
                    # Section heading: delete all untracked.
                    printf 'magit-confirm-discard untracked-all %%%sall%s\n' "$OB" "$CB"
                fi ;;
            stash-entry)
                # "file" slot carries the stash ref. Confirm-then-drop.
                if [ -n "$file" ]; then
                    printf "magit-confirm-discard stash '%s'\n" "$file"
                else
                    echo "echo -markup {Information}no stash ref at cursor"
                fi ;;
            *)
                echo "echo -markup {Information}no discard target at cursor" ;;
        esac
    }
}

# Confirmation prompt for destructive discards.
# $1 = "unstaged" or "untracked"
# $2 = filename
# Pass filename via register so the prompt body doesn't need to shell-escape it.
define-command -hidden magit-confirm-discard -params 2 %{
    set-option global magit_discard_kind %arg{1}
    set-option global magit_discard_file %arg{2}
    evaluate-commands %sh{
        case "$1" in
            unstaged)      msg="Discard unstaged changes to $2? (y/N): " ;;
            untracked)     msg="Delete untracked file $2? (y/N): " ;;
            stash)         msg="Drop stash $2? (y/N): " ;;
            unstaged-all)
                count=$(git diff --name-only | wc -l | tr -d ' ')
                msg="Discard ALL ${count} unstaged changes? (y/N): "
                ;;
            untracked-all)
                count=$(git ls-files --others --exclude-standard | wc -l | tr -d ' ')
                msg="Delete ALL ${count} untracked files? (y/N): "
                ;;
        esac
        OB=$(printf '\173')
        CB=$(printf '\175')
        printf 'prompt %%%s%s%s magit-confirm-discard-apply\n' "$OB" "$msg" "$CB"
    }
}

declare-option -hidden str magit_discard_kind
declare-option -hidden str magit_discard_file

# Called after the prompt resolves. Reads %val{text} (user's response) plus
# the stored kind/file options, and applies the destructive op on 'y'/'Y'.
define-command -hidden magit-confirm-discard-apply %{
    evaluate-commands %sh{
        ans=$kak_text
        kind=$kak_opt_magit_discard_kind
        file=$kak_opt_magit_discard_file
        case "$ans" in
            y|Y)
                toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
                if [ -z "$toplevel" ]; then
                    echo "fail 'magit-discard: not in a git worktree'"
                    exit
                fi
                case "$kind" in
                    unstaged)
                        ( cd "$toplevel" && git checkout -- "$file" ) \
                            && echo "echo -markup {Information}discarded $file" \
                            || echo "fail 'magit-discard: git checkout failed'"
                        ;;
                    untracked)
                        ( cd "$toplevel" && rm -f -- "$file" ) \
                            && echo "echo -markup {Information}deleted $file" \
                            || echo "fail 'magit-discard: rm failed'"
                        ;;
                    unstaged-all)
                        # `git checkout -- .` reverts every tracked file.
                        ( cd "$toplevel" && git checkout -- . ) \
                            && echo "echo -markup {Information}discarded all unstaged" \
                            || echo "fail 'magit-discard-all: git checkout failed'"
                        ;;
                    untracked-all)
                        # Enumerate + rm each untracked path (paths may contain spaces).
                        (
                            cd "$toplevel"
                            git ls-files --others --exclude-standard -z \
                                | xargs -0 rm -f --
                        ) && echo "echo -markup {Information}deleted all untracked" \
                          || echo "fail 'magit-discard-all: rm failed'"
                        ;;
                    stash)
                        ( cd "$toplevel" && git stash drop "$file" >/dev/null 2>&1 ) \
                            && printf 'echo -markup %%{{Information}dropped %s}\n' "$file" \
                            || printf "fail 'magit-discard: git stash drop %s failed'\n" "$file"
                        ;;
                esac
                echo 'magit-refresh-after-mutation'
                ;;
            *)
                echo "echo -markup {Information}discard cancelled"
                ;;
        esac
    }
}

define-command -hidden magit-stage-at-cursor %{
    evaluate-commands -save-regs m %{
        magit-at-cursor m
        magit-do-stage %reg{m}
    }
}
define-command -hidden magit-unstage-at-cursor %{
    evaluate-commands -save-regs m %{
        magit-at-cursor m
        magit-do-unstage %reg{m}
    }
}
define-command -hidden magit-discard-at-cursor %{
    evaluate-commands -save-regs m %{
        magit-at-cursor m
        magit-do-discard %reg{m}
    }
}
define-command -hidden magit-reverse-at-cursor %{
    evaluate-commands -save-regs m %{
        magit-at-cursor m
        magit-do-reverse %reg{m}
    }
}

# Visit source file at the cursor's linemap entry.
define-command -hidden magit-visit-at-cursor %{
    evaluate-commands -save-regs m %{
        magit-at-cursor m
        evaluate-commands %sh{
            entry=$kak_reg_m
            section=${entry%%|*}
            rest=${entry#*|}
            file=${rest%%|*}; fline=${rest#*|}
            OB=$(printf '\173'); CB=$(printf '\175')
            case "$section" in
                stash-entry)
                    # "file" slot carries the stash ref (e.g. stash@(0)).
                    # Single-quote the arg because the ref contains braces.
                    if [ -z "$file" ]; then
                        echo "echo -markup {Information}no stash ref"
                        exit
                    fi
                    printf "magit-show-stash '%s'\n" "$file"
                    ;;
                recent-commit|unpulled-commit|unpushed-commit)
                    # "file" slot carries the short sha.
                    if [ -z "$file" ]; then
                        echo "echo -markup {Information}no sha"
                        exit
                    fi
                    printf "magit-show-commit %s\n" "$file"
                    ;;
                *)
                    if [ -n "$file" ]; then
                        toplevel=$(git rev-parse --show-toplevel)
                        if [ "$fline" != 0 ] && [ -n "$fline" ]; then
                            printf 'edit -existing -- %%%s%s/%s%s %s\n' \
                                "$OB" "$toplevel" "$file" "$CB" "$fline"
                        else
                            printf 'edit -existing -- %%%s%s/%s%s\n' \
                                "$OB" "$toplevel" "$file" "$CB"
                        fi
                    else
                        echo "echo -markup {Information}no file at cursor"
                    fi
                    ;;
            esac
        }
    }
}

# --- Stash actions ------------------------------------------------------
# Dispatch from the cursor's linemap entry; only act when on a stash-entry.
# apply: leaves the stash in the list. pop: applies + drops.
# drop-without-apply is wired through magit-do-discard's dispatch further
# below so <a-k>/K "remove this thing" behavior stays uniform across sections.

define-command -hidden magit-stash-apply -docstring 'apply stash at cursor' %{
    evaluate-commands -save-regs m %{
        magit-at-cursor m
        magit-stash-apply-or-pop %reg{m} apply
    }
}

define-command -hidden magit-stash-pop -docstring 'pop stash at cursor' %{
    evaluate-commands -save-regs m %{
        magit-at-cursor m
        magit-stash-apply-or-pop %reg{m} pop
    }
}

# $1 = linemap entry "section|file|file_line", $2 = apply|pop
define-command -hidden -params 2 magit-stash-apply-or-pop %{
    evaluate-commands %sh{
        entry=$1
        action=$2
        section=${entry%%|*}
        rest=${entry#*|}
        ref=${rest%%|*}
        if [ "$section" != "stash-entry" ] || [ -z "$ref" ]; then
            echo "echo -markup {Information}no stash at cursor"
            exit
        fi
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
        [ -z "$toplevel" ] && { echo "fail 'not in a git repo'"; exit; }
        err=$(mktemp "${TMPDIR:-/tmp}/magit-stash-err.XXXXXX")
        if ( cd "$toplevel" && git stash "$action" "$ref" >/dev/null 2>"$err" ); then
            printf 'echo -markup %%{{Information}stash %s %s}\n' "$action" "$ref"
            rm -f "$err"
        else
            reason=$(grep -E '^(error|fatal|CONFLICT):' "$err" | head -1 | sed 's/^[[:space:]]*//')
            [ -z "$reason" ] && reason=$(head -1 "$err")
            [ -z "$reason" ] && reason="git stash $action exited non-zero"
            reason=$(printf '%s' "$reason" | tr -d "'")
            printf "fail 'stash %s failed: %s'\n" "$action" "$reason"
            rm -f "$err"
        fi
    }
    magit-refresh-after-mutation
}

# --- Hunk-level staging -------------------------------------------------
# $1 = "stage" (apply to index) or "unstage" (reverse from index).
# Strategy: look up the current cursor entry; walk the linemap backward to
# the containing hunk header; walk forward to the end of that hunk; re-run
# `git diff` on the file (staged or unstaged side) to get the authoritative
# diff text; isolate the specific hunk by its target-file starting line
# (recorded in the linemap at render time); pipe with proper headers into
# `git apply --cached` or `git apply --cached -R`.
define-command -hidden magit-do-stage-hunk -params 1 %{
    evaluate-commands %sh{
        direction=$1
        # Find our containing hunk start + file from the linemap at cursor.
        eval "set -- $kak_quoted_opt_magit_status_linemap"
        cur=$kak_cursor_line
        # Walk backward to nearest *-hunk entry sharing our cursor prefix.
        file=""
        hunk_file_line=""
        prefix=""
        i=$cur
        while [ $i -ge 1 ]; do
            eval "e=\${$i}"
            esec=${e%%|*}; rest=${e#*|}
            efile=${rest%%|*}; eline=${rest#*|}
            case "$esec" in
                unstaged-hunk)
                    file=$efile; hunk_file_line=$eline; prefix=unstaged; break ;;
                staged-hunk)
                    file=$efile; hunk_file_line=$eline; prefix=staged; break ;;
                unstaged|untracked|staged|head|recent|recent-commit|stash|stash-entry|unpulled|unpulled-commit|unpushed|unpushed-commit|rebase-progress|rebase-todo-line|worktree|worktree-entry|submodule|submodule-entry|bisect-progress|blank)
                    # crossed section boundary without finding a hunk header
                    break ;;
            esac
            i=$((i-1))
        done
        if [ -z "$file" ]; then
            echo "echo -markup {Information}no hunk at cursor"
            exit
        fi

        # Validate direction vs. prefix.
        case "$direction:$prefix" in
            stage:unstaged)   apply_args="--cached" ;;
            unstage:staged)   apply_args="--cached -R" ;;
            *)
                echo "echo -markup {Information}$direction not applicable at this hunk"
                exit ;;
        esac

        toplevel=$(git rev-parse --show-toplevel)
        cd "$toplevel"

        # Source diff: for stage path, use worktree diff; for unstage, use
        # cached diff. Both produce hunk headers of the form `@@ -A,B +C,D @@`.
        case "$prefix" in
            unstaged) diff_src="git diff --no-color -- $(printf '%s' "$file" | sed 's/[[:space:]]/\\&/g')" ;;
            staged)   diff_src="git diff --cached --no-color -- $(printf '%s' "$file" | sed 's/[[:space:]]/\\&/g')" ;;
        esac

        # Awk: scan diff hunks; when we find the one whose `+START` matches
        # our recorded hunk_file_line, emit that hunk (header + body) until
        # the next `@@` or end. Skip the `diff --git`/`index`/`---`/`+++`
        # preamble; we'll reconstruct the minimal headers ourselves.
        hunk=$(eval $diff_src | awk -v target="$hunk_file_line" '
            BEGIN { out=0 }
            /^@@ / {
                # Parse +START from the @@ header
                if (match($0, /\+[0-9]+/)) {
                    s = substr($0, RSTART+1, RLENGTH-1) + 0
                    if (s == target) { out=1; print; next }
                    else if (out) { exit }
                    else { out=0; next }
                }
            }
            out && /^(diff --git|index |--- |\+\+\+ )/ { exit }
            out { print }
        ')

        if [ -z "$hunk" ]; then
            echo "echo -markup {Error}could not isolate hunk for $file at line $hunk_file_line"
            exit
        fi

        # Build a minimal valid patch: diff --git + --- + +++ + the hunk.
        patch_tmp=$(mktemp "${TMPDIR:-/tmp}/magit-hunk.XXXXXX")
        {
            printf 'diff --git a/%s b/%s\n' "$file" "$file"
            printf -- '--- a/%s\n' "$file"
            printf -- '+++ b/%s\n' "$file"
            printf '%s\n' "$hunk"
        } > "$patch_tmp"

        if git apply $apply_args < "$patch_tmp" 2>/tmp/magit-apply.err; then
            verb=$direction
            echo "echo -markup {Information}${verb}d hunk in $file"
        else
            err=$(cat /tmp/magit-apply.err 2>/dev/null | head -1)
            # Escape single-quotes for the echo command below
            esc_err=$(printf '%s' "$err" | sed "s/'/''/g")
            printf "echo -markup %%%sError%s git apply failed: %s%s\n" \
                "$(printf '\173')" "$(printf '\175')" "$esc_err" ""
        fi
        rm -f "$patch_tmp"
    }
    magit-refresh-after-mutation
}

# magit-do-reverse-hunk: isolate the staged hunk at cursor and reverse-apply
# it to the WORKTREE (no --cached). Only meaningful when cursor is on a
# staged-hunk / staged-line / staged-ctx entry; caller (`magit-do-reverse`)
# already filtered for that.
define-command -hidden magit-do-reverse-hunk %{
    evaluate-commands %sh{
        eval "set -- $kak_quoted_opt_magit_status_linemap"
        cur=$kak_cursor_line
        file=""
        hunk_file_line=""
        i=$cur
        while [ $i -ge 1 ]; do
            eval "e=\${$i}"
            esec=${e%%|*}; rest=${e#*|}
            efile=${rest%%|*}; eline=${rest#*|}
            case "$esec" in
                staged-hunk)
                    file=$efile; hunk_file_line=$eline; break ;;
                unstaged|untracked|staged|unstaged-hunk|head|recent|recent-commit|stash|stash-entry|unpulled|unpulled-commit|unpushed|unpushed-commit|rebase-progress|rebase-todo-line|worktree|worktree-entry|submodule|submodule-entry|bisect-progress|blank)
                    break ;;
            esac
            i=$((i-1))
        done
        if [ -z "$file" ]; then
            echo "echo -markup {Information}no staged hunk at cursor"
            exit
        fi

        toplevel=$(git rev-parse --show-toplevel)
        cd "$toplevel"

        diff_src="git diff --cached --no-color -- $(printf '%s' "$file" | sed 's/[[:space:]]/\\&/g')"
        hunk=$(eval $diff_src | awk -v target="$hunk_file_line" '
            BEGIN { out=0 }
            /^@@ / {
                if (match($0, /\+[0-9]+/)) {
                    s = substr($0, RSTART+1, RLENGTH-1) + 0
                    if (s == target) { out=1; print; next }
                    else if (out) { exit }
                    else { out=0; next }
                }
            }
            out && /^(diff --git|index |--- |\+\+\+ )/ { exit }
            out { print }
        ')
        if [ -z "$hunk" ]; then
            echo "echo -markup {Error}could not isolate staged hunk for $file at line $hunk_file_line"
            exit
        fi

        patch_tmp=$(mktemp "${TMPDIR:-/tmp}/magit-reverse-hunk.XXXXXX")
        {
            printf 'diff --git a/%s b/%s\n' "$file" "$file"
            printf -- '--- a/%s\n' "$file"
            printf -- '+++ b/%s\n' "$file"
            printf '%s\n' "$hunk"
        } > "$patch_tmp"

        # Refuse if the target file has unstaged edits on top — same rule
        # as magit-do-reverse (whole-file). Stacking an unstaged edit over
        # a staged hunk means `git apply -R`'s 3-line context won't match.
        if ! git diff --quiet -- "$file" 2>/dev/null; then
            printf "fail 'magit-reverse-hunk: %s has unstaged edits on top of staged — stash or discard unstaged first'\n" "$file"
            rm -f "$patch_tmp"
            exit
        fi

        if git apply -R < "$patch_tmp" 2>/tmp/magit-reverse.err; then
            echo "echo -markup {Information}reversed staged hunk in $file (worktree updated)"
        else
            # Emit via `fail '<msg>'` not `echo -markup`: markup bodies
            # re-parse stray words as kakscript commands, so a git error
            # like "patch does not apply, use --3way" would trigger
            # `'use': no such command` on re-parse. fail takes a plain
            # quoted string — no re-parse. Strip both ' and " from the
            # error to avoid breaking the single-quote wrapper.
            err=$(head -1 /tmp/magit-reverse.err 2>/dev/null | tr -d "'\"")
            [ -z "$err" ] && err="git apply -R failed"
            printf "fail 'magit-reverse-hunk: %s'\n" "$err"
        fi
        rm -f "$patch_tmp" /tmp/magit-reverse.err
    }
    magit-refresh-after-mutation
}


# --- Fold persistence ---------------------------------------------------
# State lives in `<git-dir>/magit-folds` as a single line (the exact value
# of magit_status_collapsed). Missing file => option cleared, so switching
# between repos in one kak session loads each repo's own folds.
define-command -hidden magit-status-folds-load %{
    evaluate-commands %sh{
        gitdir=$(git rev-parse --git-dir 2>/dev/null)
        [ -n "$gitdir" ] || { printf "set-option global magit_status_collapsed ''\n"; exit; }
        case "$gitdir" in /*) ;; *) gitdir="$(pwd)/$gitdir" ;; esac
        f="$gitdir/magit-folds"
        if [ -f "$f" ]; then
            # Single line; strip trailing newline. Stray single-quotes in
            # file names would be surprising, but guard anyway.
            val=$(head -1 "$f" | tr -d "'")
        else
            val=""
        fi
        OB=$(printf '\173')
        CB=$(printf '\175')
        printf 'set-option global magit_status_collapsed %%%s%s%s\n' "$OB" "$val" "$CB"
    }
}

define-command -hidden magit-status-folds-save %{
    evaluate-commands %sh{
        gitdir=$(git rev-parse --git-dir 2>/dev/null)
        [ -n "$gitdir" ] || exit
        case "$gitdir" in /*) ;; *) gitdir="$(pwd)/$gitdir" ;; esac
        f="$gitdir/magit-folds"
        # Empty option: remove the file so a fresh kak session starts clean.
        if [ -z "$kak_opt_magit_status_collapsed" ]; then
            rm -f "$f"
        else
            printf '%s\n' "$kak_opt_magit_status_collapsed" > "$f"
        fi
    }
}

# --- Folding ------------------------------------------------------------
# Toggle collapse state for the section at cursor. Per-file folding (a
# diff inside unstaged/staged) is out of scope for v1; only top-level
# section kinds are foldable: head, untracked, unstaged, staged, stash,
# unpulled, unpushed, recent, rebase-progress.
define-command -hidden magit-status-fold-toggle %{
    evaluate-commands -save-regs a %{
        try %{ magit-at-cursor a } catch %{ set-register a 'blank||0' }
        evaluate-commands %sh{
            entry=$kak_reg_a
            section=${entry%%|*}; rest=${entry#*|}
            file=${rest%%|*}
            # Map nested kinds back to their top-level section so TAB on a
            # body line folds the enclosing section.
            case "$section" in
                unstaged-hunk|unstaged-line|unstaged-ctx) section=unstaged ;;
                staged-hunk|staged-line|staged-ctx)       section=staged ;;
                stash-entry)     section=stash ;;
                unpulled-commit) section=unpulled ;;
                unpushed-commit) section=unpushed ;;
                recent-commit)   section=recent ;;
                rebase-todo-line) section=rebase-progress ;;
                worktree-entry)  section=worktree ;;
                submodule-entry) section=submodule ;;
            esac
            case "$section" in
                head|untracked|unstaged|staged|stash|unpulled|unpushed|recent|rebase-progress|worktree|submodule|bisect-progress) ;;
                *)
                    echo "echo -markup '{Information}no foldable section at cursor'"
                    exit
                    ;;
            esac
            # Per-file precedence: unstaged/staged with a non-empty file slot
            # folds just that file. Cursor on the top-level section header
            # (file slot empty) falls through to section-level fold.
            target=$section
            case "$section" in
                unstaged|staged)
                    [ -n "$file" ] && target="$section:$file"
                    ;;
            esac
            cur=$kak_opt_magit_status_collapsed
            new=""
            found=0
            for tok in $cur; do
                if [ "$tok" = "$target" ]; then
                    found=1
                    continue
                fi
                new="$new $tok"
            done
            new=${new# }
            if [ $found -eq 0 ]; then
                if [ -z "$new" ]; then new=$target; else new="$new $target"; fi
            fi
            OB=$(printf '\173')
            CB=$(printf '\175')
            printf 'set-option global magit_status_collapsed %%%s%s%s\n' "$OB" "$new" "$CB"
        }
        magit-status-folds-save
        magit-status-render
    }
}

# --- Section nav --------------------------------------------------------
# Section headings: `##` possibly preceded by whitespace (indented file heads).
# n / p / parent key on this one pattern. kak's `/` and `<a-/>` search forward
# and backward; a match ON the current line is skipped when the cursor is
# exactly at its start, so plain `/` advances to the next heading.
define-command -hidden magit-next-section %{
    try %{ execute-keys '/^\h*##<ret>' }
}
define-command -hidden magit-prev-section %{
    try %{ execute-keys '<a-/>^\h*##<ret>' }
}
# Parent: nearest preceding top-level (un-indented) heading.
define-command -hidden magit-parent-section %{
    try %{ execute-keys '<a-/>^##<ret>' }
}

# --- Status-jump menu ---------------------------------------------------
# `t` in *magit-status* enters magit-status-jump. One key per top-level
# section; search fails silently (no-op, cursor unchanged) if the section
# isn't rendered on the current state (e.g. no Staged when nothing staged).
# Section headings always start at column 0 as `## <Title>`, so a
# literal `/^## <prefix>` search hits the heading reliably.
define-command -hidden magit-status-jump-to -params 1 %{
    # Stash the search pattern in the `/` register, then `ggn` to find
    # the earliest match. Why not `execute-keys "%s^## %arg{1}<ret>"`?
    # `execute-keys` splits its STRING args on whitespace into separate
    # key-sequence args, so multi-word titles like "Untracked files"
    # become two args parsed as garbage keystrokes (`U`, `n`, `t`, ...).
    # Register-then-`n` avoids the arg-split trap (same family as
    # Lesson #37 for regexes containing `<`).
    #
    # We probe first with -draft: if the regex doesn't match, `n`
    # throws inside the draft, `try` swallows it, and cursor stays
    # put — crucial when the user has already navigated somewhere
    # and jumps to a section that isn't currently rendered. Only on
    # a successful probe do we commit the real cursor move.
    set-register / "^## %arg{1}"
    try %{
        execute-keys -draft 'gg' 'n'
        execute-keys 'gg' 'n'
    }
}

declare-user-mode magit-status-jump
map global magit-status-jump h ': magit-status-jump-to Head<ret>'              -docstring 'Head'
map global magit-status-jump R ': magit-status-jump-to "Rebase in progress"<ret>' -docstring 'Rebase in progress'
map global magit-status-jump B ': magit-status-jump-to Bisecting<ret>'         -docstring 'Bisecting'
map global magit-status-jump w ': magit-status-jump-to "Other worktrees"<ret>' -docstring 'Other worktrees'
map global magit-status-jump o ': magit-status-jump-to Submodules<ret>'        -docstring 'Submodules'
map global magit-status-jump u ': magit-status-jump-to "Untracked files"<ret>' -docstring 'Untracked files'
map global magit-status-jump n ': magit-status-jump-to "Unstaged changes"<ret>' -docstring 'Unstaged changes'
map global magit-status-jump s ': magit-status-jump-to "Staged changes"<ret>'  -docstring 'Staged changes'
map global magit-status-jump z ': magit-status-jump-to Stashes<ret>'           -docstring 'Stashes'
map global magit-status-jump f ': magit-status-jump-to "Unpulled from"<ret>'   -docstring 'Unpulled'
map global magit-status-jump p ': magit-status-jump-to "Unpushed to"<ret>'     -docstring 'Unpushed'
map global magit-status-jump r ': magit-status-jump-to "Recent commits"<ret>'  -docstring 'Recent commits'

# Filetype highlighters + buffer-local keymap for *magit-status*.
# `?` help mode — keep in sync with the buffer bindings below.
declare-user-mode magit-status-keys
map global magit-status-keys n ': magit-next-section<ret>'   -docstring 'next section'
map global magit-status-keys p ': magit-prev-section<ret>'   -docstring 'prev section'
map global magit-status-keys P ': magit-parent-section<ret>' -docstring 'parent (top-level) section'
map global magit-status-keys R ': magit-status-render<ret>'  -docstring 'refresh'
map global magit-status-keys q ': delete-buffer *magit-status*<ret>' -docstring 'quit status'
map global magit-status-keys s ': magit-stage-at-cursor<ret>'   -docstring 'stage at cursor'
map global magit-status-keys u ': magit-unstage-at-cursor<ret>' -docstring 'unstage at cursor'
map global magit-status-keys V ': magit-reverse-at-cursor<ret>' -docstring 'reverse staged change in worktree'
map global magit-status-keys '<a-k>' ': magit-discard-at-cursor<ret>' -docstring 'discard at cursor'
map global magit-status-keys K       ': magit-discard-at-cursor<ret>' -docstring 'discard at cursor (alias)'
map global magit-status-keys <ret>   ': magit-visit-at-cursor<ret>'   -docstring 'visit file at cursor'
map global magit-status-keys a ': magit-stash-apply<ret>' -docstring 'apply stash at cursor'
map global magit-status-keys A ': magit-stash-pop<ret>'   -docstring 'pop stash at cursor'
map global magit-status-keys <tab> ': magit-status-fold-toggle<ret>' -docstring 'fold/unfold section at cursor'
map global magit-status-keys t ': enter-user-mode magit-status-jump<ret>' -docstring 'jump to section'

hook global WinSetOption filetype=magit-status %{
    add-highlighter window/magit-status group
    add-highlighter window/magit-status/section  regex '^##\s+[^\n]+$'      0:MagitSection
    add-highlighter window/magit-status/file     regex '^\s+##\s+[^\n]+$'   0:MagitFile
    add-highlighter window/magit-status/hunk     regex '^\s*@@[^\n]+@@'    0:MagitHunkHeader


    # Section nav uses n/p. These shadow kak's search-next/prev, which are
    # not useful inside *magit-status*.
    map buffer normal n ': magit-next-section<ret>'   -docstring 'next section'
    map buffer normal p ': magit-prev-section<ret>'   -docstring 'prev section'
    map buffer normal P ': magit-parent-section<ret>' -docstring 'parent (top-level) section'
    # Refresh uses R (not g) so that goto-mode (gg, ge, gl, …) still works.
    map buffer normal R ': magit-status-render<ret>'  -docstring 'refresh'
    map buffer normal q ': delete-buffer *magit-status*<ret>' -docstring 'quit status'
    # Stage/unstage use s/u. Selection/undo are not relevant in this buffer
    # (it's a rendered view, not hand-edited).
    map buffer normal s ': magit-stage-at-cursor<ret>'   -docstring 'stage at cursor'
    map buffer normal u ': magit-unstage-at-cursor<ret>' -docstring 'unstage at cursor'
    map buffer normal V ': magit-reverse-at-cursor<ret>' -docstring 'reverse staged change in worktree'
    # Discard uses <a-k> not k, so kak's k=up-motion is preserved. Magit
    # binds k but k is load-bearing in Kakoune. K (capital) = discard file.
    map buffer normal '<a-k>' ': magit-discard-at-cursor<ret>' -docstring 'discard at cursor'
    map buffer normal K       ': magit-discard-at-cursor<ret>' -docstring 'discard at cursor (alias)'
    map buffer normal <ret> ': magit-visit-at-cursor<ret>' -docstring 'visit file at cursor'
    # Stash actions: a apply (keep stash), A pop (apply + drop).
    # Drop-without-apply is reachable via <a-k> on a stash-entry (dispatched
    # inside magit-do-discard below).
    map buffer normal a ': magit-stash-apply<ret>' -docstring 'apply stash at cursor'
    map buffer normal A ': magit-stash-pop<ret>'   -docstring 'pop stash at cursor'
    map buffer normal <tab> ': magit-status-fold-toggle<ret>' -docstring 'fold/unfold section at cursor'
    # Jump menu: one key per section (t h/u/n/s/z/f/p/r/...). See above.
    map buffer normal t ': enter-user-mode magit-status-jump<ret>' -docstring 'jump to section'
    map buffer normal '?' ': enter-user-mode magit-status-keys<ret>' -docstring 'show keys (help)'

    hook -once -always window WinSetOption filetype=.* %{
        remove-highlighter window/magit-status
        unmap buffer normal n
        unmap buffer normal p
        unmap buffer normal P
        unmap buffer normal R
        unmap buffer normal q
        unmap buffer normal s
        unmap buffer normal u
        unmap buffer normal V
        unmap buffer normal '<a-k>'
        unmap buffer normal K
        unmap buffer normal <ret>
        unmap buffer normal a
        unmap buffer normal A
        unmap buffer normal <tab>
        unmap buffer normal t
        unmap buffer normal '?'
    }
}


}
