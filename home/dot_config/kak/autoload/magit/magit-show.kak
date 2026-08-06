# magit-show.kak — scratch-buffer viewers for commits and stashes.
# Utility commands used by magit-status visit-at-cursor and by magit-git's
# blame-jump.

provide-module magit-show %{

# `?` help modes — one per scratch-buffer kind. Buffer bindings below
# (emitted inside %sh{} printf) are duplicated here so `?` shows them.
declare-user-mode magit-show-keys
map global magit-show-keys q ': delete-buffer<ret>'             -docstring 'quit show buffer'
map global magit-show-keys V ': magit-show-revert<ret>'         -docstring 'revert whole commit into worktree'
map global magit-show-keys v ': magit-show-revert-hunk<ret>'    -docstring 'revert hunk at cursor into worktree'
map global magit-show-keys b ': magit-show-blob-at-cursor<ret>' -docstring 'open file at this commit as blob'

declare-user-mode magit-blob-keys
map global magit-blob-keys q ': delete-buffer<ret>' -docstring 'quit blob buffer'
map global magit-blob-keys b ': magit-blob-blame<ret>' -docstring 'blame this blob'

declare-user-mode magit-stash-show-keys
map global magit-stash-show-keys q ': delete-buffer<ret>' -docstring 'quit stash-show buffer'

# Show a commit in a scratch buffer. Parallels magit-blame-jump's scratch
# emission pattern.
define-command -hidden -params 1 magit-show-commit %{
    evaluate-commands %sh{
        sha=$1
        OB=$(printf '\173'); CB=$(printf '\175')
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
        [ -z "$toplevel" ] && { echo "fail 'not in a git repo'"; exit; }
        tmp=$(mktemp "${TMPDIR:-/tmp}/magit-show.XXXXXX")
        ( cd "$toplevel" && git show --no-color "$sha" ) > "$tmp" 2>/dev/null
        short=$(printf '%s' "$sha" | cut -c1-8)
        printf "edit -scratch '*magit-show-%s*'\n" "$short"
        # `git show` output is a unified diff (commit header + hunks);
        # the `diff` filetype gets Helix tree-sitter highlighting.
        printf "set-option buffer filetype diff\n"
        # Per-buffer q so we don't shadow kak's q (record macro) globally.
        printf "map buffer normal q ': delete-buffer<ret>'\n"
        # V: revert this commit into the worktree (index untouched).
        # v: revert just the hunk at cursor (hunk-level worktree revert).
        # b: open the file at cursor AS OF THIS COMMIT as a blob buffer
        #    (read-only preview; `b` inside that blob buffer runs blame).
        # Bound buffer-locally — only *magit-show-*<sha>* supports them.
        printf "map buffer normal V ': magit-show-revert<ret>'\n"
        printf "map buffer normal v ': magit-show-revert-hunk<ret>'\n"
        printf "map buffer normal b ': magit-show-blob-at-cursor<ret>'\n"
        printf "map buffer normal '?' ': enter-user-mode magit-show-keys<ret>'\n"
        printf "execute-keys '%%|cat %s<ret>gg'\n" "$tmp"
        printf "nop %%sh%s rm -f '%s' %s\n" "$OB" "$tmp" "$CB"
    }
}

# Revert a commit INTO THE WORKTREE only (index untouched). This is the
# worktree-targeted inverse of `git show <sha> | git apply -R` — it
# produces the "pre-commit" file state as unstaged edits, leaving the
# commit history alone. Different from `git revert` (which creates an
# inverse commit on HEAD; use the revert transient `<space>g v` for
# that).
#
# Preconditions: target files must not have unstaged edits on top
# (context mismatch would make `git apply -R` emit an opaque error).
# Refused cleanly in that case — same policy as magit-reverse in
# *magit-status*.
define-command -hidden -params 1 magit-revert-to-worktree %{
    evaluate-commands %sh{
        sha=$1
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
        [ -z "$toplevel" ] && { echo "fail 'magit-revert-to-worktree: not in a git repo'"; exit; }
        cd "$toplevel"
        # Resolve to a full SHA; gives a clean error if $sha doesn't refer
        # to a commit (e.g. empty string, bad ref).
        full=$(git rev-parse --verify "$sha^{commit}" 2>/dev/null)
        if [ -z "$full" ]; then
            safe=$(printf '%s' "$sha" | tr -d "'\"")
            printf "fail 'magit-revert-to-worktree: not a commit: %s'\n" "$safe"
            exit
        fi
        # Pre-check dirty stack: any file this commit touches that has
        # unstaged edits in the current worktree? git apply -R would
        # fail with a context-mismatch error that's hard to interpret.
        # `git show --name-only` lists the files; `git diff --quiet --
        # <file>` tests for unstaged changes. If any overlap, refuse.
        files=$(git show --no-color --name-only --pretty=format: "$full" 2>/dev/null | sed '/^$/d')
        dirty_stack=""
        for f in $files; do
            # The file may have been deleted in the commit — skip missing
            # paths to avoid false positives from `git diff` on a
            # non-existent path.
            [ -e "$f" ] || continue
            if ! git diff --quiet -- "$f" 2>/dev/null; then
                dirty_stack="$dirty_stack $f"
            fi
        done
        if [ -n "$dirty_stack" ]; then
            safe_sha=$(printf '%s' "$full" | cut -c1-8)
            printf "fail 'magit-revert-to-worktree %s: refusing — these files have unstaged edits:%s  (stash or discard unstaged first)'\n" "$safe_sha" "$dirty_stack"
            exit
        fi
        err=$(mktemp "${TMPDIR:-/tmp}/magit-revert-wt.XXXXXX")
        # `git show` emits the commit with a header (author/date/subject)
        # followed by the diff. `git apply -R` tolerates the header — it
        # starts patch-parsing at the first `diff --git` line. Pipe
        # directly.
        if git show --no-color "$full" 2>/dev/null | git apply -R >/dev/null 2>"$err"; then
            short=$(printf '%s' "$full" | cut -c1-8)
            printf "echo -markup %%{{Information}reverted %s into worktree (index untouched)}\n" "$short"
            printf "magit-refresh-after-mutation\n"
        else
            reason=$(head -1 "$err" | tr -d "'\"")
            [ -z "$reason" ] && reason="git apply -R failed"
            printf "fail 'magit-revert-to-worktree: %s'\n" "$reason"
        fi
        rm -f "$err"
    }
}

# Hunk-level revert inside *magit-show-*<sha>*. Parses the buffer at
# cursor: walks back to the nearest `@@` to find the hunk, and back
# further to find the `diff --git` / `+++ b/<path>` headers naming the
# file. Builds a minimal patch (file headers + this one hunk), then
# `git apply -R` — exactly as magit-do-reverse-hunk does for staged
# hunks in *magit-status*, but here the source is a committed diff.
#
# Cursor positions handled:
#   * on a `@@` hunk header → that hunk.
#   * inside a hunk body (context/+/- line) → the enclosing hunk.
#   * on a file header (`diff --git`, `---`, `+++`) → refuse: ambiguous.
#
# Two-step so we can snapshot the buffer contents synchronously. Kak
# lacks a %val{buf_contents} expansion, so we `write -force $tmp` then
# re-enter with the path as a param. Register-based capture would also
# work but runs into env-size limits for large commits.
define-command -hidden magit-show-revert-hunk %{
    evaluate-commands %sh{
        tmp=$(mktemp "${TMPDIR:-/tmp}/magit-show-revert-hunk.XXXXXX")
        printf "write -force '%s'\n" "$tmp"
        printf "magit-show-revert-hunk-impl '%s'\n" "$tmp"
    }
}

define-command -hidden -params 1 magit-show-revert-hunk-impl %{
    evaluate-commands %sh{
        buf=$1
        cur=$kak_cursor_line
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
        if [ -z "$toplevel" ]; then
            rm -f "$buf"
            echo "fail 'magit-show-revert-hunk: not in a git repo'"
            exit
        fi

        # One awk pass: find the enclosing hunk for the cursor line, the
        # file path for that hunk, AND the file-header block. The buffer
        # is a verbatim `git show --no-color` rendering, so we can slice
        # directly — no need to re-run git show.
        patch_tmp=$(mktemp "${TMPDIR:-/tmp}/magit-show-revert-patch.XXXXXX")
        awk -v cur="$cur" '
            # Walk the buffer. Track the current file-header block
            # (diff/index/---/+++). When we see `@@`, start a hunk,
            # accumulating body lines. When we see the NEXT `@@` OR a
            # new `diff --git`, the previous hunk has ended — check if
            # cursor was inside and emit. Also handle EOF as end.
            #
            # `emitted` guards against awk `exit` still firing END{}:
            # if we already printed, END{} must not re-print.
            function close_and_maybe_emit(end_line,   i) {
                if (!emitted && hunk_start > 0 && cur >= hunk_start && cur <= end_line) {
                    printf "%s", saved_header hunk_body
                    emitted = 1
                    exit
                }
            }
            /^diff --git / {
                close_and_maybe_emit(NR - 1)
                header = $0 "\n"
                cur_file = ""
                in_header = 1
                hunk_start = 0
                next
            }
            in_header && /^(index |--- |\+\+\+ )/ {
                header = header $0 "\n"
                if ($0 ~ /^\+\+\+ b\//) cur_file = substr($0, 7)
                else if ($0 ~ /^--- a\// && cur_file == "") cur_file = substr($0, 7)
                next
            }
            /^@@ / {
                close_and_maybe_emit(NR - 1)
                in_header = 0
                hunk_start = NR
                hunk_body = $0 "\n"
                saved_header = header   # header is stable per-file
                next
            }
            hunk_start > 0 { hunk_body = hunk_body $0 "\n" }
            END { if (!emitted) close_and_maybe_emit(NR) }
        ' "$buf" > "$patch_tmp"

        # Parse out the file path from the patch we just wrote, for the
        # dirty-stack check + user-visible error messages.
        file=$(awk '/^\+\+\+ b\// { print substr($0,7); exit } /^--- a\// && f=="" { f=substr($0,7) } END { if (f!="" && !shown) print f }' "$patch_tmp")

        rm -f "$buf"

        if [ ! -s "$patch_tmp" ]; then
            rm -f "$patch_tmp"
            echo "fail 'magit-show-revert-hunk: cursor not inside a hunk'"
            exit
        fi

        # Pre-check: refuse if the target file has unstaged edits. Same
        # policy as whole-commit revert.
        if [ -n "$file" ] && [ -e "$toplevel/$file" ]; then
            if ! ( cd "$toplevel" && git diff --quiet -- "$file" 2>/dev/null ); then
                rm -f "$patch_tmp"
                safe=$(printf '%s' "$file" | tr -d "'\"")
                printf "fail 'magit-show-revert-hunk: %s has unstaged edits — stash or discard first'\n" "$safe"
                exit
            fi
        fi

        err=$(mktemp "${TMPDIR:-/tmp}/magit-show-revert-err.XXXXXX")
        if ( cd "$toplevel" && git apply -R ) < "$patch_tmp" 2>"$err"; then
            safe=$(printf '%s' "$file" | tr -d "'\"")
            [ -z "$safe" ] && safe="hunk"
            printf "echo -markup %%{{Information}reverted hunk in %s into worktree}\n" "$safe"
            printf "magit-refresh-after-mutation\n"
        else
            reason=$(head -1 "$err" | tr -d "'\"")
            [ -z "$reason" ] && reason="git apply -R failed"
            printf "fail 'magit-show-revert-hunk: %s'\n" "$reason"
        fi
        rm -f "$err" "$patch_tmp"
    }
}

# Entry point for `V` in *magit-show-*<sha>*: revert the whole commit
# into the worktree. Hunk-level revert is bound separately to `v` (see
# magit-show-revert-hunk). Two keys for two operations — simpler than
# cursor-context dispatch.
# Uses $kak_bufname not $kak_buffile (scratch buffers — Lesson 45).
define-command -hidden magit-show-revert %{
    evaluate-commands %sh{
        name=$kak_bufname
        short=${name#\*magit-show-}
        short=${short%\*}
        case "$short" in
            stash-*|'')
                echo "fail 'magit-show-revert: can only revert a commit buffer'"
                exit
                ;;
        esac
        case "$short" in
            *[!0-9a-f]*)
                safe=$(printf '%s' "$short" | tr -d "'\"")
                printf "fail 'magit-show-revert: not a SHA: %s'\n" "$safe"
                exit
                ;;
        esac
        printf 'magit-revert-to-worktree %s\n' "$short"
    }
}

# Open a blob (file content at a specific commit) in a scratch buffer.
# $1 = sha, $2 = path (relative to repo root). Buffer is named
# `*magit-blob-<short-sha>:<path>*`. Read-only in practice. Filetype is
# inferred from the path extension so syntax highlighting works; if
# kak has no filetype guesser for the extension, filetype stays unset.
#
# Bound to `b` in *magit-show-*<sha>* — entry point `magit-show-blob`
# (below) parses the cursor's file from the show buffer and delegates
# here.
define-command -hidden -params 2 magit-show-blob %{
    evaluate-commands %sh{
        sha=$1
        path=$2
        OB=$(printf '\173'); CB=$(printf '\175')
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
        [ -z "$toplevel" ] && { echo "fail 'magit-show-blob: not in a git repo'"; exit; }
        # Resolve full sha for stable naming + to validate.
        full=$(cd "$toplevel" && git rev-parse --verify "$sha^{commit}" 2>/dev/null)
        if [ -z "$full" ]; then
            safe=$(printf '%s' "$sha" | tr -d "'\"")
            printf "fail 'magit-show-blob: not a commit: %s'\n" "$safe"
            exit
        fi
        # Validate blob exists at that commit.
        if ! ( cd "$toplevel" && git cat-file -e "${full}:${path}" 2>/dev/null ); then
            safe_path=$(printf '%s' "$path" | tr -d "'\"")
            safe_short=$(printf '%s' "$full" | cut -c1-8)
            printf "fail 'magit-show-blob: no blob for %s at %s'\n" "$safe_path" "$safe_short"
            exit
        fi
        short=$(printf '%s' "$full" | cut -c1-8)
        tmp=$(mktemp "${TMPDIR:-/tmp}/magit-blob.XXXXXX")
        ( cd "$toplevel" && git show --no-color "${full}:${path}" ) > "$tmp" 2>/dev/null
        # Buffer name: strip slashes from path (they're forbidden in
        # buffer names) — replace with `_`. Keep the dot in extension
        # so the filetype hook can fire.
        safe_buf_path=$(printf '%s' "$path" | tr '/' '_')
        bufname="*magit-blob-${short}:${safe_buf_path}*"
        printf "edit -scratch '%s'\n" "$bufname"
        # Stash the real blob metadata on the buffer so blob-blame can
        # use it without re-parsing the buffer name.
        printf "set-option buffer magit_blob_sha '%s'\n" "$full"
        printf "set-option buffer magit_blob_path '%s'\n" "$path"
        # Try to set filetype from the extension. kak's built-in
        # filetype guesser fires on `edit` for real files; for scratch
        # we derive manually from the extension.
        ext=${path##*.}
        case "$ext" in
            rs)  printf "set-option buffer filetype rust\n" ;;
            py)  printf "set-option buffer filetype python\n" ;;
            js|mjs|cjs) printf "set-option buffer filetype javascript\n" ;;
            ts|tsx) printf "set-option buffer filetype typescript\n" ;;
            go)  printf "set-option buffer filetype go\n" ;;
            kak) printf "set-option buffer filetype kak\n" ;;
            sh|bash) printf "set-option buffer filetype sh\n" ;;
            md)  printf "set-option buffer filetype markdown\n" ;;
            c|h) printf "set-option buffer filetype c\n" ;;
            cpp|cc|cxx|hpp) printf "set-option buffer filetype cpp\n" ;;
            json) printf "set-option buffer filetype json\n" ;;
            yml|yaml) printf "set-option buffer filetype yaml\n" ;;
            lua) printf "set-option buffer filetype lua\n" ;;
            # Unknown extension — leave unset.
        esac
        printf "map buffer normal q ': delete-buffer<ret>'\n"
        printf "map buffer normal b ': magit-blob-blame<ret>'\n"
        printf "map buffer normal '?' ': enter-user-mode magit-blob-keys<ret>'\n"
        printf "execute-keys '%%|cat %s<ret>gg'\n" "$tmp"
        printf "nop %%sh%s rm -f '%s' %s\n" "$OB" "$tmp" "$CB"
    }
}

declare-option -hidden str magit_blob_sha ''
declare-option -hidden str magit_blob_path ''

# Entry point for `b` in *magit-show-*<sha>*: open the blob for the
# file the cursor is inside (determined by walking backward to find
# the most recent `+++ b/<path>` or `--- a/<path>`). Two-step via a
# tempfile snapshot, same shape as magit-show-revert-hunk.
define-command -hidden magit-show-blob-at-cursor %{
    evaluate-commands %sh{
        tmp=$(mktemp "${TMPDIR:-/tmp}/magit-show-blob-peek.XXXXXX")
        printf "write -force '%s'\n" "$tmp"
        printf "magit-show-blob-at-cursor-impl '%s'\n" "$tmp"
    }
}

define-command -hidden -params 1 magit-show-blob-at-cursor-impl %{
    evaluate-commands %sh{
        buf=$1
        cur=$kak_cursor_line
        # Walk backward from cursor to find the enclosing file path.
        path=$(awk -v cur="$cur" '
            NR > cur { exit }
            /^\+\+\+ b\// { path=substr($0, 7) }
            /^--- a\// && path == "" { path=substr($0, 7) }
            END { print path }
        ' "$buf")
        rm -f "$buf"
        if [ -z "$path" ]; then
            echo "fail 'magit-show-blob: cursor not inside a file section'"
            exit
        fi
        # Pull the commit SHA from the buffer name.
        name=$kak_bufname
        short=${name#\*magit-show-}
        short=${short%\*}
        case "$short" in
            stash-*|''|*[!0-9a-f]*)
                echo "fail 'magit-show-blob: not a commit buffer'"
                exit
                ;;
        esac
        printf "magit-show-blob %s '%s'\n" "$short" "$path"
    }
}

# Blame the blob in the current *magit-blob-*<sha>:<path>* buffer. We
# already have magit_blob_sha / magit_blob_path set on the buffer;
# run git blame on that commit+path, render the overlay using the
# same flag-lines machinery as magit-blame-show.
define-command -hidden magit-blob-blame %{
    evaluate-commands %sh{
        sha=$kak_opt_magit_blob_sha
        path=$kak_opt_magit_blob_path
        if [ -z "$sha" ] || [ -z "$path" ]; then
            echo "fail 'magit-blob-blame: not a blob buffer (missing blob sha/path)'"
            exit
        fi
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
        [ -z "$toplevel" ] && { echo "fail 'magit-blob-blame: not in a git repo'"; exit; }

        entries=$(mktemp "${TMPDIR:-/tmp}/magit-blob-blame.XXXXXX")
        ( cd "$toplevel" && git blame --porcelain "$sha" -- "$path" 2>/dev/null ) \
        | perl -e '
            use POSIX qw(strftime);
            my %authors;
            my %dates;
            my ($sha, $new_line, $count);
            my $expect_content = 0;
            while (my $line = <STDIN>) {
                chomp $line;
                if ($line =~ /^([0-9a-f]+) (\d+) (\d+)(?: (\d+))?/) {
                    $sha = $1;
                    $new_line = $3;
                    $count = defined($4) ? $4 : 1;
                    $expect_content = 1;
                    next;
                }
                if ($line =~ /^author (.+)/) { $authors{$sha} = $1 unless exists $authors{$sha}; next; }
                if ($line =~ /^author-time (\d+)/) { $t = $1; next; }
                if ($line =~ /^author-tz ([+-])(\d\d)/) {
                    my $sign = $1 eq "+" ? "-" : "+";
                    local $ENV{TZ} = "UTC${sign}$2";
                    $dates{$sha} = strftime("%Y-%m-%d", localtime($t)) unless exists $dates{$sha};
                    next;
                }
                if ($line =~ /^\t/ && $expect_content) {
                    my $short = substr($sha, 0, 8);
                    my $author = $authors{$sha} // "?";
                    my $date = $dates{$sha} // "?";
                    $author = substr($author, 0, 12);
                    print "$new_line|{Information}$short $date $author  \n";
                    $expect_content = 0;
                }
            }
          ' > "$entries"

        sq=$(printf '\047')
        printf "set-option buffer magit_blame_flags %s\n" "$kak_timestamp"
        while IFS= read -r entry; do
            [ -z "$entry" ] && continue
            esc=$(printf '%s' "$entry" | tr -d "$sq")
            printf "set-option -add buffer magit_blame_flags %s%s%s\n" "$sq" "$esc" "$sq"
        done < "$entries"
        rm -f "$entries"
    }
    try %{ add-highlighter window/magit-blame flag-lines Information magit_blame_flags }
    set-option buffer magit_blame_active true
}

# Show a stash in a scratch buffer. $1 = stash ref like "stash@{0}".
define-command -hidden -params 1 magit-show-stash %{
    evaluate-commands %sh{
        ref=$1
        OB=$(printf '\173'); CB=$(printf '\175')
        toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
        [ -z "$toplevel" ] && { echo "fail 'not in a git repo'"; exit; }
        tmp=$(mktemp "${TMPDIR:-/tmp}/magit-stash.XXXXXX")
        ( cd "$toplevel" && git stash show -p --no-color "$ref" ) > "$tmp" 2>/dev/null
        # Extract the {N} part for the buffer name.
        num=$(printf '%s' "$ref" | sed -n 's/^stash@.\([0-9]*\).$/\1/p')
        [ -z "$num" ] && num=X
        printf "edit -scratch '*magit-show-stash-%s*'\n" "$num"
        printf "set-option buffer filetype git-diff\n"
        printf "map buffer normal q ': delete-buffer<ret>'\n"
        printf "map buffer normal '?' ': enter-user-mode magit-stash-show-keys<ret>'\n"
        printf "execute-keys '%%|cat %s<ret>gg'\n" "$tmp"
        printf "nop %%sh%s rm -f '%s' %s\n" "$OB" "$tmp" "$CB"
    }
}

}
