---
name: desktop
description: "Full control of Saiful's Linux desktop (Fedora Asahi + niri + quickshell). Use whenever a task means touching the live session: open/launch/use/test any app — web app, browser page, CLI, TUI, or GUI — drive an interactive program, type or click into a window, take a screenshot or verify something on screen, control volume/brightness/theme/media/wifi, or drive the qshell bar/menu/panels. Triggers: 'open X', 'run X and …', 'test X', 'click', 'type into', 'screenshot', 'check the screen', 'use the app', 'interact with', 'check the site'."
---

# desktop — drive this machine like the user does

This is Saiful's **live session**, not a sandbox. You share keyboard focus,
clipboard, and windows with a person who may be typing at the same time.
Everything below is verified on this machine (niri 26.04, quickshell 0.3,
eDP-1 at 1706x1066 logical / scale 1.5, qshell bar = top 26px strip).

## Golden rules

1. **Text before pixels.** `tmux capture-pane`, `niri msg -j …`, `qs ipc`,
   and command output are free; screenshots cost real money. Screenshot only
   when a question is genuinely visual.
2. **Never capture the full screen at native scale.** Always
   `grim -s 1 -g "X,Y WxH" /tmp/shot.png` — the smallest region that answers
   the question. `-s 1` maps image pixels 1:1 to logical/pointer coordinates.
3. **If the answer is text on screen, OCR it instead of Reading the image:**
   `grim -g "X,Y WxH" - | tesseract stdin stdout` → plain text, no vision
   tokens. OCR captures omit `-s 1` on purpose — tesseract needs the native
   1.5x pixels for small fonts (verified: the bar clock reads at native,
   nothing at `-s 1`).
4. **Check focus before injecting input.** `wtype` and `wlrctl` go to
   whatever has keyboard focus / is under the pointer. A miss lands your
   keystrokes in the user's terminal or Claude prompt.
5. **Clean up what you spawn.** Name tmux sessions `agent-<task>`, kill them
   when done; kill by pid, never `pkill -f <pattern>` — and never select
   pids with `pgrep -f <pattern> | kill` either: any pattern that appears in
   your own command line matches your own Bash tool and kills you (verified
   twice, once each way). Filter `/proc/<pid>/cmdline` by exact match, or
   kill the tmux server/pane that owns the process instead.

## The four surfaces, and what drives each

| Surface | Tool | Why |
|---|---|---|
| Web app / page | `playwright-cli` — `open` (isolated) or `attach --extension` (their session) | accessibility-tree snapshots, real clicks/typing, console + network |
| Desktop GUI app | `~/.claude/skills/desktop/scripts/gui` | reads and clicks widgets **by name** over the accessibility bus — no coordinates, no screenshots, no focus stealing |
| CLI / TUI | tmux (`send-keys` + `capture-pane`) | full text in, full text out, nothing visual to pay for |
| The shell itself (bar, panels, overlays) | `qs ipc` + `niri msg` | the surfaces answer directly; screenshots are a last resort |

`gui` prints its full usage with no arguments.

## The loop — every interaction, any app type

```
- [ ] 1. Pick the cheapest channel that answers the question:
        command/curl output → gui/web/tmux/IPC text → OCR → region screenshot
- [ ] 2. Before input: verify the target (focused window id, active pane,
        highlighted row) — never assume state carried over from a prior call
- [ ] 3. Act in one atomic burst (focus+verify+type in a single Bash call)
- [ ] 4. Verify the effect through the cheapest channel before concluding —
        a failed interaction is usually your targeting, not the app
- [ ] 5. Revert what you touched: windows, sessions, focus, files, settings
```

If an interaction "did nothing", suspect steps 2–3 before reporting an app
bug — re-verify at fullscreen / re-read the real state, then retest once.

## Seeing the screen

- Region: `grim -s 1 -g "X,Y WxH" /tmp/s.png` then Read. Screen is
  0,0 1706x1066; bar is `0,0 1706x26`; tiled windows sit below the bar with
  10px gaps (a full tile is ~1687x1021 starting near 10,36).
- Window geometry is NOT available from IPC (`tile_pos_in_workspace_view` is
  null; nirisnap verified window-region capture impossible on niri). For a
  whole-window shot use the compositor:
  `niri msg action screenshot-window` → newest file in `~/Pictures/Screenshots/`
  (`ls -t ~/Pictures/Screenshots | head -1`). Prefer a region crop when you
  know where to look.
- Overlays/panels: confirm the surface actually mapped before trusting an
  empty shot — `niri msg -j layers | jq -r '.[].namespace'` (qshell surfaces
  are `qshell-<name>`). Overlays dismiss on any user keystroke/click, so
  chain open→grim within ~0.7s and treat an empty capture as a race first.
- Text state of any terminal you own: `tmux capture-pane -p -t agent-x` —
  never screenshot a terminal you can capture.

## Keyboard — wtype

- Keysyms are reliable: `wtype -k Return`, `wtype -k Down`, `wtype -k BackSpace`.
- Modifiers: `wtype -M ctrl -k space -m ctrl` (press `-M`, release `-m`).
- Text: `wtype "hello"` — fine on the live session; under the nested dev
  compositor text autorepeats into garbage, use single `-k` keysyms there.
- Before typing: `niri msg -j focused-window | jq '{app_id,title}'` (or the
  layers check above for shell surfaces). After a miss: `wtype -k BackSpace`
  to clean up.
- **When the user is active, make every burst atomic**: focus + verify +
  type inside ONE Bash call (`niri msg action focus-window --id N; check
  focused==N && wtype …`), and abort on mismatch — their keystrokes between
  your tool calls can move focus at any moment (they answer you mid-turn).
- **grim BEFORE pressing Return inside qshell panels.** Blind Right+Return in
  the network panel once switched the user's DNS to Cloudflare. Look, then press.

## Mouse — wlrctl to point, ydotool to hold

- Relative only, so reach absolute (X,Y) logical coords by pinning to the
  corner first:
  `wlrctl pointer move -20000 -20000 && wlrctl pointer move X Y`
- `wlrctl pointer click` (left; also `right`, `middle`), `wlrctl pointer scroll dy dx`.
- Coordinates == pixels in a `grim -s 1` capture. Take the region shot, find
  the target, click those numbers.
- **Moving the pointer changes focus** (focus-follows-mouse is on) and can
  dismiss open overlays/tooltips. Don't wiggle the mouse for fun; put it back
  near where it was if the user is active.
- Tooltips in screenshots may be the idle mouse hovering, not your cursor.
- **Verify where the pointer actually is** with `grim -c` (includes the
  cursor) on a small region — the only way to confirm a move landed.
- Prefer `gui click` over coordinates whenever the app exposes a11y: it
  can't miss, and it doesn't move the user's pointer at all.
- **Dragging** (sliders, drag-and-drop, marquee) needs a held button, which
  wlrctl cannot express — hold it with ydotool and steer with wlrctl:

```sh
wlrctl pointer move -20000 -20000 && wlrctl pointer move X Y   # to the grab point
ydotool click 0x40      # press and HOLD left     (0x40 down · 0x80 up · 0xC0 click)
wlrctl pointer move DX DY                                       # drag, relatively
ydotool click 0x80      # release
```

  Verified end to end (a GTK slider moved 50 → 89). Two traps: **don't
  reach for `ydotool mousemove --absolute`** — ydotoold's default device is
  relative, so absolute coordinates are ignored, and `ydotoold -T` (the
  EV_ABS/touch device that would accept them) exits 2 immediately on this
  machine, verified against a working control run. Position with wlrctl,
  use ydotool only for the buttons. And `ydotoold` must be running
  (`systemctl --user status ydotoold`), which needs the `input` group
  active in the session — a fresh login after install.
- **To click a spot inside a window, fullscreen it first**
  (`niri msg action fullscreen-window --id N`): a tiled window's x-position
  in the scrolling layout is unknowable from IPC, so clicks computed from
  assumed tile coords miss silently (verified — same click worked at
  fullscreen). A click that "did nothing" is usually YOUR coordinates, not
  the app: re-verify at fullscreen before reporting the app broken.

## Interactive CLIs/TUIs — tmux is the default

```sh
tmux new-session -d -s agent-x -x 200 -y 50   # headless terminal
tmux send-keys -t agent-x 'mysql' Enter
sleep 1; tmux capture-pane -p -t agent-x      # read output as TEXT
tmux send-keys -t agent-x 'show databases;' Enter
tmux kill-session -t agent-x                  # always
```

- Answer prompts with `send-keys` (`y`, `Enter`, `C-c`, arrows as `Down`/`Up`).
- Show the user what you're doing: `foot-run tmux attach -t agent-x` opens a
  visible foot on the same session — you keep driving via send-keys, they watch.
- `foot-run <cmd>` (in `~/.dotfiles/bin`, already on PATH) is the way to open
  any visible terminal — server-first footclient, instant spawn.
- An app that runs its own tmux server (`-L <name>` / `-S <path>`) can be
  read and driven the same way — target its socket: `tmux -L <name>
  capture-pane -p -t %N`, `send-keys`. `tmux -L <name> list-panes -a` maps
  what it built.

## Driving any TUI precisely

- Plain `capture-pane -p` strips colors, so **selection/highlight state is
  invisible**. Before any destructive keystroke (delete/confirm/stop), read
  `capture-pane -p -e` and find the reverse-video row with regex
  `\x1b\[[0-9;]*7m` — highlights often render as a combined SGR (`[0;7m`),
  and a bare-`[7m` match misses it (that miss once produced a false
  "selection vanished" bug report). Selection is often sticky on an old
  row, not the row you assume (that once armed a destructive action on the
  wrong list item — caught just in time).
- Fast typed strings can outrun a TUI's input handling (palettes,
  autocomplete): type, pause, then Enter — and re-capture between steps.
- tmux pane → screen coords for clicking: `display-message -p -t %N
  '#{pane_left} #{pane_top} #{pane_width} #{pane_height} #{window_width}
  #{window_height}'` cells, scaled into the (fullscreened) window's pixel
  box.

## Launching GUI apps

- `launch-or-focus <app_id> [cmd…]` — focus the existing window else launch
  (pattern matches app_id, word-bounded, case-insensitive).
- `app-run <cmd> [args…]` — detached launch as its own systemd unit under
  app-graphical.slice (oomd isolation). Use for anything long-lived.
- `webapp-launch <name>` — chromium webapps (chatgpt, discord, whatsapp, x,
  youtube, zoom). Plain browser: `app-run chromium-browser <url>`.
- Or compositor-side: `niri msg action spawn -- cmd args` / `spawn-sh "cmd | pipe"`.
- Wait for the window: `wlrctl toplevel waitfor app_id:<id>` (and `wait` for
  it to close, `find` to test existence).
- **Verify survival, not the flash**: sleep 3, `pgrep -af <cmd>`,
  `systemd-cgls --user-unit app-graphical.slice | grep <cmd>` — a window that
  appeared and died has fooled an agent before.

## GUI apps — read and click by name

`scripts/gui` talks to the accessibility bus, so a GTK/Qt app is a tree of
named widgets with screen coordinates, not a picture to squint at:

```sh
gui apps                      # what's on the a11y bus right now
gui tree <app>                # interactive widgets + coords + state flags
gui click <app> 'Save'        # activates it semantically — mouse never moves
gui type <app> 'Search' 'foo' # set an entry's text
gui text <app>                # every readable string in the app
```

`[checked,focused,sensitive]` flags in `tree` output are how you assert an
effect happened without a screenshot. Substring matching: `gui click files
Save` is enough.

Limits, and what to do instead: apps absent from `gui apps` don't export
a11y (drive them with wtype/wlrctl as usual); Electron/Chromium need
`--force-renderer-accessibility` to appear; a widget with no action still
gives you coordinates to click.

## Web apps & browser — decide the session first

**Before the first browser call, decide *whose session* the task needs.
That, not difficulty, picks the channel:**

| No login needed → `open` (isolated, default) | User's login needed → `attach --extension` |
|---|---|
| public pages, docs, local `.test` dev sites | Shopify admin, dashboards, paid/SaaS consoles |
| a login the task performs itself (test creds) | "check *my* orders / *my* store / *my* account" |
| repeatable checks, before/after comparisons | a bug only their logged-in session reproduces |
| anything unattended | a tab they already have open |

One tool does both — `playwright-cli`. Default hard to `open`: isolated,
headless, repeatable, and it never touches their profile. Escalate to
`attach` only when the task is impossible without their identity — and
**say so in your reply**, because it is their real browser and their data.

**`playwright-cli`** (full command reference: the `playwright-cli` skill —
invoke it rather than guessing flags). The session-opening command carries
the config; later commands find the running session on their own:

```sh
playwright-cli --config ~/.config/playwright-cli/config.json open <url>
playwright-cli snapshot            # a11y tree with refs (e3, e6…) — cheap
playwright-cli find "Add to cart"  # search the page instead of dumping it
playwright-cli click e6 · fill e3 "text" · press Enter
playwright-cli console             # errors without a screenshot
playwright-cli close-all           # always
```

The config pins Fedora's chromium (`launchOptions.executablePath`) —
without `--config`, `open` dies looking for `/opt/google/chrome/chrome`,
because no Chrome build exists for Linux arm64. `--mobile` renders a
lighter page and costs fewer tokens; `--json`/`--raw` keep output
scriptable.

**Their logged-in browser**, through the Playwright Extension (installed by
policy, `chromium/policies/extensions.json`) — real cookies, real logins,
real extensions:

```sh
PLAYWRIGHT_MCP_EXECUTABLE_PATH=/usr/bin/chromium-browser \
  playwright-cli attach --extension=chromium     # session name: chromium
playwright-cli --s=chromium goto https://…       # then drive as usual
playwright-cli --s=chromium detach               # NEVER `close`/`close-all`
```

The env var is load-bearing: without it the extension path looks for
Google Chrome (`~/.config/google-chrome`), which does not exist here.
Their browser must already be running — launch it with `app-run
chromium-browser` if not. **`detach` leaves their browser alive; `close`
and `close-all` would shut it, taking their tabs with it.** Never navigate
their session somewhere destructive, and never quote private page content
into a reply that doesn't need it.

**Cheapest first still applies.** `curl -s` answers most "is it up / what
does this endpoint return" questions with no browser at all. Local
projects serve at `https://<dir>.test` for `~/Sites/<dir>/public`
(caddy + dnsmasq + local CA).

Webapp wrappers (`webapp-launch chatgpt|discord|whatsapp|x|youtube|zoom`)
are chromium app windows — drive them as GUI windows (app_id
`webapp-<name>`), or via `attach --extension` if the tab is in the main
browser.

## Windows & workspaces — niri msg

- Inspect: `niri msg -j windows|workspaces|focused-window|layers|outputs`.
- Act: `niri msg action focus-window --id N`, `close-window --id N`,
  `fullscreen-window`, `move-column-left/right`, `focus-workspace N`,
  `toggle-overview` … (`niri msg action --help` lists ~140).
- React: `timeout 10 niri msg event-stream` streams WindowOpened/Focused/
  WorkspaceActivated etc. Always under `timeout`.
- Config edits don't hot-reload through the symlink:
  `niri msg action load-config-file` first.

## The qshell shell — qs ipc

`qs ipc show` lists everything. Targets you'll actually use:
`launcher` `menu` (`open <route>`, e.g. `menu open toggle.profile`) `notifs`
(status/dismiss/dnd) `media` (playPause/next/previous/status) `theme`
`background` (set/current) `clipboard` `emojis` `osd` `idle`
(stayAwake/status) `bar` (`open <widgetId>` opens a panel) `lock` (state
only — see Never-do) `filepicker` `wallpaper` `bluetooth`.

Quirks (all verified): `qs ipc call <target> show` prints a listing instead
of calling — use `qs ipc call <target> -- show` or `toggle`. The shell never
hot-reloads QML edits — restart it (`qshell-relaunch`). Syntax check QML with
`qmlformat-qt6 <file> >/dev/null`.

## System knobs (prefer the bin/ helpers — they exist for a reason)

- Volume/mute: `wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+`, `wpctl set-mute … toggle`
- Brightness: `brightness-display 5%+` (wraps brightnessctl + OSD) ·
  keyboard: `brightness-keyboard`
- Theme: `theme-set [name]` (no arg lists; drives niri + shell + apps) ·
  wallpaper: `background-next`
- Network: `network-status --verbose`, `network-dns`, `network-band`; wifi
  via `nmcli` (no polkit prompt in-session, verified)
- Media: `qs ipc call media playPause` (media keys route here; no playerctl)
- Misc: `power-profile`, `system-stats`, `reminder <min> [msg]`,
  `screenrecord` (wf-recorder), `color-pick`, `clipboard-open`
- Clipboard: `wl-copy` / `wl-paste` (`wl-copy` detaches a child — don't wait
  on it in a pipeline)

## Risky UI testing → nested compositor

To test anything that could wreck the live session (lock screen, shell
crashes, destructive keybinds): `just dev` in ~/.dotfiles opens a nested niri
on wayland-2 with its own qshell. Prefix every command with
`WAYLAND_DISPLAY=wayland-2` (`grim`, `wtype`, `qs list --all`, `qs ipc -i <id>`).
grim there captures only the nested output and keeps working if the real
session locks.

## Never do (without the user asking in this conversation)

- `niri msg action quit` / `power-off-monitors`, `qs ipc call lock lock`,
  suspend/reboot/poweroff — you'd end the session you're driving.
- Install packages or add configs — ask per item; installs go through
  `packages/manifest.toml` + the user running dnf (sudo prompts; have them
  run `! sudo …`).
- Change wifi/DNS/bluetooth/theme state as a side effect of "testing" —
  read state freely, mutate only on request, and revert what you touch.
- Leave anything behind: tmux sessions, spawned windows, files outside /tmp,
  a moved mouse mid-overlay.
