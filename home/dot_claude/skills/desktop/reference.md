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
| `jev not granted` | `screen find` or `screen check` ran without `--jev` | pass `--jev` only if the brief says "JEV allowed"; else use `gui` or OCR |
| `overview open` | `screen find` or `check` without `--any` while niri's overview shows every workspace | retry once it is closed; the overview may be Saiful's, so if the agent did not open it, hand back |
| `not an agent window` | the focused window (keys) or the window under the point (clicks) is not one `screen launch` opened; for `screen find` and `check`, any window on the focused output's active workspace that is not | `screen launch` the app, or `--any` if the brief grants it |
| `windows share a title` | `gui click` or `type` in an app with two windows of one title, only one of them an agent window: AT-SPI cannot tell them apart | close the other window or rename yours; hand back if the other is Saiful's |
| `not editable` | `gui type` on a field without the editable state, or with read-only | find the right field in `gui tree`; never type into it another way |
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

JEV is TypeSafe's hosted decision model, reached through OpenRouter. Pass
`--jev` only when the brief says "JEV allowed"; there is no standing switch.
Each call sends a fresh screenshot of the focused output off the machine, to
OpenRouter and TypeSafe, billed to Saiful's OpenRouter credits.

- `screen find "<description>" --jev [--any]` takes a fresh shot, which
  becomes the last shot, so `screen click X Y` right after takes the point as
  printed. It prints `{"x":..,"y":..,"confidence":..,"on_screen":..}`: the
  point in shot pixels, the Box confidence and the probability the thing is
  on screen. Exit 4 prints `{"found":false,"on_screen":p}` when that
  probability is under 0.5.
- `screen check "<yes-or-no question>" --jev [--any]` prints
  `{"yes":true|false,"probability":p}`. `yes` is true when p is at least 0.5.
  Exit 0 either way.
- Exit 3 refuses: `{"refused":"jev not granted"}` without `--jev` (nothing is
  read, shot or sent); `locked` and `auth prompt` as for every input, even
  with `--any`; `overview open` while niri's overview shows every workspace;
  and `not an agent window` when any window on the focused output's active
  workspace, floating ones included, is not one `screen launch` opened, read
  both before and after the shot. `--any` lifts only those last two checks,
  and only when the brief grants `--any`.
- Exit 1 is any other failure: no key, network, HTTP error, a malformed
  answer, or no reply within 10 s (no retry). stderr ends "fall back to gui or
  OCR". Find the thing with `gui find` or `gui tree`, or OCR of
  `screen zoom`. Never retry JEV in a loop.
- Every send is a journal line holding the question and JEV's answer. The
  journal never holds the image.

## Journal

Each action and refusal is one line in
`$XDG_STATE_HOME/dots/agent-journal.ndjson`: time, tool, args, outcome, ms and
the window seen. Typed text is kept as its length and sha256, never the text.
