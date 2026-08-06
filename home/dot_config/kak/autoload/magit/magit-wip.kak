# magit-wip.kak — auto-snapshot worktree+index into refs/wip/wtree/<branch>
# on every BufWritePost. Recoverable via `git reflog refs/wip/wtree/<branch>`.

provide-module magit-wip %{

declare-option bool magit_wip_enabled true
declare-option -hidden str magit_wip_ref_prefix 'refs/wip/wtree'

define-command magit-wip-toggle -docstring 'toggle WIP auto-snapshot' %{
    evaluate-commands %sh{
        if [ "$kak_opt_magit_wip_enabled" = "true" ]; then
            printf "set-option global magit_wip_enabled false\n"
            printf "echo -markup %%{{Information}WIP: off}\n"
        else
            printf "set-option global magit_wip_enabled true\n"
            printf "echo -markup %%{{Information}WIP: on}\n"
        fi
    }
}

define-command -hidden magit-wip-record %{
    evaluate-commands %sh{
        [ "$kak_opt_magit_wip_enabled" = "true" ] || exit 0
        f=$kak_buffile
        [ -n "$f" ] || exit 0
        case "$f" in \**) exit 0 ;; esac
        dir=$(dirname "$f")
        [ -d "$dir" ] || exit 0
        top=$(cd "$dir" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)
        [ -n "$top" ] || exit 0
        if br=$(cd "$top" && git symbolic-ref --short HEAD 2>/dev/null); then :; else br=HEAD; fi
        # stash create: produces a commit of worktree+index without touching
        # the stash stack or the worktree. Returns empty sha if no changes.
        snap=$(cd "$top" && GIT_EDITOR=true git stash create 2>/dev/null)
        [ -n "$snap" ] || exit 0
        ref="$kak_opt_magit_wip_ref_prefix/$br"
        old=$(cd "$top" && git rev-parse -q --verify "$ref" 2>/dev/null || true)
        err=$(mktemp "${TMPDIR:-/tmp}/magit-wip-err.XXXXXX")
        base=$(basename "$f")
        msg="WIP on $br: save $base"
        if [ -n "$old" ]; then
            ( cd "$top" && git update-ref --create-reflog -m "$msg" "$ref" "$snap" "$old" >/dev/null 2>"$err" )
        else
            ( cd "$top" && git update-ref --create-reflog -m "$msg" "$ref" "$snap" >/dev/null 2>"$err" )
        fi
        rm -f "$err"
    }
}

hook -group magit-wip global BufWritePost .* %{
    try %{ magit-wip-record }
}

}
