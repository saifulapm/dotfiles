# Credits

Code and patterns borrowed from MIT-licensed projects, recorded exactly.
Reference checkouts live in `~/ref/` (read-only, never symlinked into live config).

## omarchy (MIT) — github.com/basecamp/omarchy

- **Architecture patterns** from `shell/shell.qml`: services instantiated once at the
  root and passed by property injection (relative-path imports do not share singleton
  state); hardcoded fallback config so the shell renders a bar even with a broken
  user config; one Loader per summonable panel keyed by an open-set, with pending
  payload queues; IPC summon/hide/toggle surface.
- **Foot live retheme** approach from `bin/omarchy-theme-set-foot` +
  `bin/omarchy-theme-osc`: write OSC color escape sequences directly to each foot
  child's pty so open terminals retheme without restart.
- **Structural token concept** from `shell/Commons/Style.qml`: spacing scale as the
  shell's rem, font size ratios, state-token alpha recipes.
- **Clock/calendar plugin design** from `shell/plugins/panels/clock/`: hero date
  over a year-progress rail, memento-mori life bar with inline birth-year editor,
  ISO week-number gutter, locale-honoring week start with click-to-toggle
  persisted to shell.json; plus the inline widget-settings pattern
  (layout entries as `{id, ...settings}` objects, `updateEntryInline` writing
  them back atomically, format-ring cycling on the bar clock).
- **Audio plugin design** from `shell/plugins/panels/audio/`: hero with a master
  mute switch over the now-playing context, OUTPUT/INPUT/SOURCES sections with
  right-aligned percentages, the live microphone meter driven by
  `PwNodePeakMonitor`, per-application stream rows with their own sliders, the
  snapshot-plus-settle-timer around PipeWire's node lists, and the single
  cursor model shared by mouse hover and keyboard (j/k, h/l, Enter, m).
- **Network plugin design** from `shell/plugins/panels/network/`: the hero with
  QR-share, speed-test and radio-switch actions over a rotating connection
  phrase, the always-mounted live stats grid (ping, packet loss, rates, totals,
  IP, gateway) sampled from a helper script, the WI-FI BAND section with its
  Automatic switch and collapsing band pills, the DNS PROVIDER pills, the
  KNOWN/OTHER NETWORKS sections with inline passphrase entry and
  forget-on-hover, the centered QR and speed-test overlays, and the same single
  cursor model shared by mouse and keyboard.
- **Tray widget design** from `shell/plugins/bar/widgets/Tray.qml`: the
  pinned/drawer/hidden bucket model persisted as two id lists in the widget's
  inline settings entry, the hover-revealed drawer (600 ms OutCubic reveal of a
  clipped icon row, with the chevron riding the reveal at the drawer's outer end
  and the reserved empty space masked out of hit testing), symbolic-icon
  detection by the freedesktop `-symbolic` suffix with `MultiEffect`
  colorization to the bar foreground, and the right-click manage card (title and
  caption over per-item rows with Pin / Hide toggles). Their FontAwesome chevron
  is a Material Design glyph here (the FontAwesome range does not render under
  our Nerd Font fallback), their Dropbox dedicated-widget ownership check is
  dropped (we ship no Dropbox widget), and their in-house `QsMenuOpener` menu
  rendering is not used — our tray items open the application's own menu through
  `display()`.
- **Menu framework and filter semantics** from `shell/plugins/menu/` (`Menu.qml`,
  `MenuModel.js`) and the tree format of `default/omarchy/omarchy-menu.jsonc`:
  the hierarchical tree keyed by dotted ids with the kind inferred from the
  entry's own fields, submenu rows with a chevron and the "<title>…" header
  ("Go…" at the root), the type-to-filter pass over the WHOLE subtree below the
  current menu with their ranking (label exact / prefix / substring, then id and
  aliases, then whole-word description matches, submenus favoured on a tie, then
  depth and declaration order) and their split of matches into rows that live
  here and drilldown rows under a divider carrying the breadcrumb of where they
  actually live, the `when` guards batched into one bash run per open with
  submenus hidden when nothing under them survived, the `checked` ✓ marker,
  alias routes for summoning a submenu (or firing a leaf) directly, and the
  keyboard model (Enter/Right to enter, Left/Backspace-on-empty to go up,
  Escape clearing the query before it closes). Their JSONC parsing and user
  extension file, provider-backed rows and desktop-app rows are not ported —
  our tree is a JS object in `Modules/Menu/MenuTree.js` and our Apps row hands
  off to the launcher — and rows the shell owns itself (launcher, theme
  switcher, DND, lock) run in-process instead of shelling out.
- **Emoji picker design** from `shell/plugins/emojis/Emojis.qml`: the flat
  grid of glyph cells with no group headers and no recents section, the query
  line that doubles as the card header, and their keyboard model (←/→ by one
  cell, ↑/↓ by a row, PageUp/PageDown by a screenful, the first press parking
  on the first cell instead of stepping, Enter to take the cursor's emoji,
  Escape clearing the query before it closes, hover moving the cursor).
  Their selection path is `wl-copy --sensitive --foreground` plus a
  `wtype -M shift -k Insert` paste into the focused window, with the offer
  killed afterwards; no key-injection tool is installed here, so ours does a
  plain persistent `wl-copy` and confirms with a notification instead.
- **Clipboard manager design** from `shell/plugins/clipboard/Clipboard.qml`: the
  always-loaded capture half (the shell supervises the `wl-paste --watch`
  process itself and brings it back a second after it dies, because a dead
  watcher fails silently — copying still works and nothing is ever recorded),
  the picker as a query line over a split of entry list and full-entry preview,
  the row shapes (image thumbnail plus "Screenshot from <day> <time>", file
  drops shown as a file name, both dimmed against real text), and the keyboard
  model (Delete removes the row under the cursor, Shift+Delete asks before
  clearing everything, Home/End, PageUp/PageDown by six, Escape clearing the
  query before it closes, the first press parking the cursor instead of
  stepping). Their Enter pastes into the focused window via
  `wtype -M shift -k Insert` and their Alt+Enter opens the entry in a browser or
  editor; no key-injection tool is installed here, so Enter copies and confirms
  with a notification (as the emoji picker does) and the open action is not
  ported. Their history-index helper scripts are not needed as a result — the
  picker copies through `wl-copy` directly.
- **Reminders design** from `bin/omarchy-reminder`, `shell/plugins/reminders/`
  and `shell/plugins/bar/indicators/Reminder.qml`: reminders as transient
  systemd user timers (one per reminder, `systemd-run --user --on-active`,
  cancelled by stopping the unit) so nothing in the shell counts down, the
  two-step capture flow (minutes, then an optional message) as a single
  centered input line asked twice, and the bar indicator that shows only while
  something is armed — same glyph, same `count`/`tooltip` JSON contract, and
  the same click rule where a pending list notifies itself and an empty one
  opens the flow. Their indicator is refreshed by the CLI poking the shell over
  IPC; ours watches the store file the CLI writes, which is the same event with
  no coupling back to the shell. Their store is the timer list itself plus a
  message file per reminder under `$XDG_RUNTIME_DIR`; ours is a JSON file the
  shell can read, reconciled against the live timers on every read so a login
  that drops transient units cannot leave phantoms behind.
- **Theme palettes** from `themes/*/colors.toml`: all files in `themes/` except
  `tokyo-night.toml` are generated ports of omarchy's theme colors via
  `bin/theme-port-omarchy` (surface/text/accent/ansi mapping documented there).
  Non-color tokens (shape/motion) in those files are ours. Muted/primary text
  colors may differ from the source where our contrast floor adjusted them.

## DankMaterialShell (MIT) — github.com/AvengeMedia/DankMaterialShell

- **niri event-stream pattern** from `quickshell/Services/NiriService.qml`:
  `Socket` on `$NIRI_SOCKET`, send `"EventStream"`, parse newline-delimited JSON
  with `SplitParser`, dispatch on the event's single key.
- **LazyLoader + IPC popout pattern** from `DMSShell.qml` / `Services/PopoutService.qml`:
  every popout behind `active: false` loaders flipped by IPC handlers.

## noctalia (MIT) — github.com/noctalia-dev/noctalia-shell

- **Contrast-by-construction algorithm** from `src/theme/contrast.cpp`:
  `ensureContrast()` — WCAG-ratio target searched via 20-step binary search on
  OKLCH lightness with chroma-only gamut mapping. Ported to
  `shell/Commons/color.js`, consumed by `Services/Theme.qml` (derived
  on-accent + validation) and `bin/theme-apply` (template fan-out).
- **Surface-ladder derivation idea** from `src/theme/custom_schemes.cpp`:
  elevations as recipes (keep hue, cap saturation, force lightness).

## quickshell (LGPL/source reference) — github.com/quickshell-mirror/quickshell

- Used as API reference only; no code copied.

---
Direct file-level copies (source path → destination path):

- omarchy `shell/plugins/panels/audio/Model.js` → `shell/Modules/Bar/widgets/AudioModel.js`:
  near-verbatim port of the node/stream math (playback-stream and audio-source
  tests, device and stream labelling, headphone/bluetooth/HDMI glyph picks, the
  volume mood-name ladder, and the MPRIS-to-stream matching that names a
  generic `audio-src` stream after the player it belongs to). Their
  `parseSinkAvailability` was dropped (it parses an omarchy helper script we do
  not ship), the two type tests take the resolved type name as an argument
  because quickshell exposes `PwNode.type` as a numeric flags enum, video
  sources are excluded from the audio-source test, and whitespace was restyled
  to house 4-space qmlformat.
- omarchy `shell/plugins/panels/network/Model.js` → `shell/Modules/Bar/widgets/NetworkModel.js`:
  near-verbatim port of the network panel's parsing and formatting layer (the
  key/tab/value reader, throughput deltas, the ping window with its packet-loss
  percentage, byte/rate/latency formatting, band labels and status parsing, the
  Wi-Fi row shaping, sorting and KNOWN/OTHER section titles, the QR matrix
  parser and the 802.1X `nmcli connection edit` script). Their bar-pill helpers
  moved into `NetworkWidget.qml`, the icon ladder returns Material Design glyphs
  (the FontAwesome range does not render under our Nerd Font fallback),
  `signalStrength` is normalised here because quickshell reports 0..1, and
  whitespace follows house 4-space qmlformat.
- omarchy `bin/omarchy-network-status` → `bin/network-status`: direct port, same
  `--verbose` key/tab/value output contract. Byte counters come from
  `/proc/net/dev` instead of `/sys/class/net/*/statistics`, the route is parsed
  from `ip route get` text rather than `ip -j` + jq, and SSID/signal/frequency
  come from nmcli, with `iw` used only when installed (dBm, bitrate).
- omarchy `bin/omarchy-network-band` → `bin/network-band`: direct port of the
  band status/pin logic (nmcli `802-11-wireless.band` with revert-on-failure,
  the frequency→band boundaries, and the available-band scan of NetworkManager's
  cache). The current SSID/frequency are read from the nmcli scan list instead
  of `iw dev <device> link`, so `iw` is not a dependency.
- omarchy `bin/omarchy-network-qr` + `bin/omarchy-network-password` →
  `bin/network-qr`: direct port of both, merged behind a `--password` flag —
  same interface detection, same WEP/enterprise handling, same `qrencode
  --type ASCII` matrix collapsed to 0/1 rows, same secrets-on-stdout-only rule.
- omarchy `bin/omarchy-network-speedtest` → `bin/network-speedtest`: direct
  port (fast.com endpoints, eight parallel curl workers, per-second rates from
  the interface counters); the endpoint list is pulled out with grep instead of
  jq, and the counters come from `/proc/net/dev`.
- omarchy `bin/omarchy-dns` → `bin/network-dns`: partial port — their
  `set_connection_dns` / `clear_connection_dns` / `reapply_active_dns_connections`
  nmcli mechanism and their provider-detection heuristic. Their
  `/etc/NetworkManager/conf.d` global-dns file and `/etc/systemd/resolved.conf`
  rewrite (which is what makes the original need sudo/pkexec) are deliberately
  not ported: this repo does not write `/etc` without approval.
- omarchy `shell/plugins/emojis/emojis.json` → `shell/Modules/Emojis/emojis.json`:
  verbatim, byte-for-byte — their 1870-record emoji dataset (`{e, k}`: the
  glyph and its name plus search keywords as one lowercase string).
- omarchy `shell/plugins/emojis/EmojiSearch.js` → `shell/Modules/Emojis/EmojiSearch.js`:
  direct port of the search — the whole of it is a case-insensitive substring
  test of the trimmed query against each record's `k` text, with no
  tokenizing and no ranking (results keep the file's Unicode-group order) and
  the scan capped at 1000 hits. Only whitespace changed, to house 4-space
  qmlformat.
- omarchy `shell/plugins/clipboard/capture.sh` → `bin/clipboard-capture`: direct
  port of the emitter — the sensitive-selection gate (`CLIPBOARD_STATE` plus the
  `x-kde-passwordManagerHint` mime, so password managers never reach the
  history), the content-addressed image spill to a state directory keyed by
  sha256, the mime→extension mapping, the image-before-text probe order of the
  argument-less snapshot mode, and the two JSON entry shapes. Added on top: a
  `watch` mode that owns both `wl-paste --watch` children (upstream runs them as
  two separate Processes from QML, ours is one supervised process), each JSON
  line written under `flock` because the two watchers now share one stdout, and
  a TERM/INT/HUP trap that takes the children down — bash skips the EXIT trap on
  a signal.
- omarchy `shell/plugins/clipboard/ClipboardHistory.js` →
  `shell/Modules/Clipboard/ClipboardHistory.js`: near-verbatim port of the whole
  history model — entry normalisation, the `text:`/`image:` dedup key,
  most-recent-first rebuild with the cap applied as it goes (so re-copying moves
  an entry to the top rather than duplicating it), `file://` URI decoding that
  turns a file-manager copy into a named file row, the preview/full-text
  projections, and the plain case-insensitive substring filter in `displayRows`.
  Their `module.exports` tail was dropped and whitespace restyled to house
  4-space qmlformat.
- omarchy `bin/omarchy-reminder` → `bin/reminder`: direct port of the command
  surface and every user-visible string — the bare `<minutes> [message]` form
  with its "Your N minutes are up" default, the confirmation notification
  ("<message> in N minutes" / "Reminder set for N minutes" over "You'll be
  reminded at HH:MM"), the `show` listing notification and its
  "<label> in <remaining> (HH:MM)" lines with their minutes/seconds
  formatting, `show --json`'s exact object shape and "Set Reminder" /
  "1 reminder" / "N reminders" tooltip ladder, `clear` stopping every matching
  unit straight from systemd, and the `systemd-run --user --quiet --collect
  --on-active` firing mechanism with the message carried on the unit's command
  line. Added: a `$XDG_STATE_HOME/qshell/reminders.json` store written
  atomically (the shell watches it in place of their IPC refresh call, and it
  is reconciled against the live timers on every read), `add`, `done` for
  cancelling one by id/index/message-prefix, and a `list` that prints to the
  terminal where theirs aliases `list` to the `show` notification. Their
  `-i` summons our overlay through `qs ipc` instead of `omarchy-shell`.
- omarchy `shell/plugins/reminders/ReminderFlowModel.js` →
  `shell/Modules/Reminders/ReminderFlowModel.js`: near-verbatim port of the
  capture flow's validation — minutes as a positive integer and nothing else
  (their CLI parses no richer time input either), and the CLI argument list
  that carries the message only when one was typed. Their `module.exports`
  tail was dropped and whitespace restyled to house 4-space qmlformat.
- omarchy `shell/plugins/panels/clock/Model.js` → `shell/Modules/Bar/widgets/ClockModel.js`:
  near-verbatim port of the date/format math (format ring, ISO week, year/life
  progress parsing and percentages, six-row month grid). Vertical-bar formats and
  the node test exports were dropped; whitespace restyled to house 4-space qmlformat.
