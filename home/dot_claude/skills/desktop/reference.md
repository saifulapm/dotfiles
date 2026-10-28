# desktop reference

Detail behind SKILL.md section 4. Scripts are in `~/.claude/skills/desktop/scripts/`.

## Refusals

Every input path (`screen move|click|drag|scroll|type|key`, every `mouse`
call, `gui click|type`) refuses with exit 3 and prints
`{"refused":"<reason>"}`, with the window seen when there is one.

| Reason | Meaning | What to do |
|---|---|---|
| `locked` | `dots-call lock state` reads locked | unlock only if the brief says to; else hand back |
| `auth prompt` | a polkit or pinentry password prompt is open (`dots-call polkit state` or `dots-call pinentry state` reads anything but `"open": false`) | refused even with `--any`; stop, hand the task back to Saiful, never type a password |
| `not an agent window` | the focused window (keys) or the window under the point (clicks) is not one `screen launch` opened | `screen launch` the app, or `--any` if the brief grants it |
| `no window` | no window under the point, or none focused | re-read `niri msg -j windows`, re-shoot |
| `no answer` | `mouse` got no answer from niri's pick-window in 500 ms | retry once, then hand back |
| `busy` | another gesture runs on this niri | wait, retry |

A lock or prompt that arrives during a click's hit-test refuses it too.

## Agent windows

A window is an agent window when it opens within 5 s after `screen launch`,
or within 5 s after an agent action in an agent window (a Save As dialog).
`--any` lifts only this check: keys then go to any focused window, clicks to
any window. It never lifts the lock or an auth prompt. Pass it only when the
brief grants it.

## Typing

`screen type TEXT` sends one key per call, re-reading the lock and both
prompts before every key, at least 15 ms apart. Newlines are dropped: use
`screen key Return`. `screen key COMBO [REPEAT]` takes REPEAT 1-50 as a
positional argument and is gated per key too. The first key into a window not
typed into before is preceded by a Shift press automatically, so do not prime
by hand.

## Waiting and readiness

- `screen wait COND [--timeout S]`: `window-open --app ID`, `window-closed
  --id N`, `focus --id N`, `title --id N --matches RE`, `workspace N`,
  `overview open|closed`. 10 s default, 60 at most; exit 1 with the last state.
- `screen doctor`: JSON with `blockers` and one `next` step; exit 1 while
  anything blocks.
- `--then shot|windows|tree` on any acting command; `screen look KIND` alone.

## JEV

`--jev` is a grant for JEV commands (`screen find`, `screen check`), which
are not in this build. Pass it only when the brief says "JEV allowed".

## Journal

Each action and refusal is one line in
`$XDG_STATE_HOME/dots/agent-journal.ndjson`: time, tool, args, outcome, ms and
the window seen. Typed text is kept as its length and sha256, never the text.
