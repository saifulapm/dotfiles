# qshell vs omarchy shell — full performance comparison, 2026-08-06

MacBook Pro M2 (Asahi, 16K page kernel, aarch64), same box, same session,
sequential (never simultaneous), load average ~2 throughout (an agent session
was resident — both shells carry the same handicap; treat absolutes as upper
bounds, the comparison as fair). Raw logs: `bench/20260806-170000-aarch64.txt`
(ours) and the session job dir. Method: 3-4 cold runs each; PSS from
`/proc/<pid>/smaps_rollup`; wakeups = voluntary context switches/s sampled
per-second over 60 s; IPC-ready = first answering real handler (`shell ping`
ours, `omarchy.indicators refresh` theirs), polled at 50 ms granularity, both
carrying ~40-46 ms `qs ipc` client overhead.

## 1. Side-by-side numbers

| metric | qshell (ours) | omarchy shell |
|---|---|---|
| spawn → bar constructed | **345 ms** median (323-347, shell-reported) | not instrumentable (their code, unmodified) |
| spawn → IPC handler answers | 515 ms median (503-540) | **193 ms** median (179-204) |
| idle RSS (settled, no panel opened) | **210-212 MiB** | 299 MiB |
| idle PSS | **172-174 MiB** | 255 MiB |
| idle CPU over 60 s | 0.05 % settled / 0.25 % first minute | 0.13 % |
| idle wakeups (main thread) | **0.6/s** settled; ~7/s during first-minute service ramp | 2.5/s |
| threads / fds at idle | 16-19 / 78-82 | 20 / 93 |
| long-lived children | clipboard watch (+2 wl-paste), 1 voxtype follower | 2 wl-paste, **2 voxtype followers**, periodic weather curl |
| panel open (incl. ipc overhead ~46/39 ms) | 30-91 ms (network 91 worst) | 32-56 ms |
| launcher cold / warm | 50 / 32 ms | n/a (walker, external) |
| frame work (sync+render), animation paths | median 0 ms, p99 19 ms, max 26 ms; 4/110 frames > 8.3 ms, 2 > 16.6 ms | not measured |

**Honest verdict.** Idle memory: we win by ~83 MiB PSS (32 % lighter). Idle
CPU/wakeups: we are quieter once settled (0.6/s vs 2.5/s), noisier during the
first-minute service ramp. **Startup: omarchy wins decisively — 193 vs 515 ms
to a live IPC surface (2.7×)** — and this is despite them eagerly loading
*more* (11 of 26 plugins are `keepLoaded`, including the full menu tree and
the 108 KB emoji JSON). Their lead is architectural: plugin Loaders and
`Qt.createComponent` run `asynchronous: true` off the critical path, while our
entire module tree parses synchronously before quickshell registers any IPC
handler. Frame smoothness: ours has no systemic jank; the only >16.6 ms frames
are the wallpaper-upload frame of the theme reveal and the launcher cold open.

## 2. Long-running behavior (the leak test)

Exercise per round (ours): 8 bar panels + 8 overlays open/closed ×20 each,
61 notifications via gdbus (incl. 10 replacing one id), 30 OSDs, 4 theme
switches. Two rounds, 10 min idle after each. Omarchy got an abbreviated
equivalent (7 panels ×20, 60 notifications, 2 theme switches, 5 min idles).

| checkpoint | qshell PSS | omarchy PSS |
|---|---|---|
| settled baseline | 172.2 MiB | 255.4 MiB |
| after exercise round 1 | 315.2 (+143.0) | 312.0 (+56.6) |
| after idle | 303.7 | 321.2 (+9.2 *during* idle) |
| after exercise round 2 | 307.4 (**+3.7**) | 354.4 (+33.2) |
| after final idle | **301.4** | **312.6** |
| fds / threads / children | flat (78-86 / 16-20 / stable) | flat (89-110 / 15-20 / stable) |

**No unbounded leak in either shell.** The discriminator worked: our round 2
added just +3.7 MiB where round 1 added +143, so the growth is one-time
lazy-loader residency, not per-use accumulation. Our memory decays
monotonically during idle; omarchy's oscillates (±40 MiB, including growth
while idle — their 15-min ungated weather refresh fires regardless) but
recovers. Fully saturated, the two shells converge to within 11 MiB (301 vs
313) — **the real difference is that we start 83 MiB lighter and pay on first
use, and our warm state is stabler.**

Where the one-time +143 MiB goes (evidence from code audit + the panel-probe
delta measured at baseline):
- ~22.5 MiB: the 8 bar-widget panels' LazyLoaders staying resident (measured
  directly: PSS 174.4→196.9 after one open of each).
- ~40-70 MiB: the theme-switcher and wallpaper-picker filmstrips. Each tile
  latches its 768 px decode once seen (`FilmstripPicker.qml:246-248`,
  deliberate — commented "never re-decodes") with `cache: true`, and the
  picker LazyLoaders never deactivate. 19 themes + ±16 nearby wallpapers ≈
  1.3 MiB each.
- The current wallpaper's full-res decode in `QQuickPixmapCache`
  (`Background.qml` `base` has `cache: true`, no `sourceSize`; a 4K source is
  ~33 MiB RGBA). Round-2 stability shows the cache *evicts* superseded
  wallpapers — bounded, but the working copy is oversized.
- Launcher/menu/emojis/clipboard/OSD/notification-popup residency + QML/JS heap.

Only Lock and Polkit ever unload (`shell.qml:287`, `Polkit.qml:335`);
everything else in the tree is one-way `active = true`.

**Process hygiene: clean.** No stray processes after either shell was killed
(the lone `curl --unix-socket ...tailscaled.sock` long-poll belongs to
`taildrop-receive.service`, a systemd unit, by design). Our pdeathsig coverage
is complete — including the voxtype follower, which is wrapped inside
`bin/voxtype-status` (`exec setpriv --pdeathsig TERM voxtype ...`), and the
clipboard watcher which additionally reaps a previous instance's strays. We
deliberately did not run omarchy's speedtest: reading their script shows every
run orphans 16 infinite curl loops (`trap cleanup EXIT` only — bash skips EXIT
traps on untrapped SIGTERM, which is exactly what `Process.running = false`
sends; no pdeathsig either). Ours sends SIGTERM to a script that traps it.

**Session-state races found during measurement** (real-user impact, trivial):
- A `bar hide`/`show` cycle can leave `~/.local/state/qshell/bar-off` behind
  when show races the file write — the next shell start comes up hidden.
  (Happened during frame measurement; removed the file to recover.)

## 3. Code findings (with the numbers to back them)

### Confirmed issues, ours
1. **Wallpaper images decode at native resolution** —
   `Modules/Background/Background.qml:280-332`: three per-screen `Image`s, no
   `sourceSize`, `cache: true` on `base`, `mipmap: true` (+33 % texture) on
   both transition frames. The omarchy-ported teardown (sources cleared once
   `base` is Ready, transients `cache: false`, transition FBO gated) IS
   already in place and working — the remaining gap is decode size. LockView
   (`LockView.qml:129-137`) already does this correctly.
2. **`revealMask` FBO never gated** — `Background.qml:340-341`:
   `layer.enabled: true` unconditionally on a screen-sized mask layer used
   420 ms per theme switch. (Omarchy has the same flaw — chance to beat them.)
3. **Conditional runaway timer** — `Modules/Lock/Lock.qml:533`: the 100 ms
   repeating `pendingSessionLockTimer`'s only `stop()` is on the success path;
   the `!lockRequested` early-return at `Lock.qml:99` leaves it firing 10 Hz
   forever if a lock request is withdrawn while pending.
4. **Weather poll ungated by visibility** — `Weather.qml:311`: the 30-min
   timer (approved exception) has no `pollingAllowed` gate (compare
   `Dropbox.qml:37`), so it fetches while the bar is hidden — and ×N screens.
5. **Workspace model churn on the hottest path** — `Services/Niri.qml:99-119`
   rebuilds the workspaces array with fresh object identities on every
   workspace/focus event; `Workspaces.qml:15,38` filters it again and feeds a
   plain-array `Repeater`, so every focus change destroys and rebuilds every
   workspace delegate, per screen. Same class: `Niri.qml:133-158` clones the
   whole windows map on every title change. This is steady GC/scene-graph
   pressure — the main long-session smoothness risk we found.
6. **`popupModel` uncapped + critical toasts immortal** —
   `Services/Notifs.qml:226-234` no cap; `durationFor` returns 0 for Critical
   (`:94-95`) and `Popups.qml:120` never ticks them. A misbehaving app grows
   the toast stack + 11 retained signal closures per notification without
   bound. (Omarchy: identical gap.) History (`pendingModel`/`pastModel`) is
   correctly capped at 100 + 15-min TTL.
7. **Cap-eviction orphans cached notification images** —
   `Notifs.qml:252-253, 269-270, 303-304` don't call
   `maybeDeleteCachedImage` the way dismiss/clear/prune do. Disk-only growth
   in `~/.cache/qshell/notification-images/`.
8. **Album art at full resolution, cached forever** —
   `MediaPanel.qml:119-126`: no `sourceSize`, default `cache: true`, drawn at
   ~64 px. Every distinct cover art of a listening session accumulates.
9. **Per-screen duplication of services** — every bar widget instantiates per
   screen (`Bar.qml:492`): TailscaleService (11 Process + 6 Timer),
   DropboxService, RcloneRemoteService ×2 (icloud + dropbox-rclone), the
   Weather fetcher, the Dictation voxtype follower, and 7 inotify watchers.
   On this 1-screen box it only doubles rclone; on a multi-monitor setup it
   multiplies everything. (Omarchy has the same disease — they even built a
   `broadcast()` IPC relay to paper over it.)
10. **Keystroke-rate model rebuilds** — Emojis (`Emojis.qml:83-104`: clear +
    up to 1000 appends per keystroke), Clipboard (50 rows), Launcher (full
    rescan+sort). Bounded, cosmetic-cost only.

### Verified non-issues, ours
- Timer gating is otherwise disciplined: 17/23 repeating timers gated on
  panel-open/visible, Bluetooth discovery and Wi-Fi scanner disarmed on all
  three exit paths, Pipewire trackers bound to `panel.opened`.
- No polling at steady idle: measured 0.6 wakeups/s, 0.05 % CPU. The
  no-polling claim holds (weather = documented exception; taildrop long-poll
  is a systemd service outside the shell, event-driven by design).
- Notification object lifecycle (live QObjects out of models, `Qt.callLater`
  mutation discipline, dedup on replaces-id, debounced persistence) is sound —
  it is omarchy's design, correctly ported, with the same one gap (popup cap).
- fd/thread/child hygiene: flat across 40+ min of abuse.

## 4. Prioritized improvement plan

### Quick wins (one sitting, low risk — biggest first)
| # | change | expected gain | risk | effort |
|---|---|---|---|---|
| Q1 | `sourceSize` (screen × dpr) on `base`/`oldFrame`/`incomingFrame` in Background.qml | caps every wallpaper decode at display size; on 4K+ sources tens of MiB per decode, ×3 during transitions; beats omarchy (they forgot it too) | low — LockView is the in-repo template | 3 lines |
| Q2 | drop `mipmap: true` on the two transition frames | −33 % texture ×2 ×N screens during theme switch | negligible (drawn ~1:1) | 2 lines |
| Q3 | gate `revealMask.layer.enabled` on `incomingBackground !== "" && revealProgress < 1` (mirror `incomingLayer`) | frees a screen-sized FBO per output outside the 420 ms reveal | low — verify maskReady still latches on first frame | 1 line + test |
| Q4 | `sourceSize` + `cache: false` on MediaPanel album art | stops full-res cover accumulation over music sessions | none | 2 lines |
| Q5 | `Lock.qml`: stop `pendingSessionLockTimer` on the `!lockRequested` path | kills a conditional 10 Hz forever-timer | none | 1 line |
| Q6 | cap `popupModel` (~10, overflow → pending) + finite floor for critical (e.g. 5 min instead of ∞) | bounds notification-storm memory and toast stack | low — keep critical sticky-ish, just not immortal | small |
| Q7 | call `maybeDeleteCachedImage` on cap-eviction in Notifs.qml | stops disk-cache orphaning | none | 3 lines |
| Q8 | `pollingAllowed`-gate the Weather timer (visible bar), Dropbox-style | no fetches while bar hidden; halves multi-screen fetch count | none | few lines |
| Q9 | make `bar hide`/`show` state-file write race-safe (write-then-verify or single writer) | no more "shell starts with bar hidden" surprise | low | small |

### Structural (each its own verified session)
| # | change | expected gain | risk | effort |
|---|---|---|---|---|
| S1 | **Async-load everything that isn't the bar** — `asynchronous: true` Loaders / staged `Qt.callLater` for Menu, pickers, Emojis, Polkit registration, Clipboard watcher spawn; queue pre-resolution IPC payloads (omarchy's `pendingPayloads` array pattern, `shell.qml:419-477`) | IPC-ready 515 → ~250-300 ms; closes the one metric omarchy clearly wins | medium — first-summon races; needs the payload queue | 1-2 sessions |
| S2 | **Hoist per-screen services to shell.qml singletons** (Tailscale, Dropbox, Rclone ×2, Weather fetch, voxtype follower), inject into widgets | on 1 screen: −1 rclone service; on M screens: ÷M timers/processes/watchers; fixes N voxtype followers | medium — service/view split touches 6 widgets | 1 session |
| S3 | **Workspace/window model diffing** — id-keyed stable delegates or `sameIds()` guard (pattern exists at `Bar.qml:112-119`) for `Niri.qml` workspaces; revision counter instead of map clone for windows | eliminates delegate rebuild on every focus change and map clone on every title change — the top long-session smoothness item | low-medium | ½ session |
| S4 | **Residency policy for heavyweight lazy loaders** — unload pickers/emojis (the ~40-70 MiB filmstrips) on close after a grace period (lockLoader release at `shell.qml:281-288` is the in-repo template); keep launcher/panels warm for latency | reclaims most of the 130 MiB saturated-state cost for rarely-used surfaces; warm-open cost reverts to cold (~50 ms — acceptable) | medium — close-animation vs unload ordering | 1 session |
| S5 | steal omarchy's `inlineSettingsDelta` (BarModel.js:76-102) if/when bar settings become live-editable — patch live widgets on cosmetic config change instead of rebuilding every widget on every monitor | future-proofing the config hot path; ~25 lines of testable JS | low | small, when needed |

### For CREDITS.md (techniques observed in omarchy worth crediting when adopted)
Async plugin loading with pending-payload queues; `inlineSettingsDelta`
structural-vs-cosmetic diffing; `Qt.clearComponentCache()` on hot-reload;
out-of-process content-hashed thumbnail pre-render (`omarchy-menu-images`);
conditional transition FBO + explicit texture teardown (already ported into
Background.qml).

### Explicitly not recommended
- Copying omarchy's `keepLoaded` eager-panel approach to chase their panel
  latency — it is why they idle 83 MiB heavier; our 30-90 ms cold opens are
  fine at 120 Hz.
- Unloading bar-widget panel LazyLoaders aggressively — 22 MiB total for
  instant reopens across 8 panels is a good trade.
- Touching the taildrop long-poll — it is event-driven by design and not
  shell-owned.

## 5. Post-session state
Shell restored (`qs`, detached, normal env), bar visible and verified by
screenshot, everforest theme + original wallpaper restored, no stray
processes, no omarchy instance running. Uncommitted in-flight work untouched.
Nothing was committed.

## 6. S1 results (2026-08-06, structural session 1)

Async-load everything that isn't the bar. Same box, same methodology as §1
(3-4 cold runs, 50 ms IPC poll carrying ~40-51 ms `qs ipc` client overhead),
same handicap (an agent session resident, load ~2) — the day-of baseline
below was measured minutes before the change under identical load, so it is
the fair comparator; the §1 numbers are quoted alongside.

### Numbers

| metric | §1 report | baseline (day-of) | after S1 | Δ vs day-of |
|---|---|---|---|---|
| spawn → bar constructed | 345 ms | **371 ms** median (353-381, n=4) | **187 ms** median (137-193, n=4) | **−50 %** |
| spawn → IPC handler answers | 515 ms | **574 ms** median (555-592, n=4) | **376 ms** median (321-399, n=4) | **−35 %** |
| idle RSS (fresh, nothing opened) | 210-212 MiB | 200 MiB | **192 MiB** | −8 MiB |
| launcher cold / warm | 50 / 32 ms | 50 / 34 ms | 50 / 52 ms | unchanged |
| idle CPU (bench first minute) | 0.25 % (first-minute ramp) | 0.067 % | 0.267 % | ramp + 3 s warm pass, settles the same |

Raw logs: `bench/20260806-181719-aarch64.txt` (baseline), `bench/20260806-184003-aarch64.txt` (after).

**Verdict.** IPC-ready 574 → 376 ms external (−35 %; −27 % vs the §1 515).
The 250-300 target was not met on the external number, but ~45-50 ms of it is
qs-ipc client overhead and up to 50 ms is poll quantization (both also inside
the §1 numbers, including omarchy's 193): server-side ready is ~300-330 ms.
The remainder is structural and measured, not assumed: `bench:root-done`
instrumentation showed the root completes 3 ms after first-bar, and a floor
test with ALL startup wakes removed still measured 483-490 ms (pre-panel
conversion) vs 497 with them — i.e. ~150-170 ms after root completion goes to
quickshell window/renderer init that no QML staging removes. The two levers
that actually paid were compile-time ones. Omarchy's 193 ms remains ahead
because their first paint trails their IPC; ours leads it — after S1 our BAR
is on screen at 187 ms, six milliseconds before their first handler answers,
and the unplanned bonus is that first paint HALVED (371 → 187 ms).

### What was done

1. **shell.qml no longer names any non-bar module type.** Every overlay/
   surface moved to a `SurfaceLoader` (a `Loader` + `setSource(url, props)`;
   quickshell's `LazyLoader` has no source-URL form and cannot satisfy
   `required` properties). QML resolves types named in a document before the
   root can instantiate, so the old inline `component:` blocks compiled the
   entire Menu/Launcher/Emojis/… trees before the first IpcHandler existed.
   Now those trees compile on first summon.
2. **Pending-call queue** (omarchy's pendingPayloads, their shell.qml
   summon/deliverIfLoaded): `summon()` wakes the loader and either calls the
   method or queues `{method, args}`; `onLoaded` replays in arrival order.
   `deliver()` (hide/cancel verbs) reaches a live or in-flight surface but
   never wakes a cold one. IPC racing a load is queued, never dropped.
3. **Startup staging.** Clipboard wakes at root completion (its capture
   watcher must not miss early selections; wl-paste re-fires on watch start,
   so only a selection made and replaced inside the first beat could slip).
   Background, OSD, Polkit, and the notification popup surface (if
   `everNotified`) wake on a 400 ms one-shot — immediate wakes cost ~15-30 ms
   of IPC latency to incubation contention.
4. **Warm pass at +3 s**: `Qt.createComponent(url, Asynchronous)` for
   Launcher, Menu, Lock — compile-cache only, nothing instantiates. Launcher
   cold open stayed at 50 ms (the cache is URL-keyed, so warm URLs must be
   byte-identical to the summon URLs).
5. **Bar widget panels off the bar's own critical path** — the second, bigger
   lever, and why first-bar halved: all 13 panel `LazyLoader { component:
   XPanel {…} }` blocks (Network ~2100 lines, Tray, Ai, Tailscale, Monitor,
   RcloneRemote, Bluetooth, Power, Weather, Dropbox, Audio, Media, Calendar)
   became invisible plain `Loader`s fed by `setSource` at `openPanel()`.
   Injected props preserved 1:1; Clock's `settings` (reassigned on format
   cycling) kept live via a `Binding`; the two `.active &&` conjunction
   checks (BluetoothWidget, Media marquee) now key on `.item`.
6. **Synchronous by contract, still off the startup path**: Lock
   (`lockSession()` must truthfully return missing-pam) and FilePicker
   (portal `pick()` answers with the real queue result) load with
   `asynchronous: false` on first use; both trees still compile at use time,
   not startup. Lock's release cycle re-verified (preview → loaded:true →
   hidePreview → loaded:false).

### Gotcha discovered (cost one bug, now documented)

shell.qml loads through quickshell's URL interceptor, so a *relative*
`setSource` from it resolves into the intercepted scheme, under which
**implicit same-directory type resolution fails inside the loaded file** —
Popups.qml could not see NotificationCard ("NotificationCard is not a
type"), while the widget-level panel loads (whose caller documents come from
the plain-file import path) were unaffected. Fix: `shell.moduleRoot =
"file://" + Quickshell.shellDir` prefixed on every surface URL (and the warm
list, for cache-key identity). Caught by the early-notification test, which
is exactly why it is on the checklist.

### Race-test evidence (checklist §2)

`<target> show` fired in a tight loop from t=0 against a cold shell; first
accepted call, its reply, and the surface then verified open by screenshot:

| target | accepted at | reply | surface verified |
|---|---|---|---|
| launcher | +317 ms | ok | screenshot: open, bar rendered |
| menu | +388 ms | ok | screenshot: open at root |
| theme | +341 ms | ok | screenshot: filmstrip on Everforest |
| emojis | +340 ms | ok | screenshot: grid + search field |

Each call landed while the surface's tree was still resolving — the queue
replayed it; nothing was dropped. `menu open <route>` while resolving queues
`openRoute` and replies "ok" (the §1-era reply was the route result; only
this sub-second race window differs).

### Full-surface verification (checklist §3-§6)

- All targets answer post-settle: shell, bar, launcher, menu, theme, emojis,
  clipboard (2 wl-paste watchers up), wallpaper, background, osd, notifs,
  reminders, filepicker, idle, lock (status/state), polkit, media,
  nightlight. (`bluetooth` exposes open/close/toggle, no status — unchanged.)
- All 13 converted panels open: 10 via `bar open <id>`, the 3 whose widgets
  were legitimately hidden (tray/media/dropbox — no SNI items, no player, no
  daemon) force-opened via QSHELL_TEST_PANEL; correct empty-state cards,
  zero QML errors across every run.
- Notifications: gdbus Notify at t+1 s pops a toast (the popup surface
  async-loads on first notification and replays), late one likewise;
  history, dismissAll fine.
- Polkit: `registered:true` shortly after start (staged registration),
  `pkexec true` produced the dialog (screenshot), IPC `polkit cancel`
  dismissed it (pkexec exit 126).
- Theme round-trip everforest → gruvbox → everforest via bin/theme-set: bar
  foreground tracked (#d3c6aa → #d4be98 → back), `background
  themeTransition` served by the async-loaded surface, wallpaper verified by
  grim gap-column sample (everforest greens).
- Idle RSS 192 MiB fresh (better than both baselines — the 13 panel trees'
  compiled-type metadata no longer loads at startup); 215 MiB after every
  panel + overlay had been opened, consistent with §2's one-time residency.
- Log clean (only the pre-existing Qt.atob deprecation warnings from the
  theme transition's base64 payload), shell restored and healthy, nothing
  committed.

### Could NOT move off the critical path, and why

- **Bar** — it is the product's first paint and the cold-start anchor;
  S1 made it *faster*, not later.
- **Theme, Niri** (bar dependencies), **Notifs** (must own
  org.freedesktop.Notifications from startup), **Idle** (unarmed idle
  monitor is not an idle monitor), **Audio/Media/Battery/Nightlight/Sync**
  (keybind/widget contracts; each individually cheap) — all §1-eager by
  design and untouched.
- **~150-170 ms of post-root quickshell window/renderer init** before the
  IPC socket answers — measured as the gap between root-done (+3 ms after
  first-bar) and first external answer with zero wakes scheduled. Not
  addressable from QML; would need quickshell-side changes (e.g. answering
  IPC before the first surface commit).

### For CREDITS.md (do not edit yet — noting for the eventual entry)

Adopted in S1: omarchy's async plugin loading with a pending-payload queue
replayed on Loader resolution (their shell.qml `summon` /
`pendingPayloads` / `deliverIfLoaded`), generalized here into SurfaceLoader's
summon/deliver/replay with per-surface queues.

## 7. S2+S3 results (2026-08-06, structural sessions 2–3)

Same box, same handicap (agent session resident), same methodology. Day-of
baseline re-measured minutes before S2 under identical load. Commits:
S2 = 9c3b09e, S3 = c29c2d8.

### S2 — per-screen services hoisted to bar-root singletons

Every daemon-backed widget owned its service object, so each screen's copy
duplicated the full stack (§3.9). The services now live at the bar root —
Bar.qml's Scope is ONE instance however many screens its `Variants` fans out
to — created lazily by the first widget that asks (config presence still
gates existence) and injected into every screen's widget by the registry
components. Weather's fetch stack became `WeatherService.qml` (3 curl
Processes, 3 Timers, the legacy-location FileView); the voxtype follower
became `DictationService.qml`.

Instantiations per service (temporary `console.info` in
`Component.onCompleted`, counted from the startup log):

| service (per-instance stack) | before | after |
|---|---|---|
| TailscaleService (11 Process + 6 Timer + 1 FileView) | 1 × screens | **1** |
| DropboxService (3 Process + 5 Timer) | 1 × screens | **1** |
| RcloneRemoteService (2 Process + 2 Timer) | 2 × screens | **2** (one per remote — icloud + dropbox-rclone are different remotes, correctly not merged) |
| Weather fetch stack (3 Process + 3 Timer + 1 FileView) | 1 × screens | **1** |
| Dictation voxtype follower (1 long-lived child) | 1 × screens, **2** while recording (the Indicators active block mounts a second copy) | **1** always |

This is a 1-screen box, so the counts are flat here; the fix is structural —
creation happens in the Scope, outside the per-screen delegate, so M screens
now share one instance where they multiplied before. Wins realized on this
box regardless: the transient second voxtype follower while recording is
gone, and tailscale/dropbox polling now actually stops during `bar hide`
(the old gate keyed on Item.visible, which a hidden *window* never touches;
the new gate is the report's Q8 pattern: ANY bar visible && widget still in
the layout).

Design decisions (documented per plan):
- **Settings = the config's own inline entry.** A shared service binds
  `settings` to `inlineEntryFor(id)` rather than one widget's copy — every
  screen renders the same entry, so first-widget-wins and config-wins name
  the same object, and the config outlives widgets. `updateEntryInline`
  applies in memory before persisting, so panel settings writes still land
  in the service synchronously. One divergence: with a broken-on-disk
  shell.json (configWritable false) a settings edit no longer half-applies
  to the local widget — it is refused whole, which is the honest behavior.
- **Services survive their widgets.** A screen unplugging must not kill the
  daemon conversation the remaining screens render; removing the id from
  the layout stops the polling instead (the gate above).

Verification: all four daemon panels live through the shared services
(tailscale tailnet card, weather Dhaka report + bar temp, icloud
reachability probe, dropbox-rclone quota 2.49/2.55 GB), dropbox
empty-state card via QSHELL_TEST_PANEL, bar hide/show cycles clean,
children (1 voxtype follower + clipboard watcher) and fds (81) identical to
baseline, log clean.

### S3 — workspace delegates stable, windows map in place

`Workspaces.qml` now feeds its Repeater the id sequence only, held back by
the sameIds guard (Bar.qml's syncModels rule); each live delegate re-resolves
its workspace object from the fresh `niri.workspaces` per event. `Niri.qml`'s
windows map is mutated in place with a `windowsRevision` counter as the
change signal — `focusedTitle`/`focusedAppId` reference the revision, and
imperative event-time readers (Notifs' click-to-focus) read the live map.

| churn metric (instrumented both sides, same drive) | before | after |
|---|---|---|
| delegate creations, 10 × focus-workspace round trips | 20 (N per change) | **0** |
| delegate creations, 20 rapid cycles | 40-equivalent | **0**, no visual glitch |
| windows-map replacements, open + 5 OSC-0 title changes + close | 8 | **0** |
| windows-map replacements, ambient (startup + first minutes, live terminal titles) | 78 | 2 (the WindowsChanged snapshots) |

Membership changes still rebuild, as they must: occupying the trailing empty
workspace (2→3) created 3 delegates, the shrink back created 2 — a plain
array model rebuilds wholesale on identity change, which is exactly the
Bar.qml precedent and only fires when the id sequence really changed. The
bar's ActiveWindow title tracked all five OSC-0 changes live
(screenshot-verified) with zero map replacements; focused dot / index /
empty dimming all render as before.

### Bench (medians not taken — single runs, all within S1's run spread)

| metric | §6 after S1 | day-of baseline | after S2 | after S3 |
|---|---|---|---|---|
| spawn → bar constructed | 187 ms | 200 ms | 195 ms | **184 ms** |
| spawn → IPC ready (external) | 376 ms | 369 ms | 397 ms | 386 ms |
| idle RSS | 192 MiB | 199 MiB | 195 MiB | 196 MiB |
| launcher cold / warm | 50 / 52 ms | 57 / 45 ms | 53 / 85 ms | 55 / 53 ms |

No regression; the deltas are run-to-run noise (S1's IPC spread was
321–399 ms). Raw logs: `bench/20260806-191504` (baseline), `-192509` (S2),
`-193117` (S3).

### Not deduplicated, and why

- **RcloneRemoteService ×2** — one per remote (icloud, dropbox-rclone), not
  per screen; merging them would merge two different backends.
- **The small per-widget FileView watchers** (SystemUpdate, ScreenRecording,
  Reminder, AiClaude's credentials watch — the rest of §3.9's "~7 inotify
  watchers"): each is one inotify fd and a few lines of trivially-shared
  state, none spawns recurring processes, and their refresh processes are
  event-driven one-shots. A service/view split per widget would cost more
  code than the fd it saves on a multi-monitor box; revisit only if a real
  multi-screen setup shows measurable cost.
- **Bar.qml's own two FileViews** (wallpaper sample, bar-off flag) were
  already Scope-level singletons.
- **The startup fallback→real-config slot rebuild** (4 instead of 2
  workspace delegate creations at startup, both before and after S3): the
  bar's section Repeaters rebuild every WidgetSlot when shell.json lands
  because modelLeft's id sequence really changes
  (fallback has no launcher). That is a one-time cost of the
  broken-config-safe startup, not steady-state churn — left alone.
