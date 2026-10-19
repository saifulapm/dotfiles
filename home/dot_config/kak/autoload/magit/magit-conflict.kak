# magit-conflict.kak — helpers for resolving merge conflict markers.
# Operates on whichever conflicted file the user has open; not tied to
# *magit-status*. Handles both the default 2-way and diff3-style 3-way
# marker formats:
#
#   2-way (merge.conflictStyle = merge, default):
#     <<<<<<< <label>
#     our side
#     =======
#     their side
#     >>>>>>> <label>
#
#   3-way (merge.conflictStyle = diff3 / zdiff3):
#     <<<<<<< <label>
#     our side
#     ||||||| <base-label>
#     merged common ancestor
#     =======
#     their side
#     >>>>>>> <label>
#
# For diff3, the base section is always discarded — `ours` keeps only
# lines between `<<<<<<<` and `|||||||`, `both` concatenates ours+theirs
# (skipping base).
#
# Resolution strategy: write the buffer to disk, mutate with awk given
# the cursor line number, replace buffer contents via %|cat<ret>gg.
# `edit!` would discard unsaved changes — we want the user's in-progress
# edits preserved, so we flush-then-replace.

provide-module magit-conflict %{

# Navigation: set the search register to a plain regex (avoiding `<` in
# the execute-keys arg, which would otherwise be parsed as key-syntax),
# then let `n` / `<a-n>` drive the search.
define-command magit-conflict-next -docstring 'Jump to next conflict marker' %{
    set-register / '^<<<<<<<'
    try %{ execute-keys n } catch %{ echo -markup '{Information}no more conflicts' }
}

define-command magit-conflict-prev -docstring 'Jump to previous conflict marker' %{
    set-register / '^<<<<<<<'
    try %{ execute-keys '<a-n>' } catch %{ echo -markup '{Information}no more conflicts' }
}

# Shared runner: $1 = 'ours' | 'theirs' | 'both'. Writes buffer, mutates
# via awk, reloads via cat-replace. Awk finds the conflict whose
# <<<<<<< is <= cursor_line AND >>>>>>> is >= cursor_line; if the cursor
# isn't inside any conflict, it fails clearly.
define-command -hidden -params 1 magit-conflict-resolve %{
    write
    evaluate-commands %sh{
        mode=$1
        line=$kak_cursor_line
        f=$kak_buffile
        tmp=$(mktemp "${TMPDIR:-/tmp}/magit-conflict.XXXXXX")
        awk -v line="$line" -v mode="$mode" '
            # State machine across the file:
            #   state 0  = outside a conflict
            #   state 1  = between <<<<<<< (start) and ||||||| (base) or ======= (mid)
            #   state 1b = between ||||||| (base) and ======= (mid) — diff3 only
            #   state 2  = between ======= and >>>>>>> (end)
            # `base` is 0 in 2-way merges, >0 in diff3. `emit_ours` uses
            # `base` as upper bound if set, else `mid`.
            BEGIN { state = 0; start = 0; base = 0; mid = 0; found = 0 }
            function is_target() { return line >= start && line <= NR }
            function ours_end()     { return (base > 0) ? base : mid }
            function emit_ours()    { for (i = start + 1; i < ours_end(); i++) print saved[i] }
            function emit_theirs()  { for (i = mid + 1;   i < NR;  i++) print saved[i] }
            function emit_verbatim() {
                for (i = start; i <= NR; i++) print saved[i]
            }
            /^<<<<<<</ && state == 0 {
                state = 1; start = NR; saved[NR] = $0; next
            }
            /^\|\|\|\|\|\|\|/ && state == 1 {
                state = 1; base = NR; saved[NR] = $0; next
            }
            /^=======/ && (state == 1) {
                state = 2; mid = NR; saved[NR] = $0; next
            }
            /^>>>>>>>/ && state == 2 {
                saved[NR] = $0
                if (!found && is_target()) {
                    found = 1
                    if (mode == "ours"  || mode == "both") emit_ours()
                    if (mode == "theirs" || mode == "both") emit_theirs()
                } else {
                    emit_verbatim()
                }
                # Clear accumulated lines for the next conflict.
                for (k in saved) delete saved[k]
                state = 0; start = 0; base = 0; mid = 0
                next
            }
            {
                if (state == 0) print $0
                else            saved[NR] = $0
            }
            END {
                if (!found) exit 42
            }
        ' "$f" > "$tmp"
        rc=$?
        if [ "$rc" = 42 ]; then
            rm -f "$tmp"
            echo "fail 'magit-conflict: cursor not inside a conflict block'"
            exit
        fi
        OB=$(printf '\173')
        CB=$(printf '\175')
        # Replace buffer contents. Lesson 27: %|<cmd><ret>gg is the recipe;
        # no trailing d/esc (d would eat the first char).
        printf "execute-keys %%%s%%|cat %s<ret>gg%s\n" "$OB" "$tmp" "$CB"
        # Save so the on-disk file reflects the resolution (matches the
        # expectation that editing a conflicted file and resolving leaves
        # the worktree in a committable state).
        printf "write\n"
        # The tempfile is no longer needed after cat replaces contents.
        printf "nop %%sh%sRM=%s; rm -f \"\$RM\"%s\n" "$OB" "$tmp" "$CB"
        printf "echo -markup %%%s{Information}resolved conflict: %s%s\n" "$OB" "$mode" "$CB"
    }
}

define-command magit-conflict-ours   -docstring 'Keep ours (between <<<<<<< and =======)'     %{ magit-conflict-resolve ours }
define-command magit-conflict-theirs -docstring 'Keep theirs (between ======= and >>>>>>>)'   %{ magit-conflict-resolve theirs }
define-command magit-conflict-both   -docstring 'Keep both sides, strip markers only'         %{ magit-conflict-resolve both }

}
