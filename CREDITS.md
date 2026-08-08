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
  Deliberately NOT ported (2026-08-06 parity audit): their
  `omarchy-audio-sink-availability` filter, which drops sinks whose ports are
  all "not available" (unplugged HDMI/headphone jacks) from the OUTPUT list.
  It reads `pactl`, and no machine here ships it (Fedora's pipewire-pulse
  carries no pactl; pw-dump is absent too, and quickshell's Pipewire API
  exposes no port availability), so the filter would be dead code on every
  target — this Mac's graph shows a single sink regardless. If an unplugged
  HDMI sink ever pollutes the NUC's output list, install `pulseaudio-utils`
  and port the script's awk over `pactl list sinks` plus their
  `parseSinkAvailability`/`sinkAvailable` wiring. Their microphone widget's
  in-use state IS ported (2026-08-06): `Services/Audio.qml` `micInUse` lights
  the bar mic when any application holds a capture stream — presence-based
  rather than their per-stream mute test, since untracked PipeWire nodes
  carry no live mute state here, with the asahi-audio effect streams and the
  shell's own panel meter node excluded.
- **Network plugin design** from `shell/plugins/panels/network/`: the hero with
  QR-share, speed-test and radio-switch actions over a rotating connection
  phrase, the always-mounted live stats grid (ping, packet loss, rates, totals,
  IP, gateway) sampled from a helper script, the WI-FI BAND section with its
  Automatic switch and collapsing band pills, the DNS PROVIDER pills, the
  KNOWN/OTHER NETWORKS sections with inline passphrase entry and
  forget-on-hover, the centered QR and speed-test overlays, and the same single
  cursor model shared by mouse and keyboard.
- **Model-usage plugin design** from `shell/plugins/model-usage/`
  (`Panel.qml`, `Main.qml`, `providers/Claude.qml`): reading Anthropic's own
  rate limits from the OAuth usage endpoint with the token in
  `~/.claude/.credentials.json` (their request, their `anthropic-beta` header,
  their bucket preference of the OAuth-apps weekly bucket over the plain
  seven-day one), their percent-vs-fraction scale detection and reset-timestamp
  normalisation, the two windows normalised into one record so the meters speak
  one language, the "binding window" idea (the fullest window is the one that
  stops the next prompt) and the `alarming` state it drives at 90 %, the hero
  naming the tool over the plan, the LIMITS section as a labelled meter with a
  "Resets in …" countdown and their duration formatting, the 30 s tick that
  keeps those countdowns honest while the panel sits open, the TOKENS BY DAY
  rows scaled to the busiest day with today picked out, the TOKENS BY MODEL
  rows as a share bar filling the row behind the label, their top-four cut, and
  their model-id prettifier and token-count abbreviations. Their plan/tier
  label rules come with it (`default_claude_max_20x` → "Max 20x"). Both of
  their providers are ported, with their `Main.qml` multi-provider layer: each
  provider publishing the same six rate-limit properties, the rule that a
  provider earns a place only by being switched on AND having actually
  produced numbers (so a CLI that was installed and never run shows no tab of
  zeroes, and a machine that has run neither shows no widget at all), the
  per-provider `enabled` setting, the selection that follows the provider
  rather than its slot, the provider switch row, and their bar button's
  left-opens / right-refreshes / middle-steps-provider split. Their window
  label sniffing (`windowIsLong`, `windowSpanMs`, `windowTitle`) is what
  reconciles Claude spelling its windows out ("Session (5-hour)") with Codex
  abbreviating them ("5h window", "30m window"). Their SVG provider marks are
  copied verbatim, including the light/dark swap of the Codex mark. (The third
  provider in our panel, GitHub Copilot, is NOT theirs — `AiCopilot.qml` and
  `bin/copilot-usage-scan` are ours, written to the same provider contract so
  it drops in beside these two.) Their
  multi-device sync is ported too — the transport as `Services/Sync.qml` (see
  below) and the merge rules here: what a provider contributes to a snapshot,
  the sums for prompts/sessions/token buckets, the union of active dates
  rather than a sum of counts (working on two machines on one day is one
  active day, which is why the dates travel and not just a count), the
  fallback to the widest count for snapshots written before those dates
  existed, `recentDays` accumulating only into the local seven-day window, the
  merged view that replaces counted-from-disk numbers while keeping every
  account-level fact local, and their "Merged from N devices" footer. Rate
  limits are deliberately absent from a snapshot, as upstream: they are
  account-level, so the provider already reports usage across every machine
  and merging them would double-count. Not ported: their `stats-cache.json`
  and `history.jsonl` readers (ours reads the scanners instead) and their
  background polls — this shell does not poll, so the panel refreshes when it
  opens and from a refresh button they do not have. Their plugin has no plan
  table driving limits: the plan is a label and the numbers come from the
  provider, so our `plan` widget setting only overrides that label.
- **Cross-machine sync** from the sync half of `shell/plugins/model-usage/Main.qml`
  → `shell/Services/Sync.qml`: the whole design — one snapshot file per
  machine written into a shared directory with every snapshot in that
  directory read back, so the folder's own sync tool is the transport and
  there is no server or protocol; the `mkdir -p` → atomic write → scan
  sequence on a 1 s debounce with a re-run queued if one was requested while
  running; their marker-framed `bash` reader (`===<path>===` … `=== EOM ===`,
  `nullglob`) and its tolerant parse that drops snapshots it cannot read;
  their path expansion (`~`, `$HOME/`, relative-to-home, absolute), their
  device-id sanitising and its hostname/`$HOST`/`$USER` fallback chain (ours
  consults `~/.config/qshell/machine` before any of those — every Asahi box
  here answers "fedora" to hostname, and colliding ids collapse into one
  device), their
  permissive reading of the enable flag, the dummy snapshot path that keeps
  the FileView valid while sync is off, and their status strings. Generalized
  in one respect: upstream hardcodes model-usage's single payload, while this
  takes named sections (`publish("providers", …)` /
  `snapshotsFor("providers")`) so other modules can share the transport.
  Sections sit at the top level of the file beside `deviceId`/`updatedAt`, so
  a model-usage snapshot written here has the same shape as one written by
  their shell. Merging stays with each module, since what it means to combine
  two payloads is not the transport's business. The same one-writer-per-device
  invariant, applied to real files instead of snapshots, is `bin/qshell-sync` +
  `home/dot_bashrc.d/20-history.sh` (2026-08-06): per-machine bash history
  files in a folder every machine reads whole. The code is ours and the
  transport differs by design — omarchy's layer moves no bytes (their README
  delegates to "a folder synced by Syncthing, Dropbox, rsync, …"), while ours
  is the missing tool: rclone against a Dropbox hub on a systemd timer, with
  `bisync` beside it for the screenshots folder, which is file sync omarchy
  does not do at all.
- **Monitor plugin design** from `shell/plugins/panels/monitor/` (`Panel.qml`,
  `Model.js`): the hero naming the current brightness mood over a "Display"
  title, their brightness mood-name ladder itself, the live brightness slider
  with its 180 ms debounce and the rule that the value just written wins over
  anything a later probe reports (theirs bounced to zero without it), the
  right-aligned percentage that follows the knob while dragging, the SCALE
  preset row naming the focused output when more than one is connected, the
  per-display enable rows with their focused marker, check mark and
  last-display-enabled guard, the 5 s refresh that runs only while the panel is
  open with a re-probe after every action, and their section cursor model
  (j/k walks rows and falls through between sections, h/l adjusts the slider or
  walks the pills, Enter activates, hover moves the cursor). Their scale math
  (`cleanScale` / `availableScales` / `matchingScaleIndex`) is deliberately NOT
  ported — it encodes Hyprland's rule that a scale must divide the mode evenly
  in 1/120ths, which niri does not have, and applying it here misreported both
  the presets and the live scale. Their TEXT SIZE section is not ported (it
  drives an omarchy CLI that rewrites their shell's font override; ours lives in
  the theme). Their brightness helper, `hyprctl` monitor keywords and OSD summon
  are replaced by `brightnessctl` and `niri msg output`, which also gives us a
  VRR toggle they have no equivalent for.
- **Battery service** from `shell/plugins/services/battery/` (`Service.qml`,
  `BatteryModel.js`), ported 2026-08-06 as `shell/Services/Battery.qml`: the
  low-battery warning at 10% while discharging that fires once and re-arms
  when the state stops qualifying (their `shouldWarnLowBattery` rules and
  `PersistentProperties` reload guard), their notification wording ("Time to
  recharge!", "Battery is down to N%", critical, 30 s, the 󱐋 glyph), and the
  automatic power-profile switch on AC↔battery transitions. Two adaptations:
  their 30-second check timer is not ported — the UPower display device
  pushes percentage and state changes, so the logic re-evaluates from
  bindings (event-driven, identical observable behaviour); and their
  `omarchy-powerprofiles-set` per-source saved-profile files are not ported —
  upstream only writes them from a CLI this desktop does not ship, so this is
  their exact fallback behaviour (AC → performance when the daemon offers it,
  else balanced; battery → balanced) through quickshell's PowerProfiles
  service instead of `powerprofilesctl`. Their `omarchy-hook` call has no
  counterpart (no plugin system here).
- **Power plugin design** from `shell/plugins/panels/power/` (`Panel.qml`,
  `Model.js`): the hero of battery glyph, bold title and rotating status phrase
  beside the percentage at display size, over a charge bar that animates its
  width and pulses while current is flowing in; their two phrase lists and the
  2.8 s fade-out/swap/fade-in rotation with its snap back to full opacity when
  the state stops rotating; the label/value fact pairs (battery size, charge
  cycles, time left / time to full, discharge / charge rate) with the charge
  threshold taking over those labels when a charge limit is holding; their
  charge-threshold detection itself (pending-charge, fully-charged below 99 %,
  or charging with the rate collapsed or an eight-hour estimate); the battery
  glyph ladders; the 5 s refresh that runs only while the panel is open and
  keeps the last good sample when a run comes back empty; and the
  keyboard-cursor profile picker where the first arrow press parks the cursor
  rather than moving it. What UPower publishes is read from UPower rather than
  from their `omarchy-battery-status` helper; their profile list comes from
  `powerprofilesctl`, ours from quickshell's PowerProfiles service, so their
  `parseProfiles` and `omarchy-powerprofiles-set` are not ported. Their panel
  fetches system stats and never displays them — ours shows them as a SYSTEM
  section.
- **Weather plugin design** from `shell/plugins/panels/weather/`: the two-source
  fetch (wttr.in for the full report, Open-Meteo for the fast day/night-aware
  current conditions and daily forecast, with coordinates driving Open-Meteo
  first and wttr filling in behind it), the hero of condition glyph and
  oversized temperature beside the location label and the FEELS / WIND / HUMID
  read-outs, the three-day forecast row, the click-to-edit location label with
  debounced Open-Meteo geocoding (arrow-key suggestion list, coordinates stored
  with the name, empty commit clearing back to IP auto-detect, the spinner held
  until the report for the new location lands so stale data is never shown
  under a new label), the imperial/metric decision from an explicit `unit`
  setting then the reported country then the locale, the bounded 2.5 s retry
  rounds on both fetches, and the widget hiding itself until it has a report.
  Their location lives in an `omarchy-weather-location`-owned `weather.json`;
  ours is the widget's inline shell.json entry (with the old plain-text
  `weather-location` state file still honoured), so their save helper and its
  file-watch race workaround are not ported. Their bar right-click sends the
  report as a notification; ours middle-clicks to refresh.
- **Tray widget design** from `shell/plugins/bar/widgets/Tray.qml`: the
  pinned/drawer/hidden bucket model persisted as two id lists in the widget's
  inline settings entry, the hover-revealed drawer (600 ms OutCubic reveal of a
  clipped icon row, with the chevron riding the reveal at the drawer's outer end
  and the reserved empty space masked out of hit testing), symbolic-icon
  detection by the freedesktop `-symbolic` suffix with `MultiEffect`
  colorization to the bar foreground, and the right-click manage card (title and
  caption over per-item rows with Pin / Hide toggles). Their FontAwesome chevron
  is a Material Design glyph here (the FontAwesome range does not render under
  our Nerd Font fallback) and their in-house `QsMenuOpener` menu rendering is
  not used — our tray items open the application's own menu through
  `display()`. Their dedicated-widget ownership rule is ported (see below): an
  app whose own bar widget is in the layout has its tray item suppressed, and
  gets it back the moment that widget leaves the layout.
- **Dropbox plugin design** from `shell/plugins/panels/dropbox/` (`Panel.qml`,
  `Service.qml`, `DropboxIcon.qml`): the drawn five-tile Dropbox mark carrying
  the whole state (full foreground while an authenticated daemon syncs, dimmed
  and darkened while it is paused or logged out) instead of a glyph ladder, the
  bar button's left-opens / right-refreshes / middle-logs-in split, the hero of
  the mark over a rotating sync phrase ("Filing files", "Boxing bytes", …) with
  their 180/260 ms cross-fade between phrases and the compact on/off switch on
  its trailing edge, the optimistic pause/resume state that flips the icon on
  the click rather than when dropboxd settles, their startup ramp and
  post-command settle re-polls, the login row and its authentication-URL
  scraping out of the CLI's own output, the "Stored X of Y" line against their
  hard-coded plan quotas, the RECENT FILES list with per-kind glyphs and
  relative times, and their single cursor model shared by mouse and keyboard
  (header ↔ files, Enter activates, r/l/p). Ours on top: the folder walk is
  split off the presence probe so the periodic refresh stays cheap, the
  "Stored" row opens the Dropbox folder (`o`), and files open with `xdg-open`
  rather than `uwsm-app -- nautilus --select`.
- **rclone-remote widget (ours, in the Dropbox plugin's visual language).**
  omarchy has no rclone plugin; `shell/Modules/Bar/widgets/RcloneRemote*.qml`
  + `bin/rclone-remote-status` are ours, written in the design language of
  the Dropbox port above (which is omarchy's design): the mark carrying the
  state by color and opacity, the hero over a rotating phrase with the
  180/260 ms cross-fade, the optimistic toggle that flips on the click, the
  presence gate that keeps the widget invisible without a backend, the JSON
  status helper split into a cheap local mode and an expensive full one, and
  the simplified j/k/Enter cursor model. It began life as an iCloud-only
  widget and was generalized (2026-08-06) into one component instanced per
  rclone remote — today `icloud` (iclouddrive) and `dropbox-rclone` (dropbox,
  the Asahi Macs' access path; the NUC keeps the daemon-backed dropbox
  widget above) — each registry id carrying its own defaults, overridable
  from the inline shell.json entry. The rclone-specific deviations from the
  Dropbox design: the one network call is `rclone about --json`, so the
  STORAGE section (the "Stored X of Y" idea above, drawn as a fill bar)
  appears exactly when the backend supports `about` (dropbox does) and falls
  back to a root-listing reachability probe when it does not (iclouddrive) —
  panel open and explicit refresh only, where the dropbox widget keeps
  upstream's visible-widget poll; the mount is a transient systemd user unit
  (`systemd-run --user --collect`, the `bin/reminder` precedent) rather than
  a vendor daemon, with `mountpoint -q` as the arbiter; there is no
  recent-files walk (every listing is a paid API call); and
  re-authentication is interactive (Apple 2FA, Dropbox browser OAuth) that
  no shell process can drive, so a failed probe raises a copyable
  `rclone config reconnect` command row — the tailscale panel's notice-row
  precedent — instead of a login flow. The marks are per-instance: iCloud
  typesets `md-apple_icloud` (the MD range being the one that renders here);
  the Dropbox instance reuses `DropboxIcon.qml` — omarchy's drawn five-tile
  mark, listed under direct copies below — behind a Loader rather than
  redrawing it; both wear TailscaleIcon's "!" badge recipe.
- **Tailscale plugin design** from `shell/plugins/panels/tailscale/` (`Panel.qml`,
  `Service.qml`, `TailscaleIcon.qml`, and their `README.md` as the intent doc):
  the mark drawn as a 3×3 dot grid with the six inactive dots faded, carrying
  all three states itself (plain while the tailnet is up, struck through while
  it is down, badged with a red "!" while the device needs authorizing), the
  bar button's left-opens / right-toggles / middle-refreshes split, the hero of
  the mark over a rotating phrase ("Encrypting connections", "Braiding
  packets", …) with their 180/260 ms cross-fade and the compact on/off switch
  on its trailing edge, the optimistic on/off state that flips the mark on the
  click rather than when tailscaled settles, their login dance (`tailscale up`
  streamed line by line with the first authentication URL handed to the
  browser, a 10 s fallback that re-reads it from the status), the CONNECTIONS
  list of login profiles with the switching row pulsing, their operator escape
  hatch (a profile read refused for want of privileges raises a row that runs
  `tailscale set --operator=$USER` under pkexec instead of failing silently),
  the EXIT NODES list with the tailnet's own nodes, the recently-used Mullvad
  regions and the searchable region picker folded in behind a "+" row, the
  MACHINES list with per-OS glyphs, IP · DNS captions, a Taildrop send button
  gated on the tailnet's file-sharing capability and their four-way copy menu
  (name / DNS name / IPv6 / IPv4), and their single cursor model shared by
  mouse and keyboard (header → connections → exit nodes → machines, Enter
  activates, t/r/c/n/d/s). Ours on top: the Mullvad table and the profile list
  are read on panel open rather than on every tick (only the status feeds the
  bar mark), a THIS DEVICE block names the status, tailnet name and address
  their panel never shows, the copy menu is an inline expansion of the machine
  row rather than a `QtQuick.Controls` popup, and any privileged refusal — not
  only the one wording their profile list produces — raises the authorize row.
- **Bluetooth plugin design** from `shell/plugins/panels/bluetooth/`
  (`Panel.qml`, `Model.js`, and `bin/omarchy-bluetooth-device` as the action
  layer): the hero of state glyph, "Bluetooth" title and rotating phrase
  ("Untangling wires", "Streaming vikings", …) with their 180/260 ms
  cross-fade while the adapter is enabled, the compact on/off switch on the
  hero's trailing edge as the header's only cursor target, and "No adapter" /
  "Turned Off" standing in for the phrase when there is nothing to rotate
  about; the three device buckets (connected / known / discovered) sorted by
  label with address- and uuid-shaped names filtered out entirely, the
  CONNECTED list pinned above a ListView that scrolls the PAIRED and
  AVAILABLE sections as one flat model (their reasoning kept: the view owns
  the scroll position, so j/k keeps the current row visible and a shortening
  discovery list re-clamps without lurching under a hovering mouse), the
  AVAILABLE section existing only while the adapter is discovering, and their
  empty-state ladder; the per-address pending-action map that shows the
  in-flight verb ("Connecting…", "Disconnecting…", "Forgetting…") on the row
  and is reconciled against BlueZ's own reports when reality lands, with the
  20 s give-up sweep; connect-or-pair by whether BlueZ remembers the device,
  disconnect running the native call and the CLI belt-and-braces, forget
  disconnecting first; the battery percentage standing in for a connected
  row's status; THE audio-output auto-switch — a device that finishes
  connecting schedules the default PipeWire sink onto its own sink node,
  found by normalized BlueZ address (then label) in the node's text, retried
  on a 500 ms timer up to eight times so a keyboard stops looking; the 1 s
  discovery nudge while the panel is open (BlueZ refuses StartDiscovery
  during power-up and times discovery out on its own); and their whole cursor
  model — one highlight for mouse and keyboard, j/k across section
  boundaries with the virtual header section above them, l/h onto and off
  the row's forget button, Enter activating, Delete (or x) forgetting, b
  toggling the adapter, hover moving the cursor, the first press parking it,
  and the focused device followed by BlueZ address across list churn rather
  than by row index. Their IPC verb set (open/close/show/hide/toggle/
  toggleBluetooth) is ported onto a `bluetooth` target beside our
  `bar open bluetooth` summon path. Adaptations: discovery is stopped when
  the panel closes (theirs leaves BlueZ scanning; the pattern here is
  probing only while a panel is open), the sink match excludes asahi-audio's
  DSP nodes (`effect_output.*`, `audio_effect.*` — the default sink on the
  Asahi Macs is the convolver chain, which must never win the match and
  which quickshell complains about while tracked), the PipeWire preference
  write is `Pipewire.preferredDefaultAudioSink` with a `PwObjectTracker`
  held only while a switch is pending (their
  `omarchy-audio-output-set-default` persistence helper is not ported — this
  shell has no audio-restore layer), and their `QtQuick.Controls` ScrollBar
  has no counterpart (this shell hand-rolls its controls). Their
  SUPER+CTRL+B panel bind lands on Mod+Ctrl+Shift+B here (2026-08-06):
  Mod+Ctrl+B was already this config's wallpaper-picker key — established
  before the bluetooth panel arrived, and omarchy's own background switcher
  has no bind to conflict with — so bluetooth takes the Shift variant with
  their toggle semantics on the ported `bluetooth` IPC target.
- **Bluetooth escape hatch** from `bin/omarchy-restart-bluetooth` and its menu
  row (`update.hardware.bluetooth`, under their Update → Hardware submenu
  titled "Restart"), ported as `bin/bluetooth-restart` + the menu's
  `system.restart-bluetooth` row (2026-08-06). Theirs is `rfkill unblock
  bluetooth` + `rfkill list` and nothing more; ours keeps that opening and
  adds the restart their name and menu title promise — bounce
  `bluetooth.service` (through pkexec: the system unit is the one step the
  seated user's rfkill ACL does not cover), wait out the adapter's
  re-registration, and power it on with a retry for the `org.bluez.Error.Busy`
  beat right after bluetoothd returns. Their row opens a floating presentation
  terminal; ours opens the same floating foot the update row uses. Placed
  under our System submenu because our Update is a leaf and we ship none of
  their other hardware-restart scripts.
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
  extension file are not ported — our tree is a JS object in
  `Modules/Menu/MenuTree.js` — and rows the shell owns itself (theme switcher,
  DND, lock) run in-process instead of shelling out. Their **desktop-app rows**
  are ported: `mergeAppRows` (`MenuModel.js` + `Menu.qml`) swaps the whole app
  set into the tree as `kind: "app"` children of `apps`, sourced from
  DesktopEntries rather than a bash enumeration, so an installed application
  is searched, ranked and escaped exactly like a declared row. With it come
  their app-specific rules: .desktop Keywords and GenericName as aliases, app
  rows excluded from alias routes (else `htop`'s `Keywords=system;` shadows the
  System route), the whole-word label tier that puts an app above an
  exactly-labeled menu row, and the merge returning fresh maps instead of
  writing into the QML `var` properties in place. Their script-backed provider
  rows stay a separate view here (ours never merge into the tree), and their
  app uninstall flow is not ported.
- **Emoji picker design** from `shell/plugins/emojis/Emojis.qml`: the flat
  grid of glyph cells with no group headers and no recents section, the query
  line that doubles as the card header, and their keyboard model (←/→ by one
  cell, ↑/↓ by a row, PageUp/PageDown by a screenful, the first press parking
  on the first cell instead of stepping, Enter to take the cursor's emoji,
  Escape clearing the query before it closes, hover moving the cursor).
  Their selection path — insert into the focused window and leave nothing on
  the clipboard — is ported through `bin/emoji-insert`, our version of
  `bin/omarchy-menu-emoji-insert`, including the sleep that waits out the
  keyboard handover. The delivery differs: theirs is `wl-copy --sensitive
  --foreground` plus `wtype -M shift -k Insert` with the offer killed
  afterwards, and Shift+Insert does not survive the trip here — foot maps it
  to the PRIMARY selection (Alacritty, their terminal, maps it to the
  clipboard) and GTK3 apps ignore wtype's modifiers entirely while accepting
  typed characters. So ours types the emoji, which is upstream's own other
  branch (`omarchy-clipboard-paste-text` types the text when not asked for
  `--shift-insert`) and reaches the same end: nothing is left behind.
  Shift+Enter for a copy without typing is ours, as is the fallback to a
  persistent copy plus a notification when wtype cannot run at all.
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
  stepping), plus their two Enters: Enter copies the entry and pastes it into
  the focused window, Shift+Enter only copies. `bin/clipboard-paste` is
  `bin/omarchy-clipboard-paste-text` and `bin/omarchy-clipboard-paste-file`
  merged — our history store has their shape, so one `--history-index`
  resolves either kind and the content never travels on argv, which is their
  reason for the index in the first place. The paste itself deviates for the
  reasons given under the emoji picker: a short single-line entry is typed,
  and anything multi-line or long keeps their `wtype -M shift -k Insert` with
  the primary selection set to the same bytes so a terminal pastes the right
  thing — typing multi-line text into a shell would execute each line, which
  a bracketed paste does not. Their Alt+Enter open action is ported
  (2026-08-06) as `bin/clipboard-open`, a port of `omarchy-clipboard-open`:
  the same URL sniff (embedded http(s) URL first, then a lone bare domain
  promoted to https), the same scratch-file-for-text flow, the entry still
  travelling by index. Their tensaku-edit image editor and
  `omarchy-launch-browser`/`-editor` launchers are not shipped, so all three
  destinations resolve through `xdg-open`.
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
- **Idle service design** from `shell/plugins/services/idle/` (`Service.qml`,
  `IdleModel.js`): one compositor idle monitor armed at the FIRST stage
  deadline with the later stages hanging off it as one-shot timers carrying
  the difference, their `screensaver`/`lock` seconds config block and its 150 /
  300 defaults (`secondsFromConfig`'s fallback rules included), activity
  cancelling every pending stage, honoring idle inhibitors, and stay-awake as
  the presence of a state file that suspends the whole cycle — plus their
  `enable`/`disable`/`toggle`/`status` IPC verbs, where enable/disable act on
  idle detection rather than on stay-awake. Two adaptations: their first stage
  launches a screensaver window (and their Hyprland `openwindow`/`closewindow`
  tracking, launch grace and dismiss handling all exist to know whether that
  window is still up) — we ship no screensaver, so ours powers the monitors off
  through niri's DPMS action and drops that bookkeeping; and because launching
  their screensaver itself reads as activity they ignore the wake signal while
  it is up and let the lock fire underneath it, whereas ours takes the plain
  swayidle-style rule that any activity cancels the cycle and powers the
  monitors back on. Their flag file lives at
  `~/.local/state/omarchy/indicators/stay-awake` and is probed by a shell
  command on every directory change; ours is `~/.local/state/qshell/stay-awake`
  read directly by a `FileView`, so `touch`/`rm` from a terminal toggles it as
  well as the indicator does.
- **Indicator container** from `shell/plugins/bar/widgets/Indicators.qml` and
  `Ui/BarIndicator.qml`: the two-block design (active indicators always
  visible, inactive ones collapsed inside a clip container that opens on
  hover), each indicator mounted once per block with the block name and an
  `activeOverride` pushed into it, `belongsInBlock` deciding which copy renders,
  newly-activated indicators unshifted onto the far side of the active block so
  what is already showing does not shift under the pointer, the active-block
  guard that ignores a copy reporting inactive before it has ever been observed
  active, the 120 ms hide debounce shared by the container's own hover and its
  revealed items', the `items` and `alwaysShow` inline settings, and the bar's
  center-region hover as the reveal source of last resort (with nothing active
  the widget has no width to hover). Their two-state indicator styling is
  ported with it: ON lit and OFF dimmed to 0.45, both glyphs and both tooltip
  strings per indicator, and state carried by opacity rather than by the bar's
  attention color. The stay-awake, do-not-disturb and reminder indicators are
  ports of `shell/plugins/bar/indicators/StayAwake.qml`, `Dnd.qml`,
  `Reminder.qml` and `NightLight.qml` (their glyphs, their tooltip wording —
  the night light one names what a click does, not what is on — and their
  click rules). Their reveal snaps open where ours slides; and a standalone
  indicator named directly in a bar array collapses when off instead of
  reserving an empty slot.
- **Screen recording** from `shell/plugins/bar/indicators/ScreenRecording.qml`
  and `bin/omarchy-capture-screenrecording`, ported as
  `shell/Modules/Bar/widgets/ScreenRecording.qml` and `bin/screenrecord`. From
  the indicator: their glyph 󰻂, their "Stop recording"/"Screen Recording"
  tooltip pair, their rule that the indicator is active exactly while a
  recorder process is alive, and their click behaviour — stop while recording,
  otherwise open the capture menu's Screenrecord submenu (theirs shells out to
  `omarchy-menu toggle trigger.capture.screenrecord`, ours opens the same
  submenu in-process). From the script: the command surface (`--fullscreen`,
  `--with-desktop-audio`, `--with-microphone-audio`, `--stop-recording`), the
  `screenrecording-<timestamp>.mp4` naming under the XDG videos dir, the
  refusal to start a second recording, the wait for the output file before
  calling the recording started, and the stop path — SIGINT so the container is
  closed properly, a 5-second grace, then a hard kill with their
  "may be corrupted" critical notification. The menu rows are their
  `trigger.capture.screenrecord` structure: Stop declared first and guarded by
  a `pgrep` test, then one row per audio variant.
  The recorder underneath is different — theirs drives gpu-screen-recorder on
  Hyprland, ours drives wf-recorder on niri — and that accounts for the
  deviations. Their one smart picker (slurp fed rectangles from
  `hyprctl clients`, over a hyprpicker screen freeze, snapping a bare click to
  the window under it) has no niri equivalent, so ours splits into an explicit
  `--region` (bare slurp → `wf-recorder -g`) and `--fullscreen`
  (`niri msg --json focused-output` → `wf-recorder -o`). wf-recorder records a
  single audio device, so their merged "desktop + microphone audio" row cannot
  be ported and the microphone gets rows of its own; their webcam overlay needs
  mpv and v4l2-ctl, neither installed. Their post-processing pass (warmup-GOP
  trim, loudnorm, preview thumbnail in the saved notification) needs the
  ffmpeg/ffprobe CLIs, which this box does not have. And where they poke the
  shell over IPC (`omarchy-shell -q omarchy.indicators refresh`) after every
  start and stop, ours writes the recording's path to a state file the
  indicator watches, as `bin/reminder` already does — the file changing is the
  refresh, and because a supervisor process clears it when wf-recorder exits
  for any reason, a recorder that dies on its own clears the indicator too.
  Their `pgrep` check survives as the reconciliation `screenrecord status
  --json` runs on every read.
- **Dictation indicator** from `shell/plugins/bar/indicators/Dictation.qml` and
  `bin/omarchy-voxtype-status`: dictation state as a bar indicator fed by a
  long-running `voxtype status --follow --extended --format json` process
  parsed line by line — their status helper is ported as `bin/voxtype-status`,
  including the fallback JSON record it prints when voxtype is not installed
  and their reason for `exec`-ing the follower as the bar's direct child (a
  pipeline or coproc would orphan it under the systemd user instance). Their
  state mapping is ported too: `alt` first and `class` as the fallback, the
  microphone glyph while recording and 󰔟 while transcribing, "Dictate" as the
  idle tooltip. Two deviations: upstream's indicator is active only while
  `recording`, and an inactive indicator draws its inactive glyph, so their
  transcribing glyph is never rendered — ours is active for both working
  states so the hourglass actually shows; and where their click opens the
  voxtype config TUI and restarts their shell, ours toggles recording (their
  config opener is on right-click, without the restart — an indicator that
  follows a stream needs no reload). The niri binds beside it are omarchy's
  `default/hypr/bindings/voxtype.lua`: their SUPER+CTRL+X toggle verbatim, and
  their F9 push-to-talk as a second toggle, because niri has no release binds.
- **Night light service design** from `shell/plugins/services/nightlight/`
  (`Service.qml`, `NightlightModel.js`): night light as a two-state switch
  rather than a schedule — their 4000 K night and 6500 K day temperatures,
  their rule that "on" means the screen is below the 6000 K identity point,
  their pending-write queue so a fast double toggle cannot race, and their
  `status`/`enable`/`disable`/`toggle` IPC verbs. The daemon underneath is
  different: theirs drives hyprsunset through `hyprctl hyprsunset temperature`
  and reads the current value back, so hyprsunset holds the state and their
  service is stateless between calls. We drive wlsunset, which has no control
  channel — it holds wlr-gamma-control until it exits — so here the running
  daemon is the "on" state: on starts one `wlsunset -t 4000 -T 4001` (pinning
  the high temperature one kelvin above the low one is what makes a
  sun-following daemon hold still; equal values are rejected), and off
  terminates it and lets the compositor restore the ramps, so their
  day-temperature write has no counterpart. Their state therefore lives in the
  daemon and is re-probed; ours is a flag file at
  `~/.local/state/qshell/nightlight` read by a `FileView`, so `touch`/`rm`
  toggles night light as the indicator does. Their `bin/omarchy-toggle-nightlight`
  CLI, which duplicates the temperatures for callers outside the shell, has no
  port — the flag file and the IPC verbs are that entry point.
- **Background reveal** from `shell/plugins/background/Background.qml` and the
  `set_theme_background` sequencing in `bin/omarchy-theme-set`, ported as the
  rewritten `shell/Modules/Background/Background.qml` plus the synchronized
  push in `bin/theme-set`: the slanted-wipe transition — the incoming
  wallpaper drawn behind a parallelogram mask (a `QtQuick.Shapes` fill fed to
  `MultiEffect` as a mask layer, their −0.18 slant, threshold and spread
  values) that grows out from the screen's center over 420 ms InOutCubic,
  the old image underneath until the sweep passes; the version-gated state
  machine around it (`backgroundVersion` / `revealStartedVersion` /
  `pendingThemeVersion`, the instant and force paths of
  `transitionBackground`, `finishingTransition` with the settled image's
  own ready-signal doing the cleanup so finishing never flashes the window
  color); each screen readying its own mask (`maskReady` /
  `maybeStartReveal` with its double-checked `Qt.callLater` hop) while the
  first ready screen starts the shared animation, so a multi-monitor layout
  reveals everywhere; the theme payload riding the transition and applied on
  the reveal's first frame (`setPendingTheme` / `applyPendingTheme` in
  `startReveal`) with their ~300 ms fallback timer so a reveal that never
  starts still applies the theme; and their IPC surface
  (refresh/set/setInstant/transition/themeTransition) merged into our
  existing `background` target beside our clear/current. Adaptations: their
  base64 pair (colors.toml + shell.toml) is our one theme.toml, applied
  through `Services/Theme.qml`'s own loader, and the synchronization is a
  `deferFileLoads` latch there rather than their pure-IPC apply — our file
  watch on theme.toml stays armed as the degradation path, so a shell that
  missed the push still rethemes from the file on its next start;
  `finalPath` and their hardlinked background snapshots are dropped (they
  exist because their theme switch swaps the theme directory out from under
  the shown file; our theme files never move); `bin/theme-set` fires niri's
  `do-screen-transition` only when the IPC push fails (on the synchronized
  path the reveal is the transition, and freezing the screen would hide it);
  and their desktop double-click gestures (wallpaper picker on left,
  theme switcher on right) are deliberately NOT ported — this surface is
  placed within niri's backdrop (`layer-rule place-within-backdrop`), and
  niri excludes backdrop surfaces from every input-target lookup, in the
  overview included (`surface_under` in niri's src/niri.rs), so a pointer
  handler here could never fire; both pickers stay reachable through the
  menu, their binds and the `wallpaper`/`theme` IPC targets.
- **Image picker design** from `shell/plugins/image-picker/ImagePicker.qml` and
  `bin/omarchy-theme-bg-switcher`: the full-screen scrim over a skewed
  filmstrip, the selection blown up to a wide preview with the rest of the set
  fanned out around it as parallelogram slices (their expanded/slice sizes,
  their negative spacing and skew offset, the mask-plus-outline Shape pair,
  their dim wash over everything unselected and the thick accent outline on the
  selection), the z-order and the nearby window that keeps only the visited
  images decoded, the outlined title-case label under the strip, and their
  keyboard model (←/→ and Tab/Shift+Tab step over matches only,
  type-to-filter with Backspace and Ctrl+U edits, Escape clearing the filter
  before it closes, Enter or a click on the preview applying). Their picker is
  a generic selector driven over IPC by `omarchy-menu-images`, which blocks on
  a selection file — ours is summoned directly and applies through
  `bin/background-next --set`, so the selection-file/done-file handshake, the
  preload path and the request serials are not ported. The wallpaper picker
  does not preview as you move, and neither does theirs: the wallpaper changes
  only when a selection is applied, so Escape has nothing to restore.
- **Theme switcher as an image picker** from `bin/omarchy-theme-switcher`:
  their theme switcher is not its own UI at all — it builds a directory of
  per-theme preview images and hands it to the same image selector the
  wallpaper switcher uses (`omarchy-menu-images --print-name --show-labels
  --filterable --lazy-thumbnails --selected <current>`), so the two pickers are
  one component with two callers. Ours is that too: one tile per theme in the
  shared filmstrip, labelled with their title-cased basename, filterable by
  typing, opened pre-selected on the active theme. `bin/theme-list` resolves a
  tile image with their `find_preview` order — a `preview.*` file in the
  theme's directory, else the first sorted image in its `backgrounds/`. Their
  cache is not ported: they symlink previews into a cache directory keyed by a
  two-tier mtime signature because their menu is a separate process reading a
  directory, while ours is a field on the theme list the shell already reads,
  and their `--preload` warms a picker we summon directly. A theme with no
  preview image is theirs by omission — their strip just has no tile for it —
  where ours paints the theme's own surface holding its accent ramp. The live
  full-shell token preview as the selection moves is ours, not theirs
  (`Services/Theme.qml` `preview()`/`endPreview()`); it is why our switcher's
  Escape has something to restore where the wallpaper picker's does not.
- **Notification service and card design** from
  `shell/plugins/notifications/` (`Service.qml`,
  `components/NotificationCard.qml`): the whole non-visual half — the three
  models (on-screen popups, pending, past) and the rule that DND suppresses
  only the toast while the record still lands in pending; their DND bypass
  list (our own action toasts, plus a bare-CLI `notify-send` at critical
  urgency, because chat apps brand themselves and abuse critical to force
  visibility); the ephemeral senders that never enter history at all, and the
  freedesktop `transient` hint beside them; the urgency timeout policy
  (critical never expires, low floors at 5 s, everything else at 8 s, all
  capped at 30 s, with the sender's own timeout honoured in between); the
  replace-by-id removal that keeps one row per libnotify id; expire-vs-dismiss
  semantics on removal and the "user saw it" move from pending to past; the
  live-notification map held outside the models (a QObject in a model role
  becomes a dangling pointer once the server frees it); the /tmp image cache
  with its queue, its rewrite of the history row once `cp` lands and its
  delete-with-the-row; the history file with its debounced write, its
  duplicate-tolerant parse, the guard against a second `onLoaded` doubling
  every row and the first-run `onLoadFailed` branch; the 15-minute past sweep;
  the history replay with its "No recent notifications" answer; and their IPC
  surface (`invokeLast`, `dismissOne`, `dismiss`, `clear`, `clearPending`,
  `markAllSeen`, `showHistory`, `dismissAll`, `setDnd`/`toggleDnd`/`isDnd`,
  `ping`). Their card ports whole: the fixed 380 px width, the icon slot
  preferring the notification's own image over the app icon and hiding itself
  when neither resolves, the Nerd Font glyph fallback in that slot with the
  compact inline variant for a single-line toast, the collapse of a redundant
  icon when the summary already opens with a glyph, bold summary over dimmed
  body with their line caps, their body sanitising (inline `<img>` stripped,
  the origin prefix Chromium and its forks prepend removed), left-click
  invoking the `default` action and right-click closing, and the popup
  container itself: one fixed-size full-screen overlay surface per output
  masked to the toast column (adding or removing a toast never resizes the
  surface, so the compositor cannot scale a stale buffer), with the lifetime
  tick living in a slot delegate so the card stays presentational and hovering
  a toast holds it. Deviations, all deliberate: click-to-focus resolves the
  sender against `Services/Niri.qml`'s own window map and fires one niri
  `FocusWindow` action where they shell out to
  `omarchy-hyprland-focus-app`; DND and history persist through the state file
  rather than their `PersistentProperties` + file pair, since the file already
  spans QML reloads as well as restarts; a replacement notification is routed
  through ingress again from the live object's change signals, because
  Quickshell answers `replaces_id` by mutating the notification in place
  without re-emitting, which leaves upstream's model row showing the original
  text forever; an `image://icon/<name>` source is asked of the icon theme
  first, since Quickshell's icon provider answers an unknown name with a
  placeholder texture instead of the `Image.Error` their slot tests for; the
  countdown their card computes (a decaying `remainingLifetime`, an urgency
  `accentColor`) but never draws is drawn here as a rail along the bottom
  edge, and that same urgency colour marks a critical card's border, which is
  otherwise the accent for everything; and action buttons are ours — their
  card renders none and leans entirely on click-the-card, which is kept too.
  Not ported: their history panel (they have none either — the models exist
  for the IPC and the replay), and the bar-position clearance is our bar's
  since ours reads it from `shell.json`.
- **Lock screen design** from `shell/plugins/lock/` (`LockView.qml`,
  `Service.qml`): the whole face — the current wallpaper redrawn behind the
  lock and blurred to nothing (their blur radius, multiplier and slight
  contrast cut), one 381×67 password field centered on it (upstream draws
  nothing else at all — the avatar, time and date above it are ours, hung off
  the field so it keeps their dead-centre position),
  the masked characters centered and letter-spaced with their fit-to-width
  shrink so a long password never clips silently, the caret that only exists
  once something is typed, the field's own text standing in for a label
  ("Enter Password", "Checking…", the failure in italic), the failed-attempt
  count carried in that message, the border that is accent until a password is
  wrong and error afterwards, typing clearing the failure, Escape and Ctrl+U
  clearing the field, and the fingerprint glyph pinned inside the right edge
  with the field's padding reserved on both sides so the dots stay centered
  around it. Their `[lock]` theme section is the colour contract, resolved
  against our tokens: background at 0.8 alpha, their own placeholder recipe
  (foreground at 0.66), accent and error borders, accent at 0.45 for the
  selection. Their service comes with it: the requested / pending / secure
  split with the screen-stabilize queue behind it (a lock asked for while
  outputs are still settling waits rather than mapping against a screen list
  about to change), the refusal to lock at all without a readable PAM config,
  the password and fingerprint PAM flows running side by side with the
  fingerprint one retried on failure and armed only once the compositor
  confirms the lock, the five-second idle blank with its wall-clock check so a
  countdown frozen by suspend takes a fresh run-up instead of blanking a
  just-woken screen, and the preview overlay that draws the lock screen
  without locking anything. Adapted: they blank and wake through their own
  brightness helpers, we use the two niri DPMS actions the idle service
  already uses (and only run the wake when we are the reason the monitors are
  off — theirs fires a helper on every pointer motion); their `border` role is
  dead in their view (idle and typing share `border-active`), so ours has no
  idle border either; their event log goes to the journal, ours to `status`;
  and our LazyLoader, our own `pam.d/` (PAM resolves `include` inside the
  custom config directory, hence the tracked symlinks to the system files),
  our `locked` property and our `devUnlock` escape hatch are unchanged
  underneath it.
- **Polkit dialog design** from `shell/plugins/polkit/` (`PolkitAgent.qml`,
  `PolkitModel.js`): the whole face — one compact centered card holding a
  padlock glyph and the password field and nothing else (no title, no action
  id, no buttons; Escape cancels, Enter submits, any click refocuses), with
  the justification pill floating above it (polkit's boilerplate
  "Authentication is needed to run '/usr/bin/x' as the super user" reduced to
  "Authorize running '/usr/bin/x'" by their `authorizationLabel`, the full
  message standing in when it doesn't match); their `[polkit]` theme section
  as the colour contract (background, text, text-error, accent, border,
  border-error, scrim, with border / border-error sharing one alpha companion
  because the states are mutually exclusive in time), resolved against our
  tokens through the per-surface machinery; the failure choreography — the
  card shake (their exact three-step offset sequence −8/+8/0 at 35/50/55 ms),
  the border swapping to border-error, the placeholder flashing "Wrong" at
  full opacity for 1.2 s with the field read-only, and typing clearing the
  failure; the closing / submitted state machine (a cancelled or satisfied
  dialog lingers 300 ms so it never blinks, "Checking..." while PAM decides,
  a re-prompt re-arming the field); their card sizing rules (the 42 px field
  in the padded card, width clamped 260–312, height clamped to the screen);
  the snapshot-from-flow pattern (`resetSnapshot` / `syncFromFlow` /
  `beginFlow` — the view renders snapshot properties, never the flow object);
  and fingerprint mode — `fingerprintConfiguredFromPamConfig` parsing the
  polkit PAM auth stack for pam_fprintd, the card collapsing to a square that
  frames only the centered fingerprint glyph while PAM waits on the reader,
  the password field taking over the moment a response is required, and the
  lid-closed fallback that skips fingerprint while the clamshell is shut.
  Adaptations: the PAM probe assembles Fedora's split stack (the vendor file
  in `/usr/lib/pam.d` overridden by `/etc/pam.d`, plus one level of `auth
  include`/`substack` — pam_fprintd lands in system-auth here, which their
  single-file read would miss) and runs per request instead of their file
  watch; their lid helper reads `/proc/acpi/button/lid/*/state`, which Asahi
  does not have, so logind's `LidClosed` property answers behind it; their
  FontAwesome padlock is md-lock (only the MD range renders here); the
  fingerprint glyph and corner radius follow our tokens, and the card's
  whole geometry (2026-08-06) rides our spacing token the way theirs rides
  Style.space — their px values divided by our 4 px space unit, so a
  density change moves the card as their [spacing] scale would — with the
  content inset by the border width (their BorderSurface rule) and the
  border width itself resolved from the [polkit] section's border-width
  key through the per-surface machinery. Kept ours
  underneath: the keyboard-focus rule (a layer surface that asks for
  exclusive keyboard focus in its first commit never gets the keyboard from
  niri — map with None, flip to Exclusive one tick later), the
  Loader-gated window over the eager agent, the `Connections` anchored on
  `agent.flow` itself rather than a derived active flag (cancelling dies
  with null-property TypeErrors otherwise), and the `polkit status`/`cancel`
  IPC verbs — cancel now routed through their closing choreography.
- **On-screen display** from `shell/plugins/osd/Osd.qml`: the whole pill —
  the card measured out of its own columns rather than fixed widths so the
  padding is identical on every side whatever it carries, the icon column
  measured by glyph *ink* (Nerd Font glyphs draw well outside their cell) and
  pinned to the widest glyph the model can return so the bar never shifts as
  volume crosses a threshold, the readout column sized to "100%" so the digits
  don't jitter, their two-thirds gap between a glyph and a message against the
  full gap around the bar's hard edge, the message that grows to a cap and
  elides (a wider cap for media OSDs), the 142 px bar with its 140 ms OutCubic
  fill, the bottom-centered placement 67 px up, the full-screen overlay with an
  empty input region so it never eats a click, and their show/replace/timeout
  choreography: state is assigned *before* `opened` flips, so a fresh OSD
  starts at its value and only an update to a still-visible one animates,
  while a new kind replaces a visible pill in place and re-arms the 1200 ms
  timeout (`duration: 0` holds it open until `close`). Their `osd` IPC surface
  comes with it (`show` with their whole payload — icon/message/value/max/
  progressText/duration — plus `close`, `state`, `ping`), so any process can
  raise any kind; our `brightnessUp`/`brightnessDown`/`status` sit beside it.
  Adapted: `BorderSurface` becomes a plain `Rectangle` in our tokens (their
  `popups.border` default is the accent, so the border is ours-as-accent), and
  the bar takes our corner radius where theirs is square by construction
  (their rounding token is 0). Kept ours underneath: the eager-logic/lazy-
  window split, the PipeWire-reactive volume and mic paths (upstream has no
  reactive path at all — every OSD there is pushed by a helper script), the
  two-second arm delay that swallows the login flash, and the one-shot
  `brightnessctl -m` parse. Their per-level icon names are picked by the same
  ladder their audio panel uses (their volume keybind script only ever sends
  muted-or-high), and a volume above 100% shows a full bar over a truthful
  readout, which is what their model does with a value clamped at `max`
  beside a caller-supplied `progressText`.
- **Media service layer** from `shell/plugins/services/media/` (`Service.qml`,
  `BarWidget.qml`), ported as `shell/Services/Media.qml` +
  `shell/Modules/Bar/widgets/Media.qml` + `MediaPanel.qml`: the whole player
  model — playerctld ranked below real players at every decision rather than
  filtered out (the proxy is still a working fallback when it is all that
  answers); the playing-order ledger (`playerStartedAt`/`playSerial`) where a
  player keeps the serial it was first seen playing at only while it keeps
  playing, so "oldest playing" means longest continuously audible; the sticky
  preferred player that follows the player itself (`playerKey`) across list
  churn and dies with it, winning outright only while it is actually playing;
  `selectActivePlayer`'s full preference ladder (playing preferred → oldest
  audibly-playing → oldest playing → stream-backed preferred → any
  stream-backed → preferred → track metadata → controllability → identity,
  real players over the proxy at each rung); the PipeWire correlation that
  counts a player as audible only when a real playback stream's label matches
  its app label (their `streamLabelKey` normalisation with the ALSA prefix
  strips); source cycling over `orderedCycleSourcePlayers` with optional
  playback transfer that pauses the old source only after the new one actually
  started; `canHandleAction`/`playerForAction`'s rule that pause-shaped verbs
  target whatever is audibly playing first; the media OSD choreography, with
  next/previous waiting up to ten 120 ms beats for the track metadata to
  change so the OSD names the track that arrived; and the bar widget — the
  play/pause glyph dimmed darker while paused, the `title · artist` label
  auto-scrolling inside a clip when it outgrows the `maxLabelWidth` inline
  setting, glyph-only on a vertical bar, left/middle/wheel mapped to
  play-pause/next/prev-next, and the right-click card of album art (their 󰝚
  fallback), title/artist/album, transport row and the SOURCES list where a
  row click makes that player the sticky preference. Adapted: their OSD
  summon (`shell.summon("omarchy.osd", …)`) is a direct call into our Osd
  module with the same icon-name/message payload; the playback-stream list
  excludes asahi-audio's `effect_output.*`/`audio_effect.*` nodes (the
  convolver is a real Stream/Output/Audio node that would otherwise pass the
  class test and complain in the log for as long as a tracker holds it);
  their play-order resync Instantiator-of-Connections is a reactive snapshot
  binding over the same two inputs; their PopupCard becomes our BarPanel
  (scrim dismissal, Escape, Tab panel-switching) with a j/k/Enter cursor over
  the sources and h/l/Space transport keys the popup upstream does not have,
  since a panel here holds exclusive keyboard focus; the `media` IPC target
  keeps our pre-existing niri verb surface (XF86 keys) on top of their
  status/play/pause/source verbs, including a `stop` verb upstream does not
  ship; and `PwNode.type` is resolved through `PwNodeType.toString` before
  their string tests see it.
- **Bar interaction machinery** from `shell/plugins/bar/Bar.qml` +
  `BarModel.js` + `bin/omarchy-bar-text-color` + `bin/omarchy-toggle-bar`: the
  whole gesture layer of their bar. Drag-to-reorder — the 4 px press threshold
  that separates a click from a drag, the `grabToImage` ghost drawn on a
  per-screen clickthrough overlay (empty input mask) offset by where inside the
  widget the press landed, `nearestDropTarget`'s nearest-edge math over every
  drawn slot (so the empty space around a centered group is a drop zone, not a
  dead zone), the accent drop marker at that boundary, their
  `moveModuleInConfig` splice with its same-section index correction, and the
  rule that a widget lifted from a slot leaves a dimmed outline behind. The
  click-target registry that makes it possible — every button registering with
  the bar so a press that did not become a drag is dispatched back to whichever
  registered target is under the pointer, which is also what keeps a button
  nested inside a widget clickable — plus their deliberate omission of
  `drag.target` (a positioner owns the slot, and moving it leaves stale
  offsets). The bar-move gesture on empty bar space (press-and-hold or 4 px of
  travel, their `nearestScreenEdge` diagonal split, a crossfaded fixed-geometry
  slab per candidate edge rather than one resized slab, and the release that
  persists `bar.position`), and the double-click on that same space toggling
  `bar.transparent`. Transparency itself: their two-candidate auto-contrast
  (bar text vs the bar's background color, whichever wins the WCAG ratio
  against the strip of wallpaper the bar covers), the 120 ms debounce, the
  re-sample on wallpaper/theme/position change, and their trick of snapping the
  colour with animations disabled for two frames so the sampled foreground
  never crossfades — a gate that (2026-08-06) also reaches every bar glyph's
  own 160 ms colour transition through `OpticalGlyph.colorAnimationEnabled`,
  their WidgetButton `Behavior` gate carried into our component since ours,
  unlike their glyph item, owns its colour animation; non-bar consumers keep
  the animated default. The open-panel pill (their geometry: 2 px thick, 55 % of
  the slot or a widget-supplied extent, 2 px inset on the bar's inner edge,
  0.9 opacity, 120 ms fade). Cross-panel Tab/Shift+Tab over
  `panelNavigationSlots`, their configurable `centerAnchor`, their `bar-off`
  flag file as the bar-hide switch, and the rule that a widget which hides
  itself takes no space. Adapted: their `interactive`/`pressable`/`concealed`
  trio collapses onto `enabled` + opacity, tooltips are suppressed for the
  duration of a gesture, and panels follow the bar to whichever edge it is on.
- **Vertical bars** from the same files plus `Ui/WidgetButton.qml`,
  `Ui/BarIconButton.qml` and the widgets that carry a vertical variant
  (`bar/widgets/Workspaces.qml`, `ActiveWindow.qml`, `Spacer.qml`,
  `Tray.qml`, `Indicators.qml`, `panels/clock/BarWidget.qml` + `Model.js`,
  `services/media/BarWidget.qml`, `panels/power/Panel.qml`, `Ui/PopupCard.qml`):
  `bar.position` of `"left"`/`"right"` turns the bar on its side. Theirs, in
  order: the anchor set that pins a bar to one edge and spans the other axis,
  their two bar sizes (26 horizontal / 28 vertical — here two theme tokens,
  `bar.height` and `bar.width-vertical`), Column-based sections where the
  left/right arrays become the top and bottom ends with the center anchor
  pinned to the vertical center, the 8 px section insets moving to the top and
  bottom, `fixedWidth`↔`fixedHeight` swapping on every button and status slot
  so a slot is a fixed extent ALONG the bar and the bar's thickness across it,
  the open-panel pill rotating onto the bar's inner edge, the drop marker
  crossing the bar instead of running down it, tooltips 6 px off the widget's
  desktop-facing side, panels opening beside the bar centered on their widget,
  the bar-move gesture offering all four edges with a slab per edge, and the
  wallpaper strip sampled down the bar's own column. Widget by widget, theirs:
  the window title is hidden outright, the media title and the battery
  percentage give way to the glyph alone, the clock becomes a stack of short
  lines with its own `verticalFormat`/`verticalFormatAlt` settings and its own
  four-entry format ring (`"HH\n—\nmm"` and the rest, verbatim), the
  workspaces grid switches to one column, the tray drawer slides up from the
  pinned items behind a quarter-turned chevron, and the indicator container
  stacks its active and revealed blocks. Ours on top: their invariant that an
  implicit size never reads the parent's is now enforced in `BarButton`
  (a widget reading `parent.height` on a vertical bar closes a size cycle with
  the slot that sized itself from that widget), and the weather widget's
  temperature is hidden vertically the way their glyph-only weather button
  already is.
- **Per-surface theme overrides** from `shell/Commons/Color.qml` +
  `default/themed/shell.toml.tpl`: the surface-role model (one named section
  per themable surface, every key falling back to a foundational token), the
  `X` + `X-alpha` companion pairs composed into one color (`composed()` /
  `pick()`), values that name another token instead of carrying a literal,
  and the machine-level override file layered over whatever theme is active
  (their `~/.config/omarchy/shell.toml`, ours
  `~/.config/qshell/theme-override.toml`) — all folded into our single file
  per theme rather than their generated second file. `bin/theme-port-omarchy
  --sections` is their `apply_shell_section_overrides`
  (`bin/omarchy-theme-set-templates`): a theme's `shell.<section>.toml`
  becomes a `[<section>]` block spliced into ours, replacing only that block.
  `themes/tokyo-night.toml`'s `[lock]` section is their
  `themes/tokyo-night/shell.lock.toml`, values verbatim.
- **Gradient border tokens** from `bin/omarchy-theme-set-templates`
  (`parse_gradient` / `shell_gradient_value` / `gradient_start_value`) and
  `shell/Commons/Border.qml` + `BorderGeometry.js`: one token carrying either
  a solid color or a gradient (`"#a #b 45deg"`), the angle as the token ending
  in `deg`, the first stop as the flat-color degradation for consumers that
  cannot draw one, and `gradientEndpoints` verbatim in
  `shell/Commons/gradient.js`. `shell/components/GradientBorder.qml` is their
  Border.qml idea narrowed to a uniform-width ring (their per-side widths and
  hand-rolled arc paths are not ported). The `[border] active` values in
  `themes/{hackerman,solitude,last-horizon}.toml` are their
  `hyprland_active_border`, colors and angle verbatim; the template-function
  layer in `bin/theme-apply` mirrors their pre-computed `{{ shell_gradient X }}`
  / `{{ hypr_gradient X }}` sed entries.
- **ScreenMoveRemap — deliberately NOT ported** (2026-08-06, upstream 2daeaa7,
  `shell/Ui/ScreenMoveRemap.qml`): a workaround for Hyprland leaving an
  already-mapped layer surface at its old global position when its monitor
  moves within the layout; niri re-places layer surfaces on output layout
  changes, so the unmap/remap dance has no bug to fix here. Revisit only if
  the NUC's multi-monitor setup ever shows a bar or wallpaper stuck at a
  stale offset after an output change.
- **Font switcher — deliberately NOT ported.** `bin/omarchy-font-set`,
  `bin/omarchy-font-list` and their `style.font` menu provider let a user swap
  the monospace family at runtime. This desktop has no equivalent and no menu
  row: the family is fixed at Maple Mono in
  `home/dot_config/fontconfig/conf.d/50-qshell.conf`, by the user's decision on
  2026-08-06 (a port of their picker, and then a variant that switched the UI
  font while pinning the coding font, both existed briefly and were removed in
  favour of one family everywhere). What IS theirs and survives: fontconfig as
  the single source of truth rather than per-application font settings, and
  `shell/Commons/Style.qml`'s trick of resolving the alias with
  `fc-match -f "%{family[0]}" monospace` instead of handing Qt the literal
  alias — Qt caches a family name on first resolution, so the alias would
  freeze at whatever it meant when the shell started. Ours on top: a `FileView`
  on the policy file re-runs that resolution, so editing the family lands
  without a restart, and a theme's own `font.ui`/`font.mono` token still wins
  over the alias.
  Worth recording because it cost real debugging: their user config edits the
  `monospace` alias with `prepend_first`/`binding="strong"`, and that construct
  is only safe on `monospace`. Applied to `sans-serif` on Fedora it poisons the
  whole session — `/etc/fonts/conf.d/49-sansserif.conf` appends `sans-serif` to
  every pattern that carries no generic name, so a strongly-bound family on
  that alias is injected into every font request and outranks the family the
  application actually asked for. Symptom: `fc-match "Maple Mono"` answering
  "Adwaita Sans", and foot warning that its configured font was not monospace.
- **Fontconfig policy** from `default/fontconfig/conf.avail/50-omarchy.conf` →
  `home/dot_config/fontconfig/conf.d/50-qshell.conf`: the shape is theirs — a
  `mode="assign"` match per generic alias, generic-name assignment for a font
  fontconfig does not otherwise know, the web/CSS alias block (`system-ui`,
  `ui-monospace`, `-apple-system`, `BlinkMacSystemFont`), the untargeted
  last-resort family for Chromium and Electron (which resolve a missing glyph
  one character at a time with no `lang` on the pattern, so a lang-targeted rule
  never fires for them), and an `<alias><accept>` fallback list per generic so
  emoji is reachable from each. The families are ours: Maple Mono, Adwaita Sans,
  Noto Serif. Their Arabic/Urdu Naskh-vs-Nastaliq pair becomes a Bangla rule,
  which is the script this machine actually types. Ours as well: the symbols
  font on the monospace accept-list (their coding font is Nerd Font patched, so
  they need no such fallback) and `binding="weak"` on the generic assigns, for
  the reason above.
- **Theme palettes** from `themes/*/colors.toml`: all files in `themes/` except
  `tokyo-night.toml` are generated ports of omarchy's theme colors via
  `bin/theme-port-omarchy` (surface/text/accent/ansi mapping documented there).
  Non-color tokens (shape/motion) in those files are ours. Muted/primary text
  colors may differ from the source where our contrast floor adjusted them.
- **Theme wallpapers** from `themes/*/backgrounds/`: fetched verbatim as a
  pinned chezmoi external (`home/.chezmoiexternal.toml`) into
  `~/.local/share/qshell/backgrounds` — the images ship in omarchy's MIT repo
  and are downloaded from there at apply time, never committed here.
- **Emacs theming design** studied from the omarchy ecosystem's two packages
  (no code ported from either): scottjones/omarchy-emacs renders a colors file
  from theme tokens which a static theme consumes, and ovistoica/omarchy.el
  derives full-coverage themes through the Modus machinery. Ours combines the
  two ideas on our own plumbing — `templates/emacs-theme.el.tmpl` renders the
  Modus *named-color* layer to `~/.local/state/qshell/emacs-theme.el`, and the
  emacs config's qshell-dark/qshell-light themes (saifulapm/emacs.d) are Modus
  derivatives that read it; theme-apply pokes `qshell-theme-refresh` over
  emacsclient.

## DankMaterialShell (MIT) — github.com/AvengeMedia/DankMaterialShell

- **niri event-stream pattern** from `quickshell/Services/NiriService.qml`:
  `Socket` on `$NIRI_SOCKET`, send `"EventStream"`, parse newline-delimited JSON
  with `SplitParser`, dispatch on the event's single key.
- **LazyLoader + IPC popout pattern** from `DMSShell.qml` / `Services/PopoutService.qml`:
  every popout behind `active: false` loaders flipped by IPC handlers.
- **Compositor-blur adoption pattern** from `Widgets/WindowBlur.qml` /
  `Common/Theme.qml` (`blurLayersActive`): default-off setting, publish
  `BackgroundEffect.blurRegion` shaped like the card only while enabled, and
  drop surface fills to glass alphas when blur is active. Pattern only, no
  code copied (`Services/Blur.qml`, `Theme.sGlass`/`glass`).

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

## AAP / Apple Accessory Protocol (protocol reference) — librepods, OpenPods

- `bin/bluetooth-battery` speaks the L2CAP PSM 0x1001 protocol Apple audio
  accessories use to report battery, because AirPods never send the HFP command
  (`AT+IPHONEACCEV`) that PipeWire's audio gateway forwards to BlueZ — see
  `docs/airpods-battery-2026-08-08.md` for the packet-level proof. Protocol
  facts only: the handshake / set-features / request-notifications byte strings
  and the battery packet layout (component ids, level and status bytes), as
  published by the openly reverse-engineered implementations librepods
  (github.com/kavishdevar/librepods) and OpenPods
  (github.com/adolfintel/OpenPods). No code from either is copied or adapted —
  the reader is written against python3's stock `AF_BLUETOOTH`/`BTPROTO_L2CAP`
  socket — and every constant was re-verified against this desk's AirPods Pro 2
  (2026-08-08), which turned up one correction to the published sequences: with
  librepods' `ff ff fe ff` notification bitmask the device answers with its
  whole state (capabilities, HID descriptors, paired hosts, device info) and
  silently withholds battery; `ff ff ff ff` is what makes it report.

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
- omarchy `shell/plugins/model-usage/providers/Claude.qml` +
  `shell/plugins/model-usage/Panel.qml` →
  `shell/Modules/Bar/widgets/AiModel.js`: near-verbatim port of their limit
  layer, lifted out of QML into one model file — `parseNumber`,
  `utilizationPayloadUsesPercentScale`, `normalizeUtilization`,
  `normalizeResetAt`, `oauthUsageBucket` and their bucket preference,
  `bindingWindow`, `resetMsFor`, `formatDuration`, `formatTier`,
  `formatTokenCount`, `modelWordCase`/`friendlyModelName` and their `dayName`.
  Their `windowIsLong`/`windowSpanMs`/`windowTitle` label sniffing is not
  ported verbatim along with `limitWindow`/`limitWindows`, `heroMeta`,
  `modelRows`, `weekPeak` and `providerHasData` (their `Main.qml` gate).
  `windowSubtitle` and `formatPlanSetting` are ours — the first splits the
  parenthetical off a window label so the panel can set it beside the title,
  the second renders the `plan` widget setting.
- omarchy `shell/plugins/model-usage/providers/Claude.qml` and
  `providers/Codex.qml` → `shell/Modules/Bar/widgets/AiClaude.qml` and
  `AiCodex.qml`: their two provider objects and the property contract the
  panel reads them through, including Codex's `refreshLimits()` being
  `refresh()` (one scanner run answers both) and its scanner-output parse.
  Their per-provider background timers are dropped — this shell does not poll.
- omarchy `shell/plugins/model-usage/scripts/codex_usage_scanner.py` →
  `bin/codex-usage-scan`: direct copy — both local sources (the pi agent
  sessions swept with ripgrep, the native Codex session JSONL with its
  last-turn-only token accounting and its cache/reasoning double-count
  correction) and the `codex app-server` JSON-RPC handshake that reads the
  account and its rate-limit windows. Three additions, each marked in the
  file: a JSON-RPC error response now raises instead of being read past (an
  unauthenticated limits read answers with an error, which upstream silently
  turns into "no limits"), a codex that is installed but not logged in reports
  "Waiting for auth" instead of nothing, and a 43200-minute window is labelled
  "Monthly (30-day)" rather than "720h window" — the ChatGPT free plan reports
  one, and upstream's label would have been read back as a session window by
  their own title sniffing.
- omarchy `shell/plugins/model-usage/assets/{claude,codex,codex-light}.svg` →
  `shell/Modules/Bar/widgets/assets/`: verbatim, byte-for-byte — the provider
  marks shown in the panel hero.
- omarchy `shell/plugins/panels/monitor/Model.js` →
  `shell/Modules/Bar/widgets/MonitorModel.js`: partial port — their brightness
  clamp, scale normalisation and brightness mood-name ladder are verbatim.
  `cleanScale`, `availableScales` and their `matchingScaleIndex` are not ported
  (Hyprland's 1/120-divisor rule, which niri does not share); ours matches a
  preset by value. `parseDisplays` is replaced by `parseState`, which reads the
  panel's one probe: `niri msg --json outputs`, the focused output,
  `brightnessctl -lm` and a wlsunset check, split on marker lines.
- omarchy `shell/plugins/panels/power/Model.js` →
  `shell/Modules/Bar/widgets/PowerModel.js`: near-verbatim port of the
  cursor-index clamping, the key/tab/value reader, the profile glyphs, the
  charge fraction, the charge-threshold test, the battery glyph ladders and the
  mode label. Their `parseProfiles` is not ported (our profile list comes from
  quickshell, not `powerprofilesctl`); the duration/watt/capacity formatters are
  ours, formatting what UPower gives in place of the strings their
  `omarchy-battery-status` awk produced.
- omarchy `bin/omarchy-system-stats` → `bin/system-stats`: port of both stat
  sources — the `/proc/meminfo` used/total in GB and the `/proc/loadavg` read,
  plus their `key<TAB>value` output contract. CPU busy comes from sampling
  `/proc/stat` twice 200 ms apart (what their `--bar-widget` mode has the shell
  do) rather than from `top -bn1`, whose first iteration reports the average
  since boot. Added on top, so the panel needs one process per sample: a
  temperature reading (a CPU/SoC sensor when the machine has one, otherwise the
  warmest labelled hwmon reading with its label, because Apple silicon exposes
  no CPU sensor), the battery facts UPower does not publish (`cycle_count` and
  the charge-control thresholds, from the same sysfs files
  `omarchy-battery-status` reads, plus kernel health), and whether
  `powerprofilesctl` exists.
- omarchy `shell/plugins/panels/weather/Model.js` →
  `shell/Modules/Bar/widgets/WeatherModel.js`: near-verbatim port of the whole
  weather model — the wttr.in location query, the Open-Meteo geocoding parse and
  commit rules, the temperature rounding/conversion/formatting, the
  unit/locale/country imperial decision, the day-name and forecast-day builders
  for both sources, the Open-Meteo current-condition normalisation into wttr's
  shape, the day-icon pick (hourly entry nearest noon) and the WMO→wttr code
  mapping. Their `parseWeatherStatus` (the `status.sh` bar-script bridge) and
  their `weather.json` reader are dropped — our widget reads the report directly
  and takes its location from the inline settings entry. `iconForCode` keeps
  their exact wttr code groups and day/night split but returns Material Design
  glyphs (the FontAwesome and weather ranges do not render under our Nerd Font
  fallback), with their single rain group split into drizzle/light rain and
  moderate/heavy rain; `openMeteoDescription` is ours (Open-Meteo sends no
  wording, and their hero never showed one).
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
- omarchy `shell/plugins/image-picker/ImagePickerModel.js` →
  `shell/components/PickerModel.js`: near-verbatim port of the picker's whole
  non-visual half — the row parser with the basename dedup that is what merges
  two directories into one strip, `nameForPath`/`labelForPath` (basename,
  extension dropped, `-`/`_` to spaces, title case), the case-insensitive
  substring filter over both forms of the name, and the filtered-position math
  the carousel lays itself out with. Their `module.exports` tail was dropped,
  `Util.editsFilter`/`editedFilter` were folded in next to the filter they
  edit, and whitespace follows house 4-space qmlformat. The filter reads the
  `key`/`label` the row parser precomputes rather than re-deriving them from a
  file path, because the theme switcher's tiles are named themes, not files.
- omarchy `bin/omarchy-theme-bg-next` + `bin/omarchy-theme-bg-set` +
  `shell/plugins/image-picker/list.sh` → `bin/background-next`: direct port of
  the enumeration and the cycle — the merge of the active theme's backgrounds
  with a user directory, `list.sh`'s image extensions and sort, and their
  wrap-around step with an unknown current landing on the first image (which is
  what makes re-applying a theme advance its wallpaper). Their user directory is
  per-theme under `~/.config/omarchy/backgrounds/<theme>`; ours is the single
  `~/Pictures/Wallpapers`. Their current background is a symlink poked into the
  running shell over IPC — ours is the regular state file the shell already
  watches, written atomically (a repointed symlink is invisible to inotify).
  `list.sh`'s thumbnail cache is not ported: those thumbnails are rendered by
  ImageMagick, which is not installed here, so the picker decodes the originals
  at thumbnail size instead.
- omarchy `shell/plugins/bar/BarModel.js` → `shell/Modules/Bar/BarModel.js`:
  near-verbatim port of the pure half — `entryId`/`entryIndex` over the
  string-or-object layout entries, `normalizePosition`, `nearestScreenEdge`,
  `nearestDropTarget`, and `moveModuleInConfig` (renamed `moveEntry`, and
  taking our `bar` section map instead of their `bar.layout`). Dropped: their
  tray pinning, custom-module path resolution, `inlineSettingsDelta` (our bar
  patches settings in place by another route) and `pickDrawnSlot` (our centre
  anchor mounts its widget once, not twice). `normalizePosition` takes all
  four edges and `nearestDropTarget` keeps their axis switch, so the same
  functions serve a vertical bar; `isVerticalPosition` is ours.
- omarchy `bin/omarchy-bar-text-color` → `bin/bar-text-color`: port of the
  sampler — the cover-fit-then-crop of the wallpaper down to the strip the bar
  covers — all four of their crop cases, so a left or right bar samples the
  column down its own edge — the mean pixel, the WCAG luminance/contrast pair, the
  better-contrast-wins decision, and the rule that every failure prints the
  theme foreground so the bar is never left unstyled. Adapted: written in
  Python because nothing in the ImageMagick family is installed here (GdkPixbuf
  does the decode and scale, with a `grim -t ppm` screenshot of the bar region
  as the fallback that always works), the wallpaper path is read from our state
  file rather than resolved through a symlink, and the screen size comes from
  `niri msg --json outputs` instead of hyprctl.
- omarchy `shell/plugins/panels/dropbox/status.py` → `bin/dropbox-status`:
  direct copy — the `~/.dropbox/info.json` account read, their plan→quota
  table, the `dropbox-cli status` invocation and its stopped-daemon sniffing,
  and the single-pass folder walk that totals bytes while keeping the N most
  recently modified files in a heap. Three additions, each marked in the file:
  the CLI is looked up as `dropbox-cli` *or* `dropbox` (Fedora's
  nautilus-dropbox installs the second name), the resolved name is reported
  back as `cli` so the shell drives the same binary, and `--probe` answers the
  presence question without walking the folder.
- omarchy `shell/plugins/panels/dropbox/Model.js` → `shell/Modules/Bar/widgets/DropboxModel.js`:
  near-verbatim port — the status envelope and its defaults, the
  image/video/document extension tables behind the row glyphs, and the byte,
  percentage, usage-line, relative-time and file-meta formatting. Only
  whitespace changed (house 4-space qmlformat); their glyphs are already
  Material Design codepoints and survive our Nerd Font fallback as they are.
- omarchy `shell/plugins/panels/dropbox/DropboxIcon.qml` →
  `shell/Modules/Bar/widgets/DropboxIcon.qml`: verbatim — the five-tile mark
  drawn with `QtQuick.Shapes`, tile geometry and all. It replaces their login
  row's Devicons brand glyph too, which does not render here.
- omarchy `shell/plugins/panels/dropbox/Service.qml` →
  `shell/Modules/Bar/widgets/DropboxService.qml`: near-verbatim port of the
  service — the settings readers, the optimistic `_desired`/`active` pair, the
  status apply, the login/pause/resume commands, the authentication-URL
  scraper, and all five timers (periodic refresh, startup ramp, delayed
  refresh, action-status expiry, post-command settle). Changed: it is a
  `QtObject` rather than an `Item` so it can hang off a bar button, everything
  is gated behind one presence probe (nothing runs at all without a CLI), the
  periodic refresh asks only the cheap `--probe` question and runs only while
  the widget is on a visible bar, a full pass requested while another run is in
  flight is queued instead of dropped, every child process is wrapped in
  `setpriv --pdeathsig TERM`, and `openFile` uses `xdg-open` (so their
  `fileUri` encoder is gone with the nautilus call it fed).
- omarchy `shell/plugins/panels/tailscale/Model.js` →
  `shell/Modules/Bar/widgets/TailscaleModel.js`: near-verbatim port — the
  IPv4/IPv6 filters keyed on Tailscale's own ranges, the DNS-name cleaning and
  host-name display rules, the OS glyph table, the Mullvad host test, the peer
  normaliser, the `tailscale exit-node list` fixed-column table parser and its
  per-city region roll-up, the `status --json` and `switch --list --json`
  parses, the Taildrop capability and target tests, and the login plan. Only
  whitespace changed (house 4-space qmlformat), and their glyphs are already
  Material Design codepoints so they survive our Nerd Font fallback as they
  are. One function is ours: `isAccessDenied`, which widens their single
  "profiles access denied" test to the other prose tailscale answers a
  non-operator with.
- omarchy `shell/plugins/panels/tailscale/TailscaleIcon.qml` →
  `shell/Modules/Bar/widgets/TailscaleIcon.qml`: verbatim — the 3×3 dot grid
  with the six inactive dots at 0.24 opacity, the −45° slash at 1.22× the
  mark's width, and the badge circle at 0.42× with its "!" . Their
  `BorderSurface` and `Color`/`Style` singletons become plain properties the
  caller fills in, since this component knows nothing of a theme.
- omarchy `shell/plugins/panels/tailscale/Service.qml` →
  `shell/Modules/Bar/widgets/TailscaleService.qml`: near-verbatim port of the
  service — the settings readers, the optimistic `_desired`/`active` pair, the
  status/accounts/exit-node parses, the copy and Taildrop helpers, up/down,
  profile switching, exit-node setting, the pkexec operator authorization, the
  authentication-URL scraper, and all six timers (periodic refresh, startup
  ramp, delayed refresh, poll watchdog with their arm-once reasoning,
  action-status expiry, login timeout). Changed: it is a `QtObject` rather than
  an `Item` so it can hang off a bar button, everything is gated behind one
  `command -v tailscale` probe (nothing runs at all without a CLI, where theirs
  re-runs `which` on every refresh), the periodic refresh reads only the status
  and runs only while the widget is on a visible bar, every child process is
  wrapped in `setpriv --pdeathsig TERM`, the browser is reached with
  `Qt.openUrlExternally` rather than `omarchy-launch-browser`, and every
  privileged refusal raises the authorize row.
- omarchy `bin/omarchy-tailscale-send` → `bin/tailscale-send`: near-verbatim
  port — the `<machine> [file...]` shape, the short-name-in-messages rule, the
  chooser fallback with their exit-status reasoning (a chooser that never
  opened is not the same as nothing picked), the `tailscale file cp
  --update-interval=0` transfer and a toast either way. Notifications go
  through plain `notify-send` instead of `omarchy-notification-send`.
- omarchy `bin/omarchy-file-select` → `bin/file-select`: direct copy — the
  portal `OpenFile` call, the request path predicted from the bus name and
  token so the Response subscription is in place before asking, the
  case-doubled extension filters, the 600 s answer timeout and the
  nothing-picked / chooser-failed exit split. Only the program name in its two
  error messages differs.
- omarchy `shell/plugins/bar/widgets/TrayModel.js` →
  `shell/Modules/Bar/widgets/TrayModel.js`: near-verbatim port of the
  dedicated-widget ownership rule — the case-insensitive id/title/tooltip test
  for a Dropbox tray item, the layout entry-id reader that accepts both plain
  strings and `{id, …}` objects, and the section scan. Only the widget id
  differs: their plugin id `omarchy.dropbox`, our registry id `dropbox`.
- omarchy `shell/plugins/panels/clock/Model.js` → `shell/Modules/Bar/widgets/ClockModel.js`:
  near-verbatim port of the date/format math (format ring, ISO week, year/life
  progress parsing and percentages, six-row month grid). Vertical-bar formats and
  the node test exports were dropped; whitespace restyled to house 4-space qmlformat.
- omarchy `shell/plugins/notifications/NotificationLogic.js` →
  `shell/Modules/Notifications/NotificationLogic.js`: near-verbatim port of the
  module's whole non-visual logic — the Chromium-family test and the body
  sanitiser built on it, the "summary already opens with a glyph" test with its
  surrogate-pair-aware two-space rule, the DND bypass and ephemeral-sender
  rules, the glyph hint reader, the compact-glyph test, the snapshot and
  history-row shapes, the dedupe-by-libnotify-id used both on load and on
  replay, the history parse with its `entries` back-compat and duplicate
  reporting, the recent-history selection, the popup placement, and the image
  extension guess. Adapted: the two sender identities are ours (`qshell` for
  this shell's own action toasts, where theirs is `omarchy-action`) and the
  glyph hint is `qshell-glyph`; their `dumpRows` was dropped (the service dumps
  its own models, as theirs does); whitespace follows house 4-space qmlformat.
  Added at the end, not theirs: `normalizeAppToken` / `focusCandidates` /
  `appIdScore` / `matchWindowId`, which are what click-to-focus needs on niri —
  upstream hands the app name to a Hyprland helper script instead.
- omarchy `shell/plugins/lock/LockView.qml` → `shell/Modules/Lock/LockView.qml`:
  near-verbatim port of the view — the cache-busting `file://…?v=` background
  URL, the `TextMetrics` measurement that drives the fit-to-width dot scale,
  the fingerprint reserve on both margins, the password-text sync guard, the
  focus-on-enable rule, their signal set (`submitPassword`,
  `passwordTextEdited`, `clearFailureRequested`, `wakeRequested`), the wake
  MouseArea, and every size and ratio in the field. Their `Style`/`Color`
  singletons become properties resolved from the theme this shell injects,
  their `BorderSurface` becomes a plain `Rectangle` (we ship no gradient or
  per-side border specs) with our motion token animating the state change, and
  their unused `failedAttempts` view property was dropped — the count is
  rendered through `failureMessage`, as it is upstream.
- omarchy `shell/plugins/services/media/MediaModel.js` →
  `shell/Services/MediaModel.js`: direct copy of the player and stream math —
  the playerctld proxy test, the metadata/controllability capability tests,
  `canHandleAction`'s per-verb capability map, the cycle eligibility rule, the
  playback-stream class test, the stream-label normalisation with its
  PipeWire-ALSA prefix strips, the player app-label derivation from the D-Bus
  name, the bidirectional substring match between the two, the stable
  `playerKey`, the `\u001f`-joined track signature and its change test, and
  the OSD label/message builders. Two changes: `isPlaybackStream` takes the
  node's resolved type name as a second argument (quickshell exposes
  `PwNode.type` as a numeric flags enum — the AudioModel.js precedent), and
  whitespace follows house 4-space style. The `module.exports` tail is kept
  so the matching rules can be exercised under node.
- omarchy `shell/plugins/osd/OsdModel.js` → `shell/Modules/Osd/OsdModel.js`:
  near-verbatim port of the icon table and the payload model — every name
  alias, the literal-glyph passthrough for names it doesn't know, the
  percentage fallback ladder, and `stateForShow` with its clamp, its
  "a message suppresses the bar" rule, its `progressText` override and its
  duration parse. Their four FontAwesome-range speaker glyphs (U+EEE8,
  U+F026-F028) are replaced with the Material Design ladder 󰖁 󰕿 󰖀 󰕾 in the
  same four slots, because only the MD range renders under our Symbols Nerd
  Font fallback; `widestIcon` follows. Every other glyph in the table is
  already MD and is theirs unchanged.
- omarchy `shell/plugins/panels/bluetooth/Model.js` →
  `shell/Modules/Bar/widgets/BluetoothModel.js`: near-verbatim port of the
  whole model — device labelling with the uuid/address-shaped-name filters,
  the connected/known/discovered bucket split sorted by label, the
  pending-action map helpers, the visible-section list, and the
  PipeWire-node-to-device match (normalized BlueZ address, then device
  label, against the node's name/description/properties text) behind the
  audio output auto-switch. Their `module.exports` tail was dropped and
  whitespace restyled to house 4-space qmlformat; every glyph the panel
  draws is already in the Material Design range, so nothing needed
  substituting.
- omarchy `bin/omarchy-bluetooth-device` → `bin/bluetooth-device`: direct
  copy of the sequencing — the action/address argument validation, the
  power-on wait, trust-before-connect, pair as pair → trust → connect,
  forget as disconnect → remove, and every timeout. Only the program name in
  the usage line differs.
- omarchy `config/wireplumber/wireplumber.conf.d/bluetooth-a2dp-autoconnect.conf`
  → `home/dot_config/wireplumber/wireplumber.conf.d/` (2026-08-06): verbatim —
  the WirePlumber rule that auto-connects A2DP profiles on BlueZ cards, which
  is what makes the `bluez_output.*` sink the ported audio auto-switch polls
  for actually appear after a connect.
- omarchy `default/systemd/user/bt-agent.service` →
  `home/dot_config/systemd/user/bt-agent.service` (2026-08-06, after the
  user authorized installing bluez-tools): near-verbatim — the same
  `bt-agent -c NoInputNoOutput` auto-accept agent, their bluetooth-hardware
  condition, their skip-cleanly `ExecCondition` on bluetoothd and their
  restart policy. The safety comment is rewritten for this shell: their
  claim that the adapter is pairable only while their panel scans does not
  describe ours (nothing here ever sets the adapter discoverable or
  pairable — the panel's discovery is outbound scanning only), so the
  comment states that exposure honestly instead. Enabled by the
  02-user-timers unit list rather than their first-run installer script.
- omarchy `shell/plugins/polkit/PolkitModel.js` →
  `shell/Modules/Polkit/PolkitModel.js`: direct copy — `authorizationLabel`
  and its needed-or-required match, `fingerprintConfiguredFromPamConfig` with
  its comment-and-auth-line walk, and `promptLooksFingerprint`, which is
  exported and unused upstream and stays that way here. Whitespace follows
  house 4-space style; the `module.exports` tail is kept so the parses can be
  exercised under node.
- omarchy `bin/omarchy-launch-or-focus` → `bin/launch-or-focus` (2026-08-07,
  gap items 3+7): their word-bounded case-insensitive class/title match and
  focus-else-launch flow, hyprctl/jq swapped for `niri msg --json windows`
  and `focus-window --id`; newest id wins ties (their head -1 order is
  hyprctl's), `setsid -f` for the detached launch, no uwsm wrapper.
- omarchy `default/xcompose` + `install/user/xcompose.sh` →
  `home/dot_XCompose` (2026-08-07, gap item 9): the emoji and typography
  sequences verbatim, their include-chain inlined into one file, the
  identity rows carrying the gitconfig name/email.
- omarchy `bin/omarchy-brightness-display` → `bin/brightness-display` and
  `bin/omarchy-brightness-display-ddc` → `bin/brightness-display-ddc`
  (2026-08-07, gap item 1): the DDC script near-verbatim — detect/getvcp/
  setvcp 10, the bus / unavailable / range caches with their windows, the
  non-uniform sub-5% stepping — monitor names come from niri instead of
  hyprctl (both are DRM connector names, so the detect parse is unchanged).
  The wrapper drops their Apple-display (asdcontrol) and DPMS branches and
  raises our OSD over `qs ipc call osd -- show`.
- omarchy `default/themed/btop.theme.tpl`, `helix.toml.tpl`,
  `claude.json.tpl`, `gum_env.lua.tpl` → `templates/btop-theme.tmpl`,
  `helix-theme.toml.tmpl`, `claude-theme.json.tmpl`, `gum-theme.fish.tmpl`
  (2026-08-07, gap item 6): structure and key coverage theirs, token names
  mapped onto ours (terminal-family surface.0 background, foot's selection
  pair, ansi palette); the gum Lua `hl.env()` rows became fish `set -gx`
  lines sourced from conf.d/40-gum-theme.fish; claude.json's `{{ mix a b N% }}`
  expressions are precomputed in bin/theme-apply as `claude.*` tokens (plain
  sRGB interpolation, matching their awk `mix_color`). Reload pokes follow
  their restart scripts: btop SIGUSR2, helix SIGUSR1 — aimed at comm `hx`,
  Fedora's binary name, where their `pgrep -x helix` would miss. Per-theme
  GTK icon themes port their `themes/*/icons.theme` values into an `[icon]`
  section (gsettings flip beside the existing polarity flip, their
  omarchy-theme-set-gnome pattern); their gray/grey variants exist in no
  Yaru package and map to the neutral pair.
- omarchy `bin/omarchy-webapp-install` / `-webapp-remove` /
  `-launch-webapp` / `bin/omarchy-tui-install` / `-tui-remove` →
  `bin/webapp-install` / `webapp-remove` / `webapp-launch` / `tui-install` /
  `tui-remove` (2026-08-07, gap item 7): their icon scrape chain verbatim
  (apple-touch-icon link tag → well-known path → Google favicon service,
  the mime sniff on the download), their gum prompt flow, their
  TUI.float/TUI.tile app-id-to-window-rule pairing (the float rule reuses
  qshell-float's 875×600). Ours: chromium-only launch (no default-browser
  registry), launch-or-focus folded into webapp-launch as an app_id PREFIX
  match — chromium stamps app windows `chrome-<host>__-Default` and `__` is
  word characters, so the word-bounded launch-or-focus match can never hit
  them — and an X-Qshell-WebApp/-TUI marker in the .desktop so the remove
  pickers only ever offer entries these scripts created.
- omarchy `bin/omarchy-display-text-size` → `bin/text-size` +
  `bin/theme-apply`'s text-size derivations (2026-08-07, user ask): their
  one-knob design — px size upserted into the USER OVERRIDE the shell
  watches (ours: ~/.config/qshell/theme-override.toml `[font] size`), GTK
  driven as a text-scaling-factor QUANTIZED so the interface font lands on
  a whole point size, terminal point size derived from the same anchor
  (ours: the foot 12.5pt/32px tuned pair scales as a unit), and the
  foot-cannot-reload nudge with the replaces-id toast trick. Ours on top:
  the derivations live in theme-apply (so plain theme switches re-derive
  too), Emacs follows over an emacsclient poke (emacs.d reads the same
  file), and the Display panel carries the stepper omarchy puts in their
  monitor panel.
- omarchy `default/chromium/extensions/{copy-url,yt-dlp,whatsapp-slim}` →
  `chromium/extensions/` (2026-08-07, user pick): DIRECT COPIES, manifest
  `key`-pinned IDs and all — which is why the native host names stay
  com.omarchy.copy_url / com.omarchy.ytdlp: the extension code calls them by
  that exact string and the host manifests' allowed_origins match the pinned
  IDs from any install path. `bin/chromium-copy-url-host` and
  `bin/chromium-ytdlp-host` port their host scripts (framing, the detached
  --download worker, the throttled progress loop, the square-cropped toast
  thumbnail, click-to-open-in-mpv) onto notify-send and our OSD IPC; loaded
  via --load-extension in CHROMIUM_USER_FLAGS instead of their
  chromium-flags.conf, hosts registered by run_after_21.
- omarchy `bin/omarchy-menu-select` / `-menu-input` + the menu plugin's
  dmenu modes and providers (`shell/plugins/menu/Menu.qml`) →
  `bin/menu-select` / `bin/menu-input` + `Modules/Menu/Menu.qml`
  (2026-08-07, user pick): their payload contract verbatim — mode/prompt/
  options/selectionFile/doneFile, glyph-TAB-label options, the shell
  guaranteeing the done marker on every dismissal — with jq building the
  JSON instead of their perl, a 120s poll cap (their loop is infinite), and
  cancel deleting the pre-created selection file so an empty typed answer
  stays distinguishable. Providers are their registry shape (script emitting
  label\tvalue\tcurrent, volatile per entry, actionFor per row); ours ships
  power-profiles wired to bin/power-profile. omarchy-powerprofiles-set/-list
  → bin/power-profile (near-verbatim: per-source state files, UPower
  OnBattery autodetect, availability guards, ac→performance default).
- omarchy `default/bash/fns/{ssh-port-forwarding,rsyncing,tmux}` → fish
  functions `fip/dip/lip`, `rsw/lsw/dsw`, `tdl/tds/tdlm/tsl` (2026-08-08,
  user pick): logic theirs — the ControlMaster-per-host rsw socket, the
  detached inotifywait loop kept as a bash one-liner under setsid, the tmux
  pane choreography with -P -F pane-id capture. Deviations: tdl's stray
  `$opencode_pane` select lands on the editor as intended; tds's
  nvim/hunk/opencode hardcodes became $EDITOR / watchexec-driven git diff /
  claude (what this machine actually runs); app-run (same day) is the slice
  half of the uwsm-app pattern their AppLibrary launches through.
