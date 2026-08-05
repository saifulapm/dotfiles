# qshell vs omarchy shell — measured 2026-08-06, MacBook Pro M2 (Asahi, 16K kernel)

Same box, same session, same method, back to back, load average ~2 during
both (an agent session was resident; both sides carry the same handicap —
treat the absolute numbers as upper bounds and the comparison as fair).

Method: `pkill -x qs`, spawn, poll a real IPC handler every 50 ms until it
answers (`shell ping` on ours, `omarchy.indicators refresh` on theirs — a
target listing via `ipc show` answers before config load and must not be
used), RSS from /proc after a 5 s settle, CPU as utime+stime delta over 60 s.
Both numbers include ~48 ms of `qs ipc` client spawn overhead and up to
50 ms poll granularity.

| metric                        | qshell (ours)     | omarchy shell     |
|-------------------------------|-------------------|-------------------|
| spawn → bar constructed       | **285 ms** (shell-reported) | not instrumentable (their code, unmodified) |
| spawn → IPC handler answers   | 428 ms            | **230 ms**        |
| idle RSS after 5 s            | **208 MiB**       | 257 MiB           |
| idle CPU over 60 s            | 0.083 %           | 0.067 %           |
| launcher open (cold/warm)     | 43 / 53 ms        | n/a (different summon path) |

## Honest verdict

- **Idle memory: we win by 49 MiB (19 % lighter).**
- **Idle CPU: a tie.** The difference is one scheduler tick over a minute;
  both are effectively zero. (Ours is down from 0.267 % at the six-widget
  baseline — the audit's timer/scanner fixes show up here.)
- **Startup: omarchy wins.** Their full plugin set has answering handlers at
  ~230 ms where ours answers at ~428 ms. Our bar itself is up at 285 ms,
  but quickshell registers IPC handlers only when the WHOLE config finishes
  loading, and everything that is not the bar — menu tree, pickers, lock,
  polkit, clipboard capture, emoji data, background — loads after the bar
  and before the handlers. Their config parses and instantiates less at
  startup than our module set does.

## Where our startup time goes (why, not guesses)

The log order proves the shape: `bench:first-bar 285 ms` prints BEFORE
"Configuration Loaded"; handler readiness lands with the latter. So the
startup cost is split bar-construction ~285 ms / remaining-modules
~100-150 ms. The six-widget baseline was 105 ms cold on an idle box; the
grown bar (15 widgets + indicators + tray + background) plus load-2
conditions accounts for the bar half.

If startup ever needs to win outright: defer the non-bar modules (they are
all IPC-summoned overlays — a Loader flipped by the first IPC call, or
Qt.callLater staging after the bar lands, would move them off the critical
path). Not done in the audit: it restructures module wiring across
shell.qml and deserves its own verified session.

Historical note: earlier bench entries sampled "idle RSS" AFTER the
launcher LazyLoader had been summoned resident; from 2026-08-06 the sample
is taken before any panel loads, so rss numbers are not comparable across
that boundary (they overstated idle by the launcher's residency, the new
number is the honest one).
