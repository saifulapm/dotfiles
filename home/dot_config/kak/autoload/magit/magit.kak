# magit.kak — entry point. Sources the per-subsystem modules in dependency
# order. Shared state (options, faces, refresh, modeline-update, transient-
# toggle primitive) lives in this file; module-specific code (status, branch,
# commit, transients, show helpers) lives in `magit-<subsystem>.kak`.

declare-option -hidden str magit_version "0.1-phase1"

# --- State --------------------------------------------------------------
# Per-status-buffer line→(section, file, file_line) map. Populated at render.
# Format: str-list, one entry per buffer line: "section|file|file_line".
# section ∈ {head, untracked, unstaged, staged, recent, recent-commit,
#            stash, stash-entry, unpulled, unpulled-commit,
#            unpushed, unpushed-commit, rebase-progress, rebase-todo-line,
#            blank, unstaged-hunk, unstaged-line, unstaged-ctx,
#            staged-hunk,   staged-line,   staged-ctx}
declare-option -hidden str-list magit_status_linemap

# Per-transient accumulated args. One option per transient name.
declare-option -hidden str magit_commit_args ""

# Folded section kinds (space-separated). Entries: top-level section kind
# (head, untracked, unstaged, staged, stash, unpulled, unpushed, recent,
# rebase-progress). Consulted by magit-status-render.
declare-option -hidden str magit_status_collapsed ""

# Hooks/refresh bookkeeping
declare-option -hidden bool magit_in_refresh false

# --- Faces --------------------------------------------------------------
# Syntax: [fg][,bg][+attrs][@base]
set-face global MagitSection       '+b@header'
set-face global MagitFile          '+b'
set-face global MagitBranchLocal   green
set-face global MagitBranchRemote  cyan
set-face global MagitHunkHeader    cyan

# --- Refresh contract ---------------------------------------------------
# Called by every mutating magit-* command. Updates *magit-status* if open,
# and refreshes git_diff_flags in every open tracked-file buffer.
define-command -hidden magit-refresh-after-mutation %{
    try %{
        # If *magit-status* is open somewhere, re-render it.
        evaluate-commands -buffer '*magit-status*' magit-status-render
    }
    # Refresh the diff gutter in every open buffer. `-buffer *` is not a
    # wildcard; we iterate %val{buflist} via the quoted form and emit one
    # per-buffer command.
    evaluate-commands %sh{
        eval set -- "$kak_quoted_buflist"
        for buf; do
            printf "try %%{ evaluate-commands -buffer '%s' magit-gutter-update }\n" "$buf"
        done
    }
}

# --- Transient framework (flag-toggle) ---------------------------------
# Each transient is a pair: (user-mode <name> for keybindings, option <name>_args
# for accumulated flags). The dispatcher draws an info box summarizing the
# current flag state, then enters the user-mode with -lock. Keys in the
# user-mode either toggle a flag (re-drawing the info box) or fire an action.
#
# Toggle semantics: if FLAG is present in the args option, remove it; else
# append it (space-separated).

define-command magit-transient-toggle -params 2 -docstring 'toggle FLAG in OPT' %{
    # Two-phase toggle: phase 1 (this command) stashes the current option
    # value into register z so kakscript's %opt expansion gives us the
    # authoritative current value. Phase 2 (magit-transient-toggle-do) reads
    # the register in shell, computes, writes back via set-option.
    evaluate-commands -save-regs z %{
        # Build a dynamic kakscript line that expands %opt{$1} at emit time.
        evaluate-commands %sh{
            OB=$(printf '\173')
            CB=$(printf '\175')
            # set-register z %opt{OPTNAME} — OPTNAME comes from $1.
            printf 'set-register z %%opt%s%s%s\n' "$OB" "$1" "$CB"
        }
        magit-transient-toggle-do %arg{1} %arg{2}
    }
}

# Internal: reads the current option value from register z.
define-command -hidden magit-transient-toggle-do -params 2 %{
    evaluate-commands %sh{
        opt=$1
        flag=$2
        cur=$kak_reg_z
        case " $cur " in
            *" $flag "*)
                new=""
                for tok in $cur; do
                    [ "$tok" = "$flag" ] && continue
                    new="$new $tok"
                done
                new=${new# }
                ;;
            *)
                if [ -z "$cur" ]; then new=$flag; else new="$cur $flag"; fi
                ;;
        esac
        OB=$(printf '\173')
        CB=$(printf '\175')
        printf 'set-option global %s %%%s%s%s\n' "$opt" "$OB" "$new" "$CB"
    }
}

# magit-diff-dispatch: shipped in magit-diff module.
# magit-log: shipped in magit-log module.

# --- Lazy-loaded transients --------------------------------------------
# magit-transients is by far the heaviest module (~1100 lines, 52 commands)
# and evaluating its body at startup roughly DOUBLES Kakoune launch time.
# Nothing in it is needed until the user actually opens a push / pull /
# reset / remote / diff / log transient, so we defer
# `require-module magit-transients` until first use instead of running it
# on KakBegin.
#
# IMPORTANT: provide-module bodies are re-evaluated "as if by source" on
# first require-module, and the module's own `define-command`s do NOT use
# `-override`. So we must NOT pre-define any name the module defines
# (magit-modeline-update, magit-*-dispatch, …) — doing so makes
# require-module fail with "command already defined". Instead we expose
# *new* loader command names and point the keybindings / transient
# entry points at those. Each loader requires the module (idempotent —
# a no-op once loaded) then calls the real command, which exists by then.
#
# Entry points that reach transients (bound by the user's keymap — see the
# suggested bindings in README.md — or called from sibling modules):
#   magit-{push,pull,reset,remote}-dispatch  -> bound to keys directly
#   magit-modeline-update                    -> called by diff/log/commit
#                                                transient command bodies

define-command -hidden magit-transients-ensure -docstring 'Load the magit-transients module on first use' %{
    require-module magit-transients
}

# Loader entry points (distinct names — no collision with the module).
# magit-transients defines/generates these 11 *-dispatch commands:
#   push pull reset remote fetch merge cherry revert rebase tag stash
# The suggested keymap (README.md) binds keys to the -transient loaders
# below instead, so the module loads on first key press, then the real
# *-dispatch runs.
define-command magit-push-transient   -docstring 'Magit push transient'       %{ magit-transients-ensure; magit-push-dispatch }
define-command magit-pull-transient   -docstring 'Magit pull transient'       %{ magit-transients-ensure; magit-pull-dispatch }
define-command magit-reset-transient  -docstring 'Magit reset transient'      %{ magit-transients-ensure; magit-reset-dispatch }
define-command magit-remote-transient -docstring 'Magit remote transient'     %{ magit-transients-ensure; magit-remote-dispatch }
define-command magit-fetch-transient  -docstring 'Magit fetch transient'      %{ magit-transients-ensure; magit-fetch-dispatch }
define-command magit-merge-transient  -docstring 'Magit merge transient'      %{ magit-transients-ensure; magit-merge-dispatch }
define-command magit-cherry-transient -docstring 'Magit cherry-pick transient' %{ magit-transients-ensure; magit-cherry-dispatch }
define-command magit-revert-transient -docstring 'Magit revert transient'     %{ magit-transients-ensure; magit-revert-dispatch }
define-command magit-rebase-transient -docstring 'Magit rebase transient'     %{ magit-transients-ensure; magit-rebase-dispatch }
define-command magit-tag-transient    -docstring 'Magit tag transient'        %{ magit-transients-ensure; magit-tag-dispatch }
define-command magit-stash-transient  -docstring 'Magit stash transient'      %{ magit-transients-ensure; magit-stash-dispatch }

# magit-diff / magit-log / magit-commit transient command bodies call
# `magit-modeline-update` (defined in magit-transients). Their dispatch
# commands call `magit-modeline-update-safe` instead, which loads the
# module first so the real command is present when invoked.
define-command -hidden magit-modeline-update-safe -docstring 'Ensure transients loaded, then refresh modeline' %{
    magit-transients-ensure
    magit-modeline-update
}

# --- Sub-modules --------------------------------------------------------
# Each sub-module file contains `provide-module NAME %{ ... }`. This file
# triggers their execution via `require-module`. Three loaders need to
# work:
#   1. kak-bundle (recommended): sources every .kak file under the cloned
#      repo alphabetically. magit-*.kak sort BEFORE magit.kak (because `-`
#      sorts before `.`), so every sibling has registered its provide-module
#      by the time magit.kak runs. The top-level `require-module` calls
#      below succeed synchronously.
#   2. Real kakoune autoload: kakoune loads `autoload/tools/*.kak` at
#      startup. Processing order is filesystem-readdir — usually but NOT
#      GUARANTEED to be alphabetical (e.g. APFS inode-order). If kakoune
#      reaches magit.kak before a sibling, the require-module call fails
#      silently. Deferring to KakBegin guarantees all autoload has completed.
#   3. Test harness / manual `source`: sources each magit-*.kak explicitly,
#      then sources magit.kak. By that point KakBegin has already fired
#      (it runs once, during kak's own startup), so only the top-level
#      calls apply.
# All three paths use `try %{ require-module ... }` so calling it twice
# (once top-level, once on KakBegin) is a safe no-op — the second call
# fails harmlessly because the module is already loaded.
try %{ require-module magit-git }
try %{ require-module magit-show }
try %{ require-module magit-status }
try %{ require-module magit-branches }
try %{ require-module magit-commit }
# magit-transients is lazy-loaded — see "Lazy-loaded transients" above.
try %{ require-module magit-rebase }
try %{ require-module magit-conflict }
try %{ require-module magit-log }
try %{ require-module magit-reflog }
try %{ require-module magit-diff }
try %{ require-module magit-file }
try %{ require-module magit-worktree }
try %{ require-module magit-submodule }
try %{ require-module magit-wip }
try %{ require-module magit-bisect }
try %{ require-module magit-clone }
try %{ require-module magit-gitignore }
try %{ require-module magit-patch }
hook -once global KakBegin .* %{
    try %{ require-module magit-git }
    try %{ require-module magit-show }
    try %{ require-module magit-status }
    try %{ require-module magit-branches }
    try %{ require-module magit-commit }
    # magit-transients is lazy-loaded — see "Lazy-loaded transients" above.
    try %{ require-module magit-rebase }
    try %{ require-module magit-conflict }
    try %{ require-module magit-log }
    try %{ require-module magit-reflog }
    try %{ require-module magit-diff }
    try %{ require-module magit-file }
    try %{ require-module magit-worktree }
    try %{ require-module magit-submodule }
    try %{ require-module magit-wip }
    try %{ require-module magit-bisect }
    try %{ require-module magit-clone }
    try %{ require-module magit-gitignore }
    try %{ require-module magit-patch }
}
