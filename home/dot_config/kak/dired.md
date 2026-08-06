# Dired for Kakoune — Design Notes

Port of Emacs dired to kakoune, following the same conventions as the in-progress
magit-for-kakoune port (`autoload/tools/magit*.kak`).

## Feasibility

Dired is simpler in scope than magit. The magit port is the harder precedent —
dired reuses the same infrastructure (scratch buffers, user-modes, linemap,
refresh contract, async sentinel plumbing).

### What ports cleanly
- Buffer-as-directory-listing (kakoune scratch buffer with `ls -la` output)
- Single-key commands on lines (`d` mark delete, `R` rename, `C` copy, `!` shell
  command, `+` mkdir)
- Marking with `m`/`u`, acting on marked set
- `g` to refresh, `^` to go up, Enter to open
- Wdired-style editable rename (edit buffer → save → batch rename)

### What's awkward in kakoune
- Kakoune's modal model doesn't have emacs's "buffer-local keymaps" in the same
  way. Lean on `declare-user-mode dired` + hooks that bind keys only in that
  mode, as the magit port does.
- Dired-X, tramp integration, image-dired, virtual dired — deep emacs-isms.
  Skip or stub.
- Async operations need the same sentinel/wait plumbing already built for magit
  (`magit_wait_idle`). Reuse the harness.

### Goal
Don't aim for "exactly same as emacs" — aim for dired's *model*: buffer is the
filesystem, keys are verbs, marks compose with verbs. That's the 20% that
delivers 80% of dired's feel. Literal keybinding parity and every-command-ported
is where emacs ports usually die.

---

## File layout

```
autoload/tools/
  dired.kak              # entry: faces, shared options, module-requires
  dired-buffer.kak       # render & line-map (mirrors magit-status-render)
  dired-ops.kak          # mark/unmark/delete/rename/copy/chmod/shell
  dired-wdired.kak       # editable-rename mode (the killer feature)
```

Roughly 600–900 lines total. Much smaller than magit — no git plumbing, no
transients, no diff parsing.

---

## Core design

**Buffer:** `*dired: /abs/path*` — one per directory visited. Scratch, readonly
by default.

**Line map** (same pattern as `magit_status_linemap`):

```kak
declare-option -hidden str-list dired_linemap  # per line: "kind|name|size|perms"
declare-option -hidden str dired_path           # buffer-local dir
declare-option -hidden str dired_marked         # newline-joined marked names
```

**User mode** (mirrors `magit-status`):

```kak
declare-user-mode dired
# In the buffer-open hook:
map buffer normal <ret> ': dired-visit<ret>'
map buffer normal ^    ': dired-up<ret>'
map buffer normal g    ': dired-revert<ret>'
map buffer normal m    ': dired-mark<ret>'
map buffer normal u    ': dired-unmark<ret>'
map buffer normal d    ': dired-flag-delete<ret>'
map buffer normal x    ': dired-execute-flags<ret>'   # apply deletes
map buffer normal R    ': dired-rename<ret>'
map buffer normal C    ': dired-copy<ret>'
map buffer normal D    ': dired-delete<ret>'
map buffer normal +    ': dired-mkdir<ret>'
map buffer normal !    ': dired-shell-command<ret>'
map buffer normal %%s  ': dired-regexp-mark<ret>'
map buffer normal W    ': dired-wdired-start<ret>'    # the big one
```

---

## Reusing existing magit infrastructure

- **Async/sentinel plumbing** — `magit_wait_idle`/`magit_wait_autosquash`
  primitives plug straight in for shell ops (recursive delete, big copies). Per
  memory note `feedback_test_sync.md`, the 8 sync gotchas are already solved;
  dired benefits for free.
- **Refresh contract** — `dired-refresh-after-mutation` is a near-copy of
  `magit-refresh-after-mutation`, but iterates any `*dired: *` buffers whose
  path matches or is a parent of the mutated path.
- **Render pattern** — `dired-revert` = read dir, rebuild linemap, replace
  buffer contents, restore cursor on same filename if possible. Exact shape of
  `magit-status-render`.

---

## The one hard part: wdired

Emacs wdired toggles the buffer editable, user edits filenames inline, `C-c C-c`
commits as batch rename. To port:

1. `dired-wdired-start` snapshots current linemap → `dired_wdired_snapshot`,
   sets buffer modifiable, drops readonly highlighting.
2. `dired-wdired-finish` diffs current buffer lines against snapshot by position
   → emits `mv` per changed name → calls `dired-revert`.
3. **Guardrail:** if line count changed, refuse (user deleted/added lines).
   Emacs has the same rule.

This is the feature that makes dired feel magical; worth getting right.

---

## What to skip on v1

- Tramp (remote dirs)
- image-dired
- `find-dired`
- dired-x omit-files
- Subdir insertion (`i` — inline subtree under current dir)

Add later if desired. Dired-X is a rabbit hole.

---

## Suggested build order

1. **`dired-buffer.kak`** — render, linemap, `dired`/`dired-visit`/`dired-up`/
   `dired-revert`. Result: working file browser.
2. **Marks + delete** (`m`, `u`, `d`, `x`, `D`). Most common daily flow.
3. **`R`/`C`/`+`/`!`** — rename, copy, mkdir, shell command. Covers ~90% of
   emacs dired usage.
4. **wdired.** The differentiator.
5. **Sort toggles, hidden-file toggle (`.`), regexp mark (`%m`).**
