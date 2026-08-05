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
  device-id sanitising and its hostname/`$HOST`/`$USER` fallback chain, their
  permissive reading of the enable flag, the dummy snapshot path that keeps
  the FileView valid while sync is off, and their status strings. Generalized
  in one respect: upstream hardcodes model-usage's single payload, while this
  takes named sections (`publish("providers", …)` /
  `snapshotsFor("providers")`) so other modules can share the transport.
  Sections sit at the top level of the file beside `deviceId`/`updatedAt`, so
  a model-usage snapshot written here has the same shape as one written by
  their shell. Merging stays with each module, since what it means to combine
  two payloads is not the transport's business.
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
  ports of `shell/plugins/bar/indicators/StayAwake.qml`, `Dnd.qml` and
  `Reminder.qml` (their glyphs, their tooltip wording, their click rules). We
  ship no dictation, screen-recording or night-light indicators, so those
  entries are absent; their reveal snaps open where ours slides; and a
  standalone indicator named directly in a bar array collapses when off instead
  of reserving an empty slot.
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
- omarchy `shell/plugins/panels/clock/Model.js` → `shell/Modules/Bar/widgets/ClockModel.js`:
  near-verbatim port of the date/format math (format ring, ISO week, year/life
  progress parsing and percentages, six-row month grid). Vertical-bar formats and
  the node test exports were dropped; whitespace restyled to house 4-space qmlformat.
