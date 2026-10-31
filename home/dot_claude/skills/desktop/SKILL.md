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

`~/.claude/skills/desktop/scripts/screen doctor` answers that and the rest
in one JSON object: the lock and its lease, niri's socket and outputs,
whether the a11y bus answers, which input tools are there, `blockers`, and
one `next` step for the first of them. It exits 1 while anything blocks.

While locked, these still work: tmux, every `dots-call <target> state`,
`niri msg -j` queries, and `systemd-run --user`. Captures show only the lock
screen, `niri msg action` ignores all but power and VT actions, and any key
typed lands in the lock's password field. So stay locked for text work,
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

`screen`, `mouse` and `gui` read `lock state` before every input and refuse
with exit 3 while it is locked, so a lease that ended mid-job stops you; hand
back instead of renewing past the brief. Without a lease idle locks at 300 s. A `heldBy` with another name is another agent's
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
file, `gui tree <app> | jq`) instead of dumping it, or hand the job to an
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
gui tree <app>                # JSON: interactive widgets, boxes, checked/focused/... states
gui click <app> 'Save'        # activates it, then reads it back for "delivery"
gui type <app> 'Search' 'foo' # sets an entry's text, the same way
gui get <app> 'Search' text   # one of text, states or box; all three without it
gui check <app> 'Wrap'        # ticks a check box once; already ticked says "already": true (uncheck clears)
gui tree <app> --depth 3      # three levels down; a cut node shows children_count, --root <ref> opens it
gui wait <app> --gone 'Open'  # until no widget is named so; also --text T, --state <ref> <state>
gui text <app>                # every readable string
```

`click` and `type` read the widget after they act, from 300 ms to 2 s:
`"delivery": "verified"` the field reads the text, or a check box, toggle or
expander changed state; `"not_delivered"` nothing changed or the widget
refused, exit 1, the only answer with `"retry_safe": true`; `"unverified"`
anything else, a plain button's click among them. An unverified action may
still land (an app that stopped applies it when it resumes), so never send
it again: look with `gui tree` or a shot. `type` refuses a field that is not
editable, or is read-only, with exit 3, and the typed text never appears in
the output or the journal, only `"matched"`; `get` withholds a password
field's text. A GTK4 check box offers no action at all, so `click` exits 4
on it: use pixels. A GTK4 widget's `box` is where its window sits by niri:
in a tiled window it is `null` with `"box_reason": "no window position"`,
so float the window (`niri msg action toggle-window-floating --id N`) for
boxes.

Wait on the tree, never with `sleep`: `wait` polls every 100 ms for 10 s
(`--timeout S`, 60 at most) and exits 1 with the last state it saw.
`--gone` first sees the thing, or waits 2 s, so it is safe right after the
click that opens it: a menu shows up to 0.7 s after its opener.

Each `tree` node has a `"ref"` such as `s3fa1:42`; pass it where a text
goes (`gui click <app> s3fa1:42`) to reach a widget with no name, or one of
several alike. A ref keeps for an hour, and only while the app keeps that
widget where it was: after a page switch or a closed dialog it answers
`{"stale": "<cause>"}`, exit 4, and acts on nothing; take a fresh `tree`.
A text that matches two or more widgets a person would act on answers
`{"ambiguous": [...]}` with up to 10 refs, exit 4; pick one by its ref.

`tree` prints at most 1000 nodes and 32 KB; a longer tree is written whole
to the file its `"spill"` names, with the same `i` and `ref` for each node.
Read the file with `jq`, not whole.

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
- niri places a floating window (`layout.tile_pos_in_workspace_view` in
  `niri msg -j windows`) but gives no position for a tiled or fullscreen
  one, so a crop of a tiled window is a guess. Fullscreen it first (`niri msg action fullscreen-window
  --id N`, the same call toggles back) and capture the output:
  `grim -o "$(niri msg -j focused-output | jq -r .name)" ...`.
- Shell surfaces are layers `dots-island`, `dots-surfaces`, `dots-margins`,
  `dots-paper` and `dots-dim`: check `niri msg -j layers` before trusting an
  empty shot. A surface closes on the next key or click, so chain open and
  grim in one call.

## 4. Input: only through the scripts

Send keys and clicks only through `scripts/screen`, `scripts/mouse` and
`scripts/gui`. Never use bare `wtype`, `wlrctl` or `ydotool` for text or
clicks: they skip the lock, prompt and window checks the scripts make.
(`ydotool` stays only for a keyboard bind that needs uinput, a real Mod bind.)

- Keys: `screen type TEXT` (newlines dropped), `screen key Return`,
  `screen key ctrl+s`, `screen key Tab 3` (repeat 1-50). Each key is gated
  alone and the first into a new window is primed for you; do not prime.
  No combo is blocked: niri runs no bind from the virtual keyboard
  `screen key` types on, so a Mod combo reaches the window as plain keys
  and fires nothing of niri's, and keys go only to an agent window anyway.
- Pointer: `screen click|move|drag|scroll` in `screen shot` pixels, or
  `scripts/mouse to|click|drag|scroll X Y` in `grim -s 1` pixels. It never
  rests within 2 px of an edge, where the hot corners are.
- **Look in the same call.** Every acting command of `screen`, `mouse` and
  `gui` takes `--then shot|windows|tree` last: it acts, waits until two
  frames 100 ms apart match, and adds the look to its JSON, as in
  `{"stable": true, "shot": "/tmp/desk/shot.png"}`. `"stable": false` means
  the screen still moved 2 s after the call (a spinner), which is no failure.
  After `screen launch` it may look before the window maps: `screen wait`.
- **Confinement.** Keys go only into windows `screen launch` opened (or a
  dialog an agent action opened within 5 s), clicks only over them. Anything
  else exits 3 with `{"refused":"not an agent window",...}`. `--any` lifts
  only that, never the lock or a prompt; pass it only when the brief grants it.
- **Auth prompt.** A polkit or pinentry password prompt refuses every input,
  `--any` or not. Stop and hand the task back to Saiful; never type a password.
- **JEV.** `screen find "<thing>" --jev` takes a fresh shot (the last shot)
  and prints `{"x":..,"y":..,"confidence":..,"on_screen":..}`, the point in
  shot pixels; exit 4 with `{"found":false,"on_screen":p}` when it is not on
  screen. Name the thing by text it shows (`"the entry that says Search"`),
  not by its order: a Box for "the first entry" over two alike lands between
  them. `screen check "<yes-or-no question>" --jev` prints
  `{"yes":true|false,"probability":p}`, exit 0 either way. Pass `--jev` only
  when the brief says "JEV allowed": each call sends a screenshot off the
  machine, to OpenRouter and TypeSafe, on Saiful's credits. Without it, exit 3
  `{"refused":"jev not granted"}`. On exit 1, fall back to `gui find`,
  `gui tree` or OCR of `screen zoom`; never retry JEV in a loop.
- Moving the pointer can close an open surface. Prefer `gui click`.

Refusal reasons, the journal and the rest: [reference.md](reference.md).

## 5. Launching apps

```sh
screen launch foot                                           # for anything you will type into or click
systemd-run --user --quiet --collect --property=ExitType=cgroup -- chromium-browser
# not an agent window; for background apps: its own unit, which works while locked too; ExitType=cgroup keeps it up while any chromium process lives
```

Then wait for the window, never with `sleep`: `screen wait window-open --app
<id>` prints its JSON the moment niri opens it, or at once with `"already":
true`. It also waits for `window-closed --id N`, `focus --id N`, `title --id
N --matches RE`, `workspace N` and `overview open|closed`, 10 s by default
(`--timeout` up to 60), and exits 1 with the last state it saw. Check it
survived, not just that it flashed: after 3 s, `niri msg -j windows | jq -r
'.[].app_id'` still lists it.

**The worked example**, as one call so nothing types into the wrong window:

```sh
screen=~/.claude/skills/desktop/scripts/screen
$screen launch foot -a agent-hi &&
id=$($screen wait window-open --app agent-hi | jq -er .window.id) &&
$screen wait focus --id "$id" >/dev/null &&
$screen type 'echo hi' && $screen key Return &&
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
  `type`, `key`...) in screenshot pixels, which refuses input while the
  session is locked or an auth prompt is open.

The brief names the goal, what counts as done, whether it needs Saiful's
login, and every text it may type and commit action it may take, and whether
it may pass `--any` or "JEV allowed"; it stops at anything not named.

Anything that could wreck the live session (the lock itself, a shell crash,
a destructive keybind) is tested in the nested session: `bin/dots-dev` in
`~/Codes/dotfiles` starts it and prints the env to source. With it sourced,
niri msg, dots-call, qs ipc, grim and dots-pointer act on the nested
session, so `mouse` and `screen` work there, drags included; ydotool does
not, since ydotoold's device reaches the live one. The nested lock's
password is `dots-test-pass`.
