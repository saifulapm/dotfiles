# Minimap in the bar, browser scoped to the workspace — 2026-09-08

Two answers to the same complaint, one per half of the day's work: a
scrolling compositor and a shared browser both keep state you cannot see.

niri scrolls sideways forever, and nothing on screen says how much is parked
off each edge. You come back to a workspace and press Mod+Left to find out —
which is a guess, made by moving.

Chromium, meanwhile, has one profile spread over six workspaces (one per
project). Click a link in foot on the shopify workspace and the tab lands
wherever chromium last had a window activated — regularly a browser three
workspaces away, silently. The tab is opened, nothing shows up, and you go
hunting for it.

## What landed

- **A minimap under the clock** (`shell/Modules/Bar/widgets/MinimapStrip.qml`,
  `MinimapModel.js` + tests, worn by `Clock.qml`) — a row of hairline pills
  flush with the bar's inner edge under the date and time, one per column of
  the workspace this screen is showing, as wide as that column is on screen,
  the focused one in the accent color. Two windows stacked in a column split
  its pill.
- **`bin/browser-open`** + **`browser-open.desktop`** — the new
  `x-scheme-handler/http(s)` and `text/html` default. Puts the tab in THIS
  workspace's chromium window, and opens a new window here when there is
  none.
- **`Services/Niri.qml`** now carries each window's workspace, floating flag
  and place in the scrolling layout (`pos_in_scrolling_layout`, `tile_size`),
  and handles the `WindowLayoutsChanged` event that keeps them current.
- **`Prayer.qml` gained a vertical face** — found while checking the rail on a
  bar turned on its side: the widget drew its glyph and "Asr 16:25" in a Row
  at BOTH orientations, so on a 28 px column the text ran off both edges of
  the bar. It stacks now, the clock's way: glyph, name cut to three letters
  (Maghrib is legible at no size that fits), hour, colon, minutes.

## The minimap

### What the strip says

Pills are scaled against the SCREEN while everything fits on it, and against
the layout once it does not. So the strip's own length is a fact:

```
 ▁▁▁▁▁▁▁▁                    one column, half the screen — room to the right
 ▁▁▁▁▁▁▁▁ ▁▁▁▁▁▁▁▁           two columns, screen full
 ▁▁▁▁ ▁▁ ▁▁ ▁▁▁▁ ▁▁▁▁        five columns, more than a screenful — scrolling
```

### Where it lives

Not in a slot of its own — the clock wears it (user call, 2026-09-08: "no new
widget, just a bar below the date and time text"). The rail is a 2 px
hairline sitting FLUSH with the bar's inner edge — the one facing the desktop
— and as long as the face it belongs to: the label's width on a horizontal
bar, the stack's height on a vertical one, where it turns with the bar and
runs down the desktop-facing side as a border. Consequences worth knowing:

- The bar's layout never moves for it. The strip paints inside the width the
  label already claims, so opening a window redistributes pills instead of
  shoving the center anchor's neighbours sideways, and an empty workspace
  simply draws nothing.
- It is drawn chrome, not a control. The clock owns every click in that slot
  (calendar, format cycle, timezone picker), so there is no click-to-focus
  and no per-window tooltip — an earlier standalone-widget version had both,
  and putting them back would mean a 2 px band inside the clock that does
  something else.
- While the calendar is open, the rail fades out: the open-panel pill sits
  2 px off the same edge and is the same accent color, and the two together
  read as one thick bar rather than as columns.

### What it deliberately does not show

- **Which columns are scrolled out of view.** niri exposes
  `tile_pos_in_workspace_view` for exactly this, and on niri 26.04 it is
  `null` for every window including the focused one (checked 2026-09-08), so
  there is no view offset to dim anything against. When it starts reporting,
  the off-view columns can drop to half opacity and nothing else changes.
- **Floating windows.** They have no column and no place on a scrolling
  strip; a sign-in popup is not a place you can be.

### Implementation notes

- The service's window map gained the layout fields rather than a second map:
  it is already mutated in place per event with `windowsRevision` as the
  change signal, and the minimap is one more thing deriving from it.
- niri sends `WindowLayoutsChanged` on the SETTLED layout, not per animation
  frame — two events for two `set-column-width` calls, measured — so there is
  no cadence to throttle.
- `MinimapStrip` is reparented out of `BarButton`'s content Row (`parent:
  rootItem` in Clock.qml). Declared children land in that Row, which lays
  them out BESIDE the label; the rail belongs under it. It is then placed
  with x/y rather than anchors — a Row REFUSES horizontal anchors on its
  children, and the anchor dropped there does not come back when the reparent
  lands, which put the vertical rail against the screen edge instead of the
  desktop-facing one.
- The strip rebuilds on every window event (a terminal retitling
  itself is one) but only re-assigns it when it would draw differently
  (`MinimapModel.same`), which is Workspaces' `sameIds` rule: re-assigning an
  equal model destroys and rebuilds every delegate for nothing. A sub-pixel
  column resize does not survive the rounding, so animations do not churn
  delegates either.
- No `String.trimEnd` in Qt's JS engine — a missing method there is a runtime
  TypeError per window per event, found by reading the shell's journal after
  the first live start.

## The browser

`bin/browser-open` reads the focused workspace, finds the tabbed
`chromium-browser` window on it (floating popups and `chrome-<host>` webapp
windows are not candidates — chromium cannot put a tab in either, and would
quietly fall back to a browser somewhere else), focuses it, and only then
hands the URL to chromium. With no browser window on this workspace,
`--new-window` opens one, which niri maps where you are.

**The focus IS the mechanism.** Chromium gives a forwarded URL to the browser
window it activated last, so activating the right one first is what aims the
tab. Verified on this machine, 2026-09-08: two windows of a throwaway profile
side by side, focus A → open a URL → the tab is in A; focus B → open another
→ it is in B. The handoff waits for niri to confirm the focus (typically the
first pass of the poll) plus a beat for chromium to process the activation it
was just sent.

Then end to end through the real path, `xdg-open` on an empty workspace: the
first page opened a NEW chromium window there rather than joining the one two
workspaces away, and the second page joined that new window as a tab.

Which means the browser follows you, and this is also why focus lands on
chromium after a link: it is not a preference, it is the mechanism.

### Not covered on purpose

`Mod+Shift+B` / `Mod+Shift+Return` still raise the newest browser window
anywhere (`bin/launch-or-focus`), `bin/webapp-launch` still focuses a webapp
window anywhere, and `$BROWSER` is still unset — the ask was links opening in
the wrong place, and those three are all cases of ASKING for a browser rather
than opening something in one. Each is a one-line change to scope later.
