---
name: desktop
description: "Full control of Saiful's Linux desktop (Fedora Asahi, niri and the Quickshell shell). Use whenever a task means touching the live session: open, launch, use or test any app (web app, browser page, CLI, TUI or GUI), drive an interactive program, type or click into a window, take a screenshot or check something on screen, unlock the session for a task, control volume, brightness, theme, media or wifi, or drive the shell's island, launcher, control panel and other surfaces. Triggers: 'open X', 'run X and ...', 'test X', 'click', 'type into', 'screenshot', 'check the screen', 'use the app', 'interact with', 'check the site', 'unlock'."
---

# desktop: drive this machine like Saiful does

This is Saiful's live session, not a sandbox. You share keyboard focus,
clipboard and windows with a person who may be typing at the same time, or
with nobody at all when he asks from his phone. niri 26.04 is the
compositor; the shell (Quickshell, unit `dots-shell.service`) draws the
island, the launcher, the panels and the lock.

## 1. Preflight: is the session locked?

```sh
dots-call lock state | jq '{locked, heldBy, leaseUntil}'
```

While locked, these still work: tmux, every `dots-call <target> state`,
`niri msg -j` queries, and `systemd-run --user`. Captures show only the lock
screen, `niri msg action` ignores all but power and VT actions, and wtype or
ydotool type into the lock's password field. So stay locked for text work,
and unlock only when the task needs pixels or input:

```sh
dots-call lock unlock claude 15    # a lease of 15 minutes; prints the state JSON, or {"error":"..."}
dots-call lock renew claude 15     # extends the lease you hold
```

Both exit 0 either way, so read the answer: `jq -e '.error | not'`.
`unlockedAt` and `leaseUntil` are milliseconds since the epoch
(`date -d @$((leaseUntil / 1000))`), 0 with no lease. Always pass the minutes. No lease ends later than 120 minutes after its
unlock. While the lease holds, idle does not lock; when it ends the session
locks again by itself. The monitors go off a second after an agent
unlock, so nothing shows on an empty desk. A dark output sends no frame
callbacks, so a client that waits for them (the shell, Qt apps) stops
redrawing and a capture shows its last frame; foot keeps drawing. When the
task needs pixels of such a window, light the desk first with `niri msg
action power-on-monitors`.

**Before each burst of input, read `lock state` again** and stop typing if
`locked` is true: the lease ended, or Saiful locked, and the next key would
land in the password field. Without a lease idle locks at 300 s, and wtype
may not count as activity. A `heldBy` with another name is another agent's
lease: do not lock or renew it under that agent.

Over SSH (`$SSH_CONNECTION` set) fish's `conf.d/ssh-desktop.fish` imports
`WAYLAND_DISPLAY` and `NIRI_SOCKET` from the live niri, so every tool here
works unchanged. No `NIRI_SOCKET` means no graphical session is up; say so.

## 2. Text before pixels

Pick the cheapest channel that answers the question. Screenshots cost real
money; command output is free.

| Surface | Channel |
|---|---|
| Windows, workspaces, outputs | `niri msg -j windows`, `focused-window`, `workspaces`, `outputs`, `layers` |
| The shell's surfaces | `dots-call <target> state` (JSON; see the IPC table) |
| CLI or TUI | tmux `send-keys` and `capture-pane` |
| GUI app | `~/.claude/skills/desktop/scripts/gui` over AT-SPI |
| Web page | `playwright-cli` (section 6) |

A megabyte of text is not free to read either: search it (`grep` a snapshot
file, `gui tree <app> | grep`) instead of dumping it, or hand the job to an
operator subagent (section 9).

### tmux for anything in a terminal

```sh
tmux new-session -d -s agent-x -x 200 -y 50
tmux send-keys -t agent-x 'mysql' Enter
sleep 1; tmux capture-pane -p -t agent-x
tmux kill-session -t agent-x                  # always
```

- To let Saiful watch: `niri msg action spawn -- foot tmux attach -t agent-x`.
  You keep driving with send-keys.
- Plain `capture-pane -p` drops colours, so a selected row is invisible.
  Before a destructive key, read `capture-pane -p -e` and find the
  reverse-video row with `\x1b\[[0-9;]*7m` (a highlight is often `[0;7m`).
- A fast string can outrun a TUI's palette or autocomplete: type, pause,
  capture, then Enter.
- An app with its own tmux server: `tmux -L <name> list-panes -a`, then
  `capture-pane`/`send-keys` against that socket.

### GUI apps by widget name

```sh
gui apps                      # apps on the a11y bus
gui tree <app>                # interactive widgets, coords, [checked,focused,...] flags
gui click <app> 'Save'        # activates it; the pointer never moves
gui type <app> 'Search' 'foo' # sets an entry's text
gui text <app>                # every readable string
```

An app missing from `gui apps`, or whose `tree` is empty (Qt Quick apps),
exposes nothing: use pixels. Chromium and Electron need
`--force-renderer-accessibility` to appear.

## 3. Pixels: grim, window shots, OCR

- Read the geometry first, never assume it:
  `niri msg -j outputs | jq -r '.[] | "\(.name) \(.logical.width)x\(.logical.height) @\(.logical.scale)"'`.
- A region, smallest that answers: `grim -s 1 -g "X,Y WxH" /tmp/s.png`, then
  Read it. `-s 1` makes image pixels equal pointer coordinates.
- Text on screen: OCR it instead of Reading the image,
  `grim -s 3 -g "X,Y WxH" - | tesseract stdin stdout`. tesseract misreads
  small text at its own size (`hi` as `ni`), so upscale it with `-s 3`.
- One window: `niri msg action screenshot-window --id N --path /tmp/desk/win.png`
  (an absolute path). It also replaces the clipboard.
- niri gives a window's size but not its position, so a crop of a tiled
  window is a guess. Fullscreen it first (`niri msg action fullscreen-window
  --id N`, the same call toggles back) and capture the output:
  `grim -o "$(niri msg -j focused-output | jq -r .name)" ...`.
- Shell surfaces are layers `dots-island`, `dots-surfaces`, `dots-margins`,
  `dots-paper` and `dots-dim`: check `niri msg -j layers` before trusting an
  empty shot. A surface closes on the next key or click, so chain open and
  grim in one call.

## 4. Input: wtype for keys, ydotool for buttons

- **Check focus first**, inside the same Bash call as the keys:
  `niri msg -j focused-window | jq '{id,app_id,title}'`. A miss lands your
  keys in Saiful's terminal or in this prompt.
- Text `wtype 'hello'`; keys `wtype -k Return`; chords
  `wtype -M ctrl -k s -m ctrl`.
- Pointer: `~/.claude/skills/desktop/scripts/mouse to X Y`, `click X Y
  [left|right|middle]`, `drag X1 Y1 X2 Y2`. Coordinates are `grim -s 1`
  pixels. It moves with wlrctl and holds buttons with ydotool, and it never
  rests on niri's top-left hot corner. Do not pin the pointer to a corner
  yourself.
- ydotool talks to `ydotoold.service` (a user unit, socket
  `$XDG_RUNTIME_DIR/.ydotool_socket`): `systemctl --user is-active ydotoold`.
  Use it only for buttons; `ydotool mousemove --absolute` is ignored by its
  relative device.
- Moving the pointer can close an open surface. Prefer `gui click`, which
  does not move it.
- When Saiful is active, do focus, check and type in one atomic call, and
  abort on a mismatch.

## 5. Launching apps

```sh
niri msg action spawn -- foot                                # a child of niri, focused when it maps
systemd-run --user --quiet --collect --property=ExitType=cgroup -- chromium-browser
# its own unit, which works while locked too; ExitType=cgroup keeps it up while any chromium process lives
```

Then wait for the window: `wlrctl toplevel waitfor app_id:<id>`. Check it
survived, not just that it flashed: after 3 s, `niri msg -j windows | jq -r
'.[].app_id'` still lists it.

**The worked example**, as one call so nothing types into the wrong window:

```sh
niri msg action spawn -- foot && sleep 1 &&
id=$(niri msg -j focused-window | jq -er 'select(.app_id == "foot") | .id') &&
[ "$(dots-call lock state | jq -r .locked)" = false ] &&
wtype 'echo hi' && wtype -k Return &&
niri msg action fullscreen-window --id "$id" && sleep 0.5 &&
text=$(grim -s 3 -o "$(niri msg -j focused-output | jq -r .name)" - | tesseract stdin stdout 2>/dev/null)
[ -n "$id" ] && niri msg action close-window --id "$id"
grep -xE '\s*hi\s*' <<<"$text"    # the last line, so the call's exit code is whether hi was read
```

## 6. Browser: playwright-cli

The `playwright-cli` skill has the full command list; read it rather than
guess flags. The `bin/playwright-cli` wrapper adds the machine's config to
`open` and `attach` and points the extension at Fedora's chromium, so pass
no `--config` of your own.

Saiful's own Chromium, with his logins, through the Playwright extension:

```sh
playwright-cli attach --extension=chromium     # session name: chromium
playwright-cli -s=chromium tab-new https://...
playwright-cli -s=chromium find "Orders"       # search the page, do not dump it
playwright-cli -s=chromium tab-close
playwright-cli -s=chromium detach              # never close, close-all or kill-all
```

`close` and `close-all` shut his browser and every tab in it. Locally
Chromium must be running (start it as above) and he clicks the extension's
Allow; over SSH the wrapper starts it and approves the attach with the
extension's token. Attach behind the lock is untested.

When the task needs no login, an isolated browser is safer and repeatable:
`playwright-cli -s=op open <url>` ... `playwright-cli -s=op close`.

A snapshot of a real page is a megabyte. Each action writes it to a file
under `.playwright-cli/` and prints the path: `find` or `grep` it. Snapshot
lines start with the role (`- button "Save"`), so never anchor with `^`.
`curl -s` answers most "is it up" questions with no browser at all.

## 7. The shell's IPC

`qs ipc show` lists the targets live. `dots-call <target> <function> [args]`
reaches them in about 4 ms and falls back to `qs ipc call`; a typed call
(`idle times`) goes straight to `qs ipc call idle times 5 10 20`.

| Target | Functions | What |
|---|---|---|
| `lock` | `state`, `lock`, `unlock <who> <min>`, `renew <who> <min>` | the session lock and its lease |
| `idle` | `state`, `times <dimS> <lockS> <offS>` | dim, lock and monitors-off steps |
| `island` | `state`, `focus` | the top island: clock, toasts, OSD, lease slot |
| `notifs` | `state`, `open`, `close`, `toggle`, `clear`, `dnd <bool>`, `toggleDnd` | notification centre |
| `launcher` | `state`, `open`, `close`, `toggle`, `mode <name>` | modes apps, windows, clipboard, emoji, calculator, commands |
| `control` | `state`, `open`, `close`, `toggle`, `section <name>` | sections audio, wifi, bluetooth, power, display, route |
| `themes` | `state`, `open`, `close`, `toggle` | the theme picker; `dots theme <name>` switches from a shell |
| `notes` | `state`, `open`, `toggle`, `pin`, `capture` | notes panel |
| `goals` | `state`, `open`, `close`, `toggle` | goals panel |
| `pass` | `state`, `open`, `close`, `toggle` | password picker |
| `cheatsheet` | `state`, `open`, `close`, `toggle` | keybind sheet |
| `record` | `state`, `toggle` | region recorder: picks, or stops a recording |
| `media` | `playPause`, `next`, `previous` | the current MPRIS player |
| `osd` | `brightness <step>` | brightness with its OSD, step like `5%+` |
| `margins` | `state` | the margin text on the focused output |
| `pinentry` | `state` | the gpg passphrase prompt |
| `polkit` | `state` | the polkit prompt |
| `shell` | `status` | theme, outputs, memory, sync |

The shell does not hot-reload QML: `systemctl --user restart dots-shell.service`.

Volume: `wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+`. Wifi: `nmcli`.
Clipboard: `wl-copy`, `wl-paste`. Change wifi, bluetooth or theme only when
asked, and put back what you change.

## 8. Done

Revert what you touched: windows, tmux sessions, focus, files, settings. If
you unlocked, lock again and darken the desk:

```sh
dots-call lock lock && niri msg action power-off-monitors
```

Kill what you spawned by pid or by its tmux session. Never `pkill -f
<pattern>` or `pgrep -f <pattern> | kill`: the pattern is in your own command
line, so it matches your own Bash tool and kills it.

## 9. Operators

A job of several steps goes to a Haiku subagent, which keeps every snapshot
and screenshot out of your context:

- `browser-operator`: a multi-step web job, isolated or in Saiful's Chromium.
- `desktop-operator`: a visual GUI job with no text channel. It drives
  `scripts/screen`, the computer-use action set (`shot`, `zoom`, `click`,
  `type`, `key`...) in screenshot pixels, which refuses input while `lock
  state` reads locked.

The brief names the goal, what counts as done, whether it needs Saiful's
login, and every text it may type and commit action it may take; it stops
at anything not named.

Anything that could wreck the live session (the lock itself, a shell crash,
a destructive keybind) is tested in the nested session: `bin/dots-dev` in
`~/Codes/dotfiles` starts it and prints the env to source. With it sourced,
niri msg, dots-call, qs ipc, grim, wtype and wlrctl act on the nested
session; ydotool does not, since ydotoold's device reaches the live one, so
leave `mouse drag` and `screen drag`, the two that press through it, alone
there. Clicks and scrolls go through wlrctl and work. The nested lock's
password is `dots-test-pass`.
