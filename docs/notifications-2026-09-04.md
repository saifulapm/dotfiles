# The notification center, after the community plugins — 2026-09-04

User ask: pull every notification-related plugin from the omarchy **community**
marketplace and improve our notification center with what they got right.

**Nothing was installed.** All sixteen repos target `omarchy-shell` on
Hyprland — `omarchy plugin add`, `~/.config/omarchy/plugins/`, `hyprctl`,
omarchy's own `omarchy.notifications` service. This is niri and our own
Quickshell tree, so this is the same rule as the 2026-08-21 marketplace port:
the upstream repos were read for behaviour and for the decisions worth
keeping, and everything here is written against our own service. The clones
are at `~/ref/notification-plugins/` for reading.

## Where the marketplace is now

`HANCORE-linux/omarchy-plugin-marketplace` → **`omacom/omarchy-plugin-marketplace`**
(the same 301 the main repo took). **2179 sources**, up from 812 on
2026-08-25. `registry.json` is 3.8 MB, and worth knowing before writing a
query against it: **only 2 of the 2179 entries carry a `catalog` block** —
name, description, tags and category are all null for everything else, and
the site fills them in by fetching each repo's manifest. Filtering the
registry means filtering on the repo URL.

Sixteen repos matched on name. One false positive: `Cozidian/omarchy-dnd` is
a **Dungeons & Dragons 5e SRD lookup**, not Do Not Disturb.

## What we already had

Worth writing down so the next audit does not re-flag it:

| Their feature | Ours |
|---|---|
| Browser origin strip (`abran-labs/BodyText.js`, herald) | `Logic.sanitizeBody`, Chromium-gated, since the 2026-09-04 delta |
| `<img>` stripping | We are **ahead** — a whole-tag walker; theirs is the naive regex that manufactures a tag |
| A visible way to close a toast (`WhiteWebDev`) | Hover-revealed close, ported from omarchy `9b72edc` |
| Never execute stored shell text (jankeesvw, ritechoice23) | argv through a constant `exec "$@"`, reasoned out at `Notifs.qml:540` |
| Keyboard nav, DND, per-row dismiss, clear, action chips, click-to-focus | Already in the panel |

## What landed

### 1. History stops dying after fifteen minutes

`pastTtlMs = 15 * 60 * 1000` swept every *seen* notification a quarter of an
hour after it arrived. `notifications.json` was 66 bytes on a working machine
— the DND flag and nothing else. The panel could answer "what did I just
miss" and nothing else.

Now: `historyKeepDays = 30` and `historyCap = 1000`, **both** limits, per
bucket. Either alone fails in one direction — an age limit lets a
notification storm keep thousands of rows, and a count limit alone keeps a
quiet machine's notifications for years. Thirty days is what both durable
history plugins settled on (jankeesvw's and ritechoice23's).

Pruning moved from a **one-minute** timer to an **hourly** one and now sweeps
`pendingModel` as well as `pastModel`. A minute's precision on a thirty-day
cutoff bought nothing and cost a wakeup a minute for the life of the session;
`triggeredOnStart` matters more than the interval on a laptop that is
suspended most of the day. Sweeping pending too is not optional — leaving it
unswept would let the bell carry a badge that nothing can ever age out.

### 2. The list is chronological now, grouped by day

The panel used to stack UNSEEN above RECENT. That was right for a
fifteen-minute window and wrong the moment history became durable: a
three-day-old unseen entry would have sat above everything that arrived
today. Both buckets now merge, sort newest-first, and carry a **TODAY /
YESTERDAY / weekday / date** header; unseen became a per-row mark instead of a
section, which is what makes the chronological list possible at all.

Two things that had to be got right:

- **The day is the LOCAL day.** A notification at 01:00 belongs to the day you
  were awake for, not to whatever UTC calls it.
- **`dayBounds` steps a calendar day, not `+ 86400000`.** A DST-shifted day is
  23 or 25 hours long, and a fixed step would have left an hour of it outside
  the range the per-day CLEAR acts on.

The names are spelled out in `WEEKDAY_NAMES` / `MONTH_NAMES` rather than
formatted, because **Quickshell's QML engine has no ECMA-402** — `Intl is not
defined`, measured in the real engine while porting the world clock
(`docs/marketplace-ports-2026-08-21.md`, gotcha 6). There is no
`toLocaleDateString(locale)` to call.

### 3. Search

`/` or `Ctrl+F` focuses the box; every whitespace-separated term has to hit
the app name, summary or body, so `signal aisha` narrows instead of widening.
Escape drops the filter and hands the keys back to the card, and a second
Escape closes the panel — the ladder the rest of the shell uses.

The box is always visible when there is anything to search, rather than
hidden behind a magnifier: the box *is* the affordance, and a toggle that
reveals it is one more thing to discover for no less space.

Filtering re-sections what is left, and a day header's count describes the
**filtered** list. That is a test, not an accident — the obvious
implementation leaves the pre-filter counts in the headers.

### 4. Per-app mute

The gap between DND's all-or-nothing and living with an app that pings all
day. Right-hand button on any row, `m` on the keyboard, or `notifs mute <app>`.

- **Substring, case-insensitive** (`abran-labs/Rules.js`'s reasoning, and it
  holds here for the same reason): `app_name` is not a stable identifier. The
  same program says "Vesktop" from a desktop entry and "vesktop" from a
  shell, and Electron senders drift between releases. An equality rule goes
  stale silently — the app keeps notifying and the rule still looks on. The
  cost is that a short rule matches broadly, which is only tolerable because
  a rule is never typed: it is taken from the notification's own app name.
- **A muted sender's record still lands in history, but goes STRAIGHT TO
  PAST.** Pending is what the bell counts, so routing a muted app there would
  have traded a toast for a badge and silenced nothing.
- **A third-party "critical" does not buy an exemption.** The escape hatch is
  the one DND already uses (`shouldBypassDnd`: our own `qshell` notifications
  and a critical `notify-send`), so a mute can never hide the shell's own
  crash toast — but the urgency flag on a muted app's own notification is set
  by the app being muted, and an app that can promote itself out of a mute is
  not muted.
- The **MUTED** list at the foot of the panel is the other half of the
  feature, not a detail of it: a mute you cannot see is indistinguishable
  from an app that has stopped working.

### 5. Sound

One `canberra-gtk-play -i <event>` per fresh toast, so the installed theme
decides what a notification sounds like and we only decide which event it is.
`dialog-warning` for critical, `message-new-instant` for normal, `message`
for low — a critical toast that sounded like a chat message would be a
critical toast nobody looks up for.

**Nothing was installed for this**: `canberra-gtk-play` and the `freedesktop`
sound theme were both already on the machine. `fab679/virtuoso.notification-sounds`
ships its own 45-sample KDE Ocean theme and a systemd watcher that sounds
events which never *produce* a notification (AC, battery, bluetooth,
network); only the notification half is here, because the other half is a
separate feature that deserves its own decision.

Fired only from the fresh-toast path, so a shell restart replaying the popups
that were on screen does not sound them all again, and neither does the
history-replay keybinding. Silenced by DND, by a mute, and by its own toggle
(the speaker button beside DND, `s`, or `notifs setSound off`).

### 6. Permissions

The tree went from holding fifteen minutes of notifications to holding thirty
days of them, bodies included — every two-factor code and chat message of the
last month — and it was mode **0644 in a 0755 directory**. Now `0700` on
`~/.local/state/qshell/`, its `notifications/` popup dir and
`~/.cache/qshell/notification-images/`, and `0600` on `notifications.json`.
Same reasoning as both durable-history plugins, which are 0700/0600 for
exactly this.

`mkdir -m` only applies its mode to a directory it *creates*, so the startup
command chmods as well as mkdirs — the directories already existed. The popup
writer carries `umask 077` for the case where a notification beats the
service's own mkdir.

**Verified rather than assumed:** the history file's `0600` is set once at
startup, not after every save, because `FileView` writes atomically through
`QSaveFile`, which carries the existing target's permissions onto its
replacement. Checked on this machine — the file was still `-rw-------` after
a save had grown it from 66 to 775 bytes.

## The UI, since it was rebuilt anyway

A row is three things wide and two things tall:

```
┌──────┬──────────────────────────────────────────────┐
│ icon │ SIGNAL  Aisha                       [󰂛] [󰅖]  │
│  4m  │ on my way, ten minutes out — traffic on the… │
└──────┴──────────────────────────────────────────────┘
```

- **The sender is named on every row**, which it was not before: it used to
  appear only as a stand-in when the body was empty. Fine for a list you had
  just watched arrive; over thirty days, who sent it is the first thing you
  need and the last thing the summary reliably says.
- **Sender and title share the heading line.** The sender had a line of its
  own for one iteration, which is a whole line spent on a word — over three
  day sections that is a third of the list given to something read at a
  glance. The sender is capped at a third of the line so a long app name
  cannot push the title it introduces off the row; the title elides.
- **The age lives under the icon**, not at the far right of the heading. On
  the right it put the two least important things in the row — who sent it
  and when — at opposite ends of it, and spent line width on a string four
  characters long. In the gutter it costs no width at all.
- **Body gets two wrapped lines** instead of one elided one, at the **full
  width** of the row. A message you are looking up days later is usually the
  body, not the summary.
- **Unseen is the row, not a mark beside it.** The first cut drew a dot in a
  gutter, which cost every row that column permanently in order to say
  something about two of them. It is a faint accent tint on the row itself
  now (`CursorSurface.restingColor`, defaulted to transparent so the other 26
  call sites are pixel-identical) — and because it is the surface's resting
  state rather than a layer on top, hovering a tinted row still shows the
  hover fill.
- **A row does not change size when you point at it.** Two separate causes,
  both found by looking at it:
  - The mute/dismiss buttons used to sit centred on the right edge with the
    text column anchored to them, so revealing them narrowed the column,
    rewrapped the body onto a third line, grew the row and shoved every row
    below it down. They are on the **heading line** now, where they take width
    from the title instead of from the message — which is also what gives the
    body its full width. They fade rather than appear, so the space is
    reserved either way and the heading line's height is the buttons' height
    whether or not they are showing.
  - The live-action chips were gated on the pointer for freshness (`liveRefs`
    is a plain JS map and mutating it emits no change signal). They now depend
    on the row list instead, so they refresh on a model rebuild and never
    appear or vanish under the pointer.
- **Tighter icon.** The slot was `space(9)` square — a wide empty column with a
  small glyph adrift in it. `space(6.5)` now, with the row's vertical padding
  down from `space(3)` to `space(2.5)`.
- **The list sizes to the screen** rather than to a fixed `space(100)`. The old
  constant left a third of the screen empty under a panel that was already
  scrolling. It is still bounded, and deliberately: BarPanel clamps the
  *card*, and a column that asks for more than fits is not shrunk, it is
  clipped — the muted list would have silently vanished off the bottom.
- **Edge fades** at the top and bottom of the list when there is more that way.
  A ListView clipped mid-row says nothing about why the row is sliced, and
  this shell has no scrollbar to say it with: **QtQuick.Controls is not a
  dependency** (BluetoothPanel's note), and adding it for one cue would have
  been the wrong trade.

## Every toast is a drag source (same day, follow-up ask)

Before this, exactly two notifications could be dragged: a Taildrop arrival
and the ytdlp download toast, both because their `qshell-exec-argv` hint named
the file. Everything else — screenshots included — was inert.

`Logic.dragPayload` now answers three questions in order, and every toast
carries whichever one hits:

| Kind | Payload | Where it comes from |
|---|---|---|
| `files` | `text/uri-list` + paths | exec-argv allowlist, else `image`, else `app_icon` |
| `clipboard` | `text/plain` | what the service captured when the toast arrived |
| `text` | `text/plain` | the body, as plain text; the summary if there is no body |

### Why screenshots did not drag

**niri puts the saved PNG in `app_icon`, not `image`.** Captured off the bus:

```json
{ "app": "niri", "summary": "Screenshot captured",
  "body": "You can paste the image from the clipboard.",
  "image": "",
  "appIcon": "file:///home/saiful/Pictures/Screenshots/Screenshot%20from%20…png" }
```

`dragPaths` only ever read `image`, so it returned nothing. It reads
`app_icon` now — but `app_icon` is normally *decoration*, so two kinds of path
are excluded before it counts as a subject:

- **Icon-theme assets** (`/icons/`, `/pixmaps/`, `/share/app-info/`). A sender
  that names its icon by path hands over `…/thunderbird.png`, and dragging a
  notification must not scatter application icons around.
- **Anything under `/tmp`.** Chromium-family senders pass the sender's
  **avatar** as an `app_icon` in a scoped temp directory, so every web-chat
  notification would otherwise drag someone's profile picture. Deliberately a
  path test and not a sender test: a web notification's `app_name` is the
  origin (`web.whatsapp.com`), so `isChromiumDerived` never sees it — where
  the file lives is what identifies it.

That the toast keeps the *original* path is not luck: `rewriteCachedImage`
rewrites the cached copy into `pendingModel`/`pastModel` only, never into
`popupModel`.

### The clipboard payload, and the bug restoring a clipboard found

Captured when the notification **arrives**, not when the drag starts — every
one of our copy scripts runs `wl-copy` and then notifies, so arrival is the
one moment the clipboard is guaranteed to still hold what the toast is
announcing. Kept in memory and deliberately **not** a snapshot role: a role
would be written to `notifications.json`, and clipboard contents do not belong
in a thirty-day on-disk archive.

The read is `wl-paste --no-newline --type text/plain`, which **exits non-zero
whenever the clipboard holds no text** — and that is the common case here,
because niri's own screenshot puts a PNG on it. Found while restoring the
clipboard after a test: it held a 298 KB `image/png`. The first cut only
assigned on success, so a clipboard toast over an image clipboard would have
handed over *the text someone copied ten minutes ago*. `captureClipboardText`
clears before reading; empty is correct, and `dragPayload` falls through to
the body.

### Not the notification centre

The panel rows are **not** drag sources, and cannot usefully be. The centre is
a fullscreen `WlrLayer.Overlay`, so during a drag its own surface is under the
pointer everywhere and the drop can only land back on itself. Closing it when
a drag starts does not help either: that destroys the drag source mid-flight,
which is the same trap `Popups.qml` already holds a toast's expiry to avoid.

### Verified end to end

Not just in tests — the real thing, dropped on the real Shelf:

- **Screenshot toast → the PNG itself** lands in the Shelf with a thumbnail.
- **Ordinary toast → plain text.** `staging is live at <b>14:02</b> &amp;
  healthy` arrived in the clip file as `staging is live at 14:02 & healthy` —
  markup gone, entity unescaped once.
- **"Copied text to clipboard" → the clipboard**, `OCR result: the quick brown
  fox 12345`, not the sentence announcing it.
- **Same toast with an image-only clipboard → the body**, confirming the
  fallback above rather than stale text.

**Driving the drag is the fiddly part.** `mouse drag X1 Y1 X2 Y2` does not
work for a platform DnD: press → single jump → release inside 100 ms never
gives the compositor time to open a drag session. What works is the manual
form — `mouse to` the grab point, **dwell ~0.9 s** (the `grabToImage` pixmap
grab is asynchronous and happens on hover), `ydotool click 0x40`, then five
relative `wlrctl pointer move` legs at ~0.2 s each, then `0x80`. A
cursor-inclusive `grim -c` mid-drag shows the card pixmap in flight, which is
how you tell a started drag from a missed grab.

Also: **`wlrctl pointer move -10000 -10000` crashes wlrctl** (it produced a
"Process crashed: wlrctl" toast). The desktop skill already forbids pinning to
a corner by hand for a different reason — hot corners — and `scripts/mouse` is
the answer to both.

## Tests

`node shell/Modules/Notifications/NotificationLogic.test.js` — 40 tests,
26 of them new: mute matching, the local-day and DST boundaries, search
term-ANDing, the merge/sort/section pass, the sound mapping, the
persisted-state round trip, and the three drag payloads (including the real
niri screenshot notification as a fixture, the Chromium avatar case, and the
markup-to-plain-text conversion).

The one worth naming: **a v2 history file has no `sound` key, and it must
parse as `null`, not `false`** — reading a missing key as false would have
silently turned sound off for the machine that upgrades.

Verified live, against the real D-Bus path: sound fires and is suppressed by
the toggle and by DND (checked by watching for the `canberra-gtk-pl` process,
with a settle loop — a lingering player from the previous case will otherwise
report a false positive, and did once); a muted app adds nothing to `popups`
or `pending` and one row to `past`; `/` focuses the box without typing a
slash into it; the filter re-sections; Escape clears then closes.

## Not taken

- **Per-sender identity tables** (`abran-labs/Sources.js`, herald's
  `WhatsApp · Brave Origin` titles) — a curated colour and glyph per app.
  Cosmetic, and it needs hand-maintenance as app names drift.
- **Agent-turn alerts** (`omaherald`, `idandeshe/omarchy-claude-alerts`,
  `brianblakely/omarchy-codex-notifications`) — notify when Claude Code or
  Codex finishes a turn or waits on approval, and click-to-focus the right
  tmux pane. Genuinely useful next to `amx`, but it is a new notification
  *source*, not a notification-center change.
- `a3qz/omarchy-keybind-toast` (Hyprland Lua half), `MicahelE/donotify`
  (a paid phone-call reminder service), `robertlindomar/omarchy-ptbr`
  (a pt-BR translation of omarchy's own plugin).
