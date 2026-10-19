# magit-git.kak — magit-owned low-level git layer.
# Replaces the parts of upstream git.kak we depend on, with a tight
# cwd-clean implementation. Loaded as a module (consistency with siblings).

provide-module magit-git %{

# --- Gutter options -----------------------------------------------------
declare-option -docstring "gutter char for added lines"    str magit_gutter_add_char "▏"
declare-option -docstring "gutter char for modified lines" str magit_gutter_mod_char "▏"
declare-option -docstring "gutter char for deleted lines"  str magit_gutter_del_char "_"
declare-option -docstring "gutter char for top-of-file deletion" str magit_gutter_top_char "‾"

# Line-specs payload for flag-lines. Written by magit-gutter-update.
declare-option -hidden line-specs magit_gutter_flags

# Cached hunk-start line list for next/prev nav. Format: "<timestamp> <line1> <line2> ..."
declare-option -hidden int-list magit_hunk_list

# --- Gutter: show / hide / update ---------------------------------------
# Every %sh{} block that calls git computes `toplevel` at entry and wraps
# git invocations as `( cd "$toplevel" && git ... )`. Never relies on cwd.
define-command magit-gutter-show -docstring 'Show magit diff gutter in current buffer' %{
    try %{ add-highlighter window/magit-gutter flag-lines Default magit_gutter_flags }
    magit-gutter-update
}

define-command magit-gutter-hide -docstring 'Hide magit diff gutter in current buffer' %{
    try %{ remove-highlighter window/magit-gutter }
    set-option buffer magit_gutter_flags %val{timestamp}
    set-option buffer magit_hunk_list %val{timestamp}
}

# Compute diff (HEAD version vs current buffer contents) and write line-specs
# into magit_gutter_flags. Safe on any buffer — no-ops if the buffer isn't a
# tracked file in a git repo.
define-command magit-gutter-update -docstring 'Refresh magit diff gutter for current buffer' %{
    evaluate-commands %sh{
        # Bail on scratch / non-path buffers.
        case "$kak_buffile" in
            /*) ;;
            *) exit 0 ;;
        esac
        bufdir=$(dirname "$kak_buffile")
        toplevel=$(cd "$bufdir" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)
        [ -n "$toplevel" ] || exit 0

        # Untracked files: nothing to show.
        if ! ( cd "$toplevel" && git ls-files --error-unmatch -- "$kak_buffile" ) >/dev/null 2>&1; then
            exit 0
        fi

        buffile_relative=${kak_buffile#"$toplevel/"}

        # Diff the on-disk file against the INDEX (staged state). Matches
        # Magit semantics: the gutter reflects "what's unstaged" so after
        # staging a hunk, its markers disappear from the gutter.
        # Unsaved buffer edits aren't reflected until BufWritePost — matches
        # editor convention and avoids fifo-deadlock.
        entries=$(mktemp "${TMPDIR:-/tmp}/magit-gutter-entries.XXXXXX")
        (
            ( cd "$toplevel" && git diff --no-ext-diff --no-color -U0 -- "$buffile_relative" 2>/dev/null ) \
            | MAGIT_ADD="$kak_opt_magit_gutter_add_char" \
              MAGIT_MOD="$kak_opt_magit_gutter_mod_char" \
              MAGIT_DEL="$kak_opt_magit_gutter_del_char" \
              MAGIT_TOP="$kak_opt_magit_gutter_top_char" \
              perl -e '
                my $add_c = $ENV{MAGIT_ADD};
                my $mod_c = $ENV{MAGIT_MOD};
                my $del_c = $ENV{MAGIT_DEL};
                my $top_c = $ENV{MAGIT_TOP};
                while (my $line = <STDIN>) {
                    next unless $line =~ /\@\@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))?/;
                    my $from_line  = $1;
                    my $from_count = defined($2) ? $2 : 1;
                    my $to_line    = $3;
                    my $to_count   = defined($4) ? $4 : 1;

                    # Emit each entry as a separate "line|{face}char" token.
                    # We print each on its own line for the shell loop to wrap
                    # in quotes — avoids any brace-parsing surprises in kak.
                    if ($from_count == 0 and $to_count > 0) {
                        for my $i (0 .. $to_count - 1) {
                            my $l = $to_line + $i;
                            print "$l|{green}$add_c\n";
                        }
                    }
                    elsif ($from_count > 0 and $to_count == 0) {
                        if ($to_line == 0) {
                            print "1|{red}$top_c\n";
                        } else {
                            print "$to_line|{red}$del_c\n";
                        }
                    }
                    elsif ($from_count > 0 and $from_count == $to_count) {
                        for my $i (0 .. $to_count - 1) {
                            my $l = $to_line + $i;
                            print "$l|{blue}$mod_c\n";
                        }
                    }
                    elsif ($from_count > 0 and $from_count < $to_count) {
                        for my $i (0 .. $from_count - 1) {
                            my $l = $to_line + $i;
                            print "$l|{blue}$mod_c\n";
                        }
                        for my $i ($from_count .. $to_count - 1) {
                            my $l = $to_line + $i;
                            print "$l|{green}$add_c\n";
                        }
                    }
                    elsif ($to_count > 0 and $from_count > $to_count) {
                        for my $i (0 .. $to_count - 2) {
                            my $l = $to_line + $i;
                            print "$l|{blue}$mod_c\n";
                        }
                        my $last = $to_line + $to_count - 1;
                        print "$last|{blue+u}$mod_c\n";
                    }
                }
              ' > "$entries"
        )

        # Reset the option (timestamp-only), then add each entry single-quoted.
        # kak's single-quoted args take everything literally except '' → '.
        # Our entries never contain a single quote.
        printf "set-option buffer magit_gutter_flags %s\n" "$kak_timestamp"
        while IFS= read -r entry; do
            [ -z "$entry" ] && continue
            printf "set-option -add buffer magit_gutter_flags '%s'\n" "$entry"
        done < "$entries"
        rm -f "$entries"
    }
}

# --- Hunk navigation ----------------------------------------------------
# Next / prev hunk within current buffer. Reads magit_gutter_flags; caches
# the sorted list of hunk-start lines in magit_hunk_list (indexed by
# timestamp so it's invalidated when the buffer changes).
define-command magit-next-hunk -docstring 'Jump to next hunk in current buffer' %{
    magit-jump-hunk next
}

define-command magit-prev-hunk -docstring 'Jump to previous hunk in current buffer' %{
    magit-jump-hunk prev
}

define-command -hidden -params 1 magit-jump-hunk %{
    evaluate-commands %sh{
        direction=$1
        # magit_gutter_flags format: "<timestamp> <line>|<spec> <line>|<spec> ..."
        # First strip the timestamp.
        eval set -- $kak_quoted_opt_magit_gutter_flags
        shift  # drop the leading timestamp
        if [ $# -lt 1 ]; then
            echo "fail 'no hunks — magit-gutter-show may not have run'"
            exit
        fi

        # Build/refresh the cached hunk-start list if out of date.
        hunk_ts=$(printf '%s' "$kak_opt_magit_hunk_list" | awk '{print $1}')
        if [ "$kak_timestamp" != "$hunk_ts" ]; then
            # Rebuild: take every flag line, emit line only when gap > 1 from prev.
            eval set -- $kak_quoted_opt_magit_gutter_flags
            shift
            hunks=$kak_timestamp
            prev_line=-1
            for entry; do
                line=${entry%%|*}
                if [ $((line - prev_line)) -gt 1 ]; then
                    hunks="$hunks $line"
                fi
                prev_line=$line
            done
            printf 'set-option buffer magit_hunk_list %s\n' "$hunks"
            hunks_only=${hunks#* }
        else
            hunks_only=${kak_opt_magit_hunk_list#* }
        fi

        prev_hunk=
        next_hunk=
        for h in $hunks_only; do
            if [ "$h" -lt "$kak_cursor_line" ]; then
                prev_hunk=$h
            elif [ "$h" -gt "$kak_cursor_line" ]; then
                next_hunk=$h
                break
            fi
        done

        wrapped=false
        if [ "$direction" = "next" ]; then
            if [ -z "$next_hunk" ]; then
                next_hunk=${hunks_only%% *}
                wrapped=true
            fi
            [ -n "$next_hunk" ] && printf 'select %s.1,%s.1\n' "$next_hunk" "$next_hunk"
        else
            if [ -z "$prev_hunk" ]; then
                prev_hunk=${hunks_only##* }
                wrapped=true
            fi
            [ -n "$prev_hunk" ] && printf 'select %s.1,%s.1\n' "$prev_hunk" "$prev_hunk"
        fi
        if [ "$wrapped" = true ]; then
            echo "echo -markup '{Information}hunk search wrapped'"
        fi
    }
}

# --- Blame --------------------------------------------------------------
# Worktree-only blame overlay. Annotates every line with `sha8 YYYY-MM-DD
# author`. <ret> on an annotated line opens :git show for that commit in a
# scratch buffer. Toggleable via magit-blame-toggle.

declare-option -hidden line-specs magit_blame_flags
declare-option -hidden bool magit_blame_active false
# `magit_blame_style` cycles display density: full → sha → author → full.
#   full   (default): "sha8 YYYY-MM-DD Author"
#   sha    : "sha8"
#   author : "sha8 Author"       (no date — useful for narrow panes)
declare-option -hidden str magit_blame_style full
# The rev currently being blamed. Empty = worktree (default). Non-empty =
# the result of `magit-blame-recursive`, used by modeline/debug + to detect
# a reblame on the already-parent commit.
declare-option -hidden str magit_blame_rev ''

# `?` help mode for the blame overlay — bound on the buffer when blame is
# active. Keep in sync with the inline map buffer calls in magit-blame-show.
declare-user-mode magit-blame-keys
map global magit-blame-keys <ret> ': magit-blame-jump<ret>'         -docstring 'show commit for line at cursor'
map global magit-blame-keys B     ': magit-blame-recursive<ret>'    -docstring 're-blame at <sha>^ (walk history back)'
map global magit-blame-keys s     ': magit-blame-style-cycle<ret>'  -docstring 'cycle style: full → sha → author'

# Shared help mode for simple "diff scratch viewer" buffers (diff-staged,
# diff transient output, merge-preview). They all bind just `q`.
declare-user-mode magit-diff-view-keys
map global magit-diff-view-keys q ': delete-buffer<ret>' -docstring 'quit diff view'

define-command magit-blame-toggle -docstring 'Toggle magit blame overlay' %{
    evaluate-commands %sh{
        if [ "$kak_opt_magit_blame_active" = "true" ]; then
            echo magit-blame-hide
        else
            echo magit-blame-show
        fi
    }
}

define-command magit-blame-hide -docstring 'Hide magit blame overlay' %{
    try %{ remove-highlighter window/magit-blame }
    set-option buffer magit_blame_flags %val{timestamp}
    set-option buffer magit_blame_active false
    set-option buffer magit_blame_rev ''
    try %{ unmap buffer normal <ret> ':magit-blame-jump<ret>' }
    try %{ unmap buffer normal B     ':magit-blame-recursive<ret>' }
    try %{ unmap buffer normal s     ':magit-blame-style-cycle<ret>' }
    try %{ unmap buffer normal '?'   ':enter-user-mode magit-blame-keys<ret>' }
}

define-command magit-blame-show -docstring 'Show magit blame overlay' %{
    evaluate-commands %sh{
        case "$kak_buffile" in
            /*) ;;
            *) echo "fail 'magit-blame: not a file buffer'"; exit ;;
        esac
        bufdir=$(dirname "$kak_buffile")
        toplevel=$(cd "$bufdir" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)
        if [ -z "$toplevel" ]; then
            echo "fail 'magit-blame: not in a git repo'"; exit
        fi
        if ! ( cd "$toplevel" && git ls-files --error-unmatch -- "$kak_buffile" ) >/dev/null 2>&1; then
            echo "fail 'magit-blame: file untracked'"; exit
        fi

        buffile_relative=${kak_buffile#"$toplevel/"}
        entries=$(mktemp "${TMPDIR:-/tmp}/magit-blame-entries.XXXXXX")

        # Rev scope: empty -> worktree blame. Non-empty -> historical blame
        # at that rev (used by magit-blame-recursive to walk back).
        rev=$kak_opt_magit_blame_rev
        style=$kak_opt_magit_blame_style
        # Default guards — empty option or unknown value falls back to full.
        case "$style" in
            full|sha|author) ;;
            *) style=full ;;
        esac
        export MAGIT_BLAME_STYLE=$style
        if [ -n "$rev" ]; then
            ( cd "$toplevel" && git blame --porcelain "$rev" -- "$buffile_relative" 2>/dev/null )
        else
            ( cd "$toplevel" && git blame --porcelain -- "$buffile_relative" 2>/dev/null )
        fi \
        | perl -e '
            use POSIX qw(strftime);
            my $style = $ENV{MAGIT_BLAME_STYLE} // "full";
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
                    my $author = substr(($authors{$sha} // "?"), 0, 12);
                    my $date = $dates{$sha} // "?";
                    my $flag;
                    if ($style eq "sha") {
                        $flag = "$short  ";
                    } elsif ($style eq "author") {
                        $flag = "$short $author  ";
                    } else {
                        $flag = "$short $date $author  ";
                    }
                    print "$new_line|{Information}$flag\n";
                    $expect_content = 0;
                }
            }
          ' > "$entries"

        # Emit entries via single-quoted set-option -add (Lesson 23).
        # Emit entries via set-option -add with single-quoted values (Lesson 23).
        # Single quotes are stripped from the entry first — a literal single
        # quote in the value can't be safely embedded in a single-quoted arg,
        # and complex escape dances confuse kak's %sh{} block parser.
        sq=$(printf '\047')  # ASCII 39 = single quote
        printf "set-option buffer magit_blame_flags %s\n" "$kak_timestamp"
        while IFS= read -r entry; do
            [ -z "$entry" ] && continue
            esc=$(printf '%s' "$entry" | tr -d "$sq")
            printf "set-option -add buffer magit_blame_flags %s%s%s\n" "$sq" "$esc" "$sq"
        done < "$entries"
        rm -f "$entries"

    }
    # Post-shell kakscript — runs after the %sh block above returns.
    # Kept outside the shell block because the try/add-highlighter line below
    # has a literal close-brace that would prematurely end a shell block.
    try %{ add-highlighter window/magit-blame flag-lines Information magit_blame_flags }
    map buffer normal <ret> ':magit-blame-jump<ret>'
    map buffer normal B     ':magit-blame-recursive<ret>'
    map buffer normal s     ':magit-blame-style-cycle<ret>'
    map buffer normal '?'   ':enter-user-mode magit-blame-keys<ret>'
    set-option buffer magit_blame_active true
}

# Cycle the blame-overlay format density: full → sha → author → full.
# Re-runs magit-blame-show to re-render with the new style.
define-command magit-blame-style-cycle -docstring 'Cycle blame overlay: full → sha → author' %{
    evaluate-commands %sh{
        case "$kak_opt_magit_blame_style" in
            full)   next=sha ;;
            sha)    next=author ;;
            author) next=full ;;
            *)      next=full ;;
        esac
        printf "set-option global magit_blame_style %s\n" "$next"
        printf "echo -markup %%{{Information}blame style: %s}\n" "$next"
    }
    magit-blame-show
}

define-command magit-blame-jump -docstring 'Open commit for line at cursor' %{
    evaluate-commands %sh{
        # Lesson 4: never put literal {{/}} in a %sh{} body — kak counts braces
        # to find the block end. Use OB/CB for emission; avoid literal braces
        # in comments and string content.
        OB=$(printf '\173')
        CB=$(printf '\175')
        # Find the blame entry whose line matches cursor.
        eval set -- $kak_quoted_opt_magit_blame_flags
        shift
        target_sha=
        for entry; do
            line=${entry%%|*}
            if [ "$line" = "$kak_cursor_line" ]; then
                # Strip up to and including the close-brace of the face marker.
                after=${entry#*$CB}
                target_sha=${after%% *}
                break
            fi
        done
        if [ -z "$target_sha" ]; then
            echo "fail 'magit-blame-jump: no blame entry for this line'"
            exit
        fi
        case "$target_sha" in
            0*)
                case "$target_sha" in
                    *[!0]*) ;;
                    *) printf "echo -markup '%sInformation%sNot committed yet'\n" "$OB" "$CB"; exit ;;
                esac
                ;;
        esac

        bufdir=$(dirname "$kak_buffile")
        toplevel=$(cd "$bufdir" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)
        if [ -z "$toplevel" ]; then
            echo "fail 'magit-blame-jump: not in a git repo'"
            exit
        fi

        tmp=$(mktemp "${TMPDIR:-/tmp}/magit-show.XXXXXX")
        ( cd "$toplevel" && git show --no-color "$target_sha" ) > "$tmp" 2>/dev/null
        bufname="*magit-show-$(printf '%s' "$target_sha" | cut -c1-8)*"
        printf "edit -scratch '%s'\n" "$bufname"
        # `git show` output is a unified diff — `diff` filetype gets
        # Helix tree-sitter highlighting.
        printf "set-option buffer filetype diff\n"
        printf "execute-keys '%%|cat %s<ret>gg'\n" "$tmp"
        printf "nop %%sh%s rm -f '%s' %s\n" "$OB" "$tmp" "$CB"
    }
}

# Re-blame the current file at the parent of the sha under cursor.
# Answers "who touched this line before this commit touched it?" Walks
# history backwards one step per invocation. Fails cleanly when the line
# is introduced by a root commit (no parent).
define-command magit-blame-recursive -docstring 'Re-blame at parent of sha at cursor' %{
    evaluate-commands %sh{
        # Extract the sha for the line at cursor — same logic as blame-jump.
        eval set -- $kak_quoted_opt_magit_blame_flags
        shift
        target_sha=
        for entry; do
            line=${entry%%|*}
            if [ "$line" = "$kak_cursor_line" ]; then
                CB=$(printf '\175')
                after=${entry#*$CB}
                target_sha=${after%% *}
                break
            fi
        done
        if [ -z "$target_sha" ]; then
            echo "fail 'magit-blame-recursive: no blame entry for this line'"
            exit
        fi
        case "$target_sha" in
            0*)
                case "$target_sha" in
                    *[!0]*) ;;
                    *) echo "fail 'magit-blame-recursive: line not committed yet'"; exit ;;
                esac
                ;;
        esac
        # Resolve parent. Fails on root commit (no parent).
        bufdir=$(dirname "$kak_buffile")
        toplevel=$(cd "$bufdir" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)
        if [ -z "$toplevel" ]; then
            echo "fail 'magit-blame-recursive: not in a git repo'"
            exit
        fi
        if ! parent=$(cd "$toplevel" && git rev-parse -q --verify "${target_sha}^" 2>/dev/null); then
            echo "fail 'magit-blame-recursive: no parent (root commit)'"
            exit
        fi
        # Set the rev and re-render. Hide first so the overlay rebuilds
        # cleanly (clears stale flags and old mappings).
        printf "magit-blame-hide\n"
        printf "set-option buffer magit_blame_rev '%s'\n" "$parent"
        printf "magit-blame-show\n"
        printf "echo -markup %%{{Information}blame at %s}\n" "$(printf '%s' "$parent" | cut -c1-8)"
    }
}

# --- Apply selection ----------------------------------------------------
# Stage / unstage the selected lines in the current buffer via
# `git apply --cached`. Patch is computed from the file on disk (matches
# gutter semantics) and sliced to selection bounds via kak's own
# patch-range.pl helper. No buffer-contents fetch → no fifo deadlock.

define-command magit-stage-selection -docstring 'Stage the selected lines' %{
    magit-apply-selection stage
}

define-command magit-unstage-selection -docstring 'Unstage the selected lines' %{
    magit-apply-selection unstage
}

define-command -hidden -params 1 magit-apply-selection %{
    evaluate-commands %sh{
        mode=$1
        case "$kak_buffile" in
            /*) ;;
            *) echo "fail 'magit-apply: not a file buffer'"; exit ;;
        esac
        bufdir=$(dirname "$kak_buffile")
        toplevel=$(cd "$bufdir" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)
        if [ -z "$toplevel" ]; then
            echo "fail 'magit-apply: not in a git repo'"
            exit
        fi
        if ! ( cd "$toplevel" && git ls-files --error-unmatch -- "$kak_buffile" ) >/dev/null 2>&1; then
            echo "fail 'magit-apply: file untracked'"
            exit
        fi
        buffile_relative=${kak_buffile#"$toplevel/"}

        case "$mode" in
            stage)    diff_args='HEAD';    apply_args='--cached' ;;
            unstage)  diff_args='--cached'; apply_args='--cached --reverse' ;;
            *)        echo "fail 'magit-apply: bad mode'"; exit ;;
        esac

        inserted=0
        deleted=0
        applied_any=0

        # Iterate over kak's selection descriptors: "L.C,L.C" pairs, space-sep.
        for sel in $kak_selections_desc; do
            anchor=${sel%%,*}
            cursor=${sel##*,}
            a_line=${anchor%%.*}
            c_line=${cursor%%.*}
            if [ "$a_line" -lt "$c_line" ]; then
                min=$a_line
                max=$c_line
            else
                min=$c_line
                max=$a_line
            fi

            # Full diff for this file (worktree-vs-HEAD for stage, index-vs-HEAD for unstage).
            diff=$(
                cd "$toplevel" && \
                git diff --no-ext-diff --no-color -U3 $diff_args -- "$buffile_relative" 2>/dev/null
            )
            [ -z "$diff" ] && continue

            # Slice to the selection range via kak's patch-range.pl.
            # -line-numbers-from-new-file: min/max refer to the +file side.
            sliced=$(
                printf '%s\n' "$diff" \
                | perl "${kak_runtime}/rc/tools/patch-range.pl" \
                       -line-numbers-from-new-file "$min" "$max" sh -c cat --
                printf .
            )
            sliced=${sliced%.}
            [ -z "$sliced" ] && continue

            # Apply.
            if ! printf '%s' "$sliced" | ( cd "$toplevel" && git apply $apply_args - ) 2>/dev/null; then
                echo "fail 'magit-apply: git apply failed'"
                exit
            fi
            applied_any=1

            # Count +/- lines for the final echo.
            ins=$(printf '%s\n' "$sliced" | awk '/^\+[^+]/ { n++ } END { print n+0 }')
            del=$(printf '%s\n' "$sliced" | awk '/^-[^-]/ { n++ } END { print n+0 }')
            inserted=$((inserted + ins))
            deleted=$((deleted + del))
        done

        if [ "$applied_any" -eq 0 ]; then
            echo "fail 'magit-apply: no changes in selection'"
            exit
        fi

        verb=Staged
        [ "$mode" = "unstage" ] && verb=Unstaged
        # Keep user-facing text free of literal braces (Lesson 24).
        OB=$(printf '\173'); CB=$(printf '\175')
        printf "echo -markup '%sInformation%s%s +%s -%s'\n" "$OB" "$CB" "$verb" "$inserted" "$deleted"
    }
    magit-refresh-after-mutation
}

# --- Quick previews -----------------------------------------------------
# Read-only scratch buffers showing common git output. Pattern parallels
# magit-blame-jump's scratch emission.

define-command magit-diff-staged -docstring 'Preview staged diff in a scratch buffer' %{
    evaluate-commands %sh{
        OB=$(printf '\173'); CB=$(printf '\175')
        bufdir=$(dirname "$kak_buffile" 2>/dev/null)
        [ -z "$bufdir" ] && bufdir=$PWD
        toplevel=$(cd "$bufdir" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)
        if [ -z "$toplevel" ]; then
            echo "fail 'magit-diff-staged: not in a git repo'"
            exit
        fi
        tmp=$(mktemp "${TMPDIR:-/tmp}/magit-diff-staged.XXXXXX")
        ( cd "$toplevel" && git diff --cached --no-color ) > "$tmp" 2>/dev/null
        if [ ! -s "$tmp" ]; then
            rm -f "$tmp"
            printf "echo -markup '%sInformation%sNothing staged'\n" "$OB" "$CB"
            exit
        fi
        printf "edit -scratch '*magit-diff-staged*'\n"
        printf "set-option buffer filetype git-diff\n"
        printf "map buffer normal q ': delete-buffer<ret>'\n"
        printf "map buffer normal '?' ': enter-user-mode magit-diff-view-keys<ret>'\n"
        printf "execute-keys '%%|cat %s<ret>gg'\n" "$tmp"
        printf "nop %%sh%s rm -f '%s' %s\n" "$OB" "$tmp" "$CB"
    }
}

define-command magit-log-line -docstring 'Show the last commit touching the line at cursor' %{
    evaluate-commands %sh{
        OB=$(printf '\173'); CB=$(printf '\175')
        case "$kak_buffile" in
            /*) ;;
            *) echo "fail 'magit-log-line: not a file buffer'"; exit ;;
        esac
        bufdir=$(dirname "$kak_buffile")
        toplevel=$(cd "$bufdir" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)
        if [ -z "$toplevel" ]; then
            echo "fail 'magit-log-line: not in a git repo'"
            exit
        fi
        if ! ( cd "$toplevel" && git ls-files --error-unmatch -- "$kak_buffile" ) >/dev/null 2>&1; then
            echo "fail 'magit-log-line: file untracked'"
            exit
        fi
        buffile_relative=${kak_buffile#"$toplevel/"}
        line=$kak_cursor_line
        tmp=$(mktemp "${TMPDIR:-/tmp}/magit-log-line.XXXXXX")
        ( cd "$toplevel" && git log -n 1 --no-color -L "${line},${line}:${buffile_relative}" ) > "$tmp" 2>/dev/null
        if [ ! -s "$tmp" ]; then
            rm -f "$tmp"
            printf "echo -markup '%sInformation%sNo commit touches this line'\n" "$OB" "$CB"
            exit
        fi
        printf "edit -scratch '*magit-log-line*'\n"
        # `git log -L` output is a commit header + unified diff of the
        # line range — `diff` filetype gets Helix tree-sitter highlighting.
        printf "set-option buffer filetype diff\n"
        printf "execute-keys '%%|cat %s<ret>gg'\n" "$tmp"
        printf "nop %%sh%s rm -f '%s' %s\n" "$OB" "$tmp" "$CB"
    }
}

# --- Hooks --------------------------------------------------------------
# Install gutter on any file buffer when shown/focused; refresh on
# reload or save. Tracked-file check lives inside magit-gutter-update.
hook -group magit-gutter global WinDisplay .* %{
    try %{ magit-gutter-show }
}

hook -group magit-gutter global FocusIn .* %{
    try %{ magit-gutter-update }
}

hook -group magit-gutter global BufReload .* %{
    try %{ magit-gutter-update }
}

hook -group magit-gutter global BufWritePost .* %{
    try %{ magit-gutter-update }
}

}
