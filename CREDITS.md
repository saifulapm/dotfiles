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
- omarchy `shell/plugins/panels/clock/Model.js` → `shell/Modules/Bar/widgets/ClockModel.js`:
  near-verbatim port of the date/format math (format ring, ISO week, year/life
  progress parsing and percentages, six-row month grid). Vertical-bar formats and
  the node test exports were dropped; whitespace restyled to house 4-space qmlformat.
