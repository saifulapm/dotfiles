---
name: jev
description: "Judge what is on screen without reading it into context. Use when a page snapshot, a widget tree or a terminal pane would otherwise be dumped into the conversation just to answer one question: which element is the checkout button, did the order go through, is the right row selected, is this safe to press. Triggers: 'which element', 'find the button', 'is the page showing', 'did it work', 'check the page', 'verify on screen', 'which widget', 'is the selection right', plus any before-you-click safety check."
---

# jev — ask a typed question instead of reading the screen

`jev` turns one surface into text, asks Typesafe's Jev (through `pxy ask`),
and prints the answer alone. A real page snapshot runs to a megabyte; judging
it this way costs about **$0.0005** and puts nothing in context. Measured on
this machine, 2026-09-22.

`jev` and `jev-browse` are on PATH (symlinked from `~/.dotfiles/bin`), so call
them by name from any directory — unlike the desktop skill's `gui` and
`mouse`, which need their full path.

This is **opt-in**. The desktop and playwright-cli channels are unchanged and
remain the default; reach for `jev` when the cheaper channels can't answer and
the expensive one is "read the whole thing".

## Where it sits

```
command output / jq / grep   →   jev   →   read the snapshot   →   OCR   →   screenshot
    free, deterministic         ~$0        expensive context
```

**Never put `jev` ahead of something deterministic.** If `jq`, `grep` or an
exit code already answers, that is the answer. Jev is for the judgement calls
in between — and for the cases where the only alternative is reading 25 KB of
YAML to find one ref.

## The subcommands

```sh
jev pick  "<intent>" [-s SESSION] [--grep RE]   # a ref on the live playwright page
jev check "<claim>"  [-s SESSION]               # judge the live page
jev gui   <app> "<intent>" [--grep RE]          # a widget name, over the a11y bus
jev pane  <session> "<claim>"                   # judge a tmux pane, selection marked
jev guard "<action>" --asked "<request>" \
          (--pane S | --page [-s S] | --context F)   # before you press
```

`jev` with no arguments prints its full usage.

```sh
ref=$(jev pick "the element that opens the site search" -s mysession --grep search)
playwright-cli -s=mysession fill "$ref" "Ada Lovelace" --submit

jev check "the order was placed successfully" -s mysession && echo confirmed
jev gui gtk3-widget-factory "the button that closes the window"   # → Close
jev pane agent-build "the highlighted row is the dekho-sync unit"
```

`pick` prints a ref, `gui` prints a widget name that `gui click` takes (its
full line, with coordinates and state flags, goes to stderr), `check` and
`pane` print a probability.

## Exit codes — 3 is not "no"

| code | meaning | what to do |
|---|---|---|
| 0 | answered | use it |
| 1 | error | the chain or the surface is broken; read the stderr |
| 2 | `check`/`pane`: the claim is false | act on "no" |
| **3** | **abstained** | **look yourself** — do not read it as "no" |

Abstention means the winner was too weak, too close to the runner-up, or the
target is not on this screen at all. It is the guard working, not a failure.
Both failure codes are falsy, so `jev check "…" && act` also declines to act
when the chain is down.

## Thresholds

`--min` is the probability below which it declines; `--margin` (pick/gui) is
the lead over the runner-up it wants. Defaults: **0.55 / 0.15** for picking a
target, **0.70** for believing a claim — an assertion at 0.51 is not an
assertion. Tune on false negatives before false positives.

A real abstention, worth knowing by shape: asked for "the control that
switches to the third page" across gtk3-widget-factory's 95 named widgets,
Jev answered 0.40 against a runner-up of 0.39, confidence 0.39. The app has
two such controls. All three guards caught it and it abstained. That is the
jarbon 0.49-vs-0.47 case — the one that renders as a confident banner if
nobody checks the margin.

## `jev guard` — the check before a destructive keystroke

Asks three questions in one call and answers with an exit code: **0 proceed,
3 stop and ask the user**. `--asked` is required, and it is the point — you
have to state the mandate, and Jev judges whether the action is inside it.

```sh
jev guard "press 'r' to restart the dekho-sync unit" \
  --asked "restart the dekho-sync service" --pane agent-build || ask-first
```

An action it reads as consequential (≥0.35 — a deliberately low bar) must
also be clearly authorised (≥0.85) *and* certainly targeted (≥0.85). An
ordinary action only has to be aimed at the right thing (≥0.55).

Both incidents recorded in the desktop skill, replayed against it:

| case | verdict | numbers |
|---|---|---|
| restart, but the highlight is stuck on another row | **STOP** | target 0.05 |
| restart, highlight on the intended row | proceed | target 0.94, auth 0.90 |
| Right+Return moving DNS to Cloudflare, having been asked only to *look* | **STOP** | conseq 0.62, auth 0.05 |
| delete the exact file the user named | proceed | conseq 0.83, target 0.97, auth 0.95 |
| delete, but aimed at the neighbouring file | **STOP** | target 0.04 |

It does not gate benign actions on authorisation — clicking around to find
something is ordinary work, and a guard that stopped for it would be turned
off within a day. Its job is the irreversible ones.

## `jev-browse` — a whole goal, not one question

`jev-browse` runs the loop: snapshot → one Jev call → act → repeat, for
the navigation that otherwise costs ten turns each carrying a snapshot.

```sh
jev-browse "<goal>" <url> [--fill LABEL=TEXT]... [-s SESSION]
                      [--max-steps N] [--max-seconds N]
```

One request per step asks *which action*, *is the goal met* and *is this
stuck* together, so a step is one round trip, not three. Bounded at 20 steps
and 90 s, and it stops when the same action twice changes nothing.

```sh
jev-browse "find the Blue widget using the search box" http://site.test \
       --fill "Search parts=Blue widget"
# 1. type into the searchbox 'Search parts'
# 2. press Enter to submit the field just filled
# 3. click the link 'Blue widget'
# done: goal met
```

**It navigates and reads; it does not transact.** A target whose label looks
like a commit point — pay, order, checkout, delete, submit, send — ends the
run and hands back, and Enter is refused outright on any page that carries
one. Verified against a fixture: asked to "buy the blue widget" it chose
*Buy now* and then declined to click it; asked to apply a coupon on a page
with *Place order*, it filled the field and refused the Enter.

That is a keyword gate, not a judgement — Jev is asked which action to take,
and cannot be asked whether an action is reversible before it has chosen one.
For a single deliberate destructive action, use `jev guard`, which is the
semantic check, and drive it yourself.

Jev cannot write, so typed text comes from `--fill` (the label is matched as
a substring). A field with no matching `--fill` stops the run and names the
flag it wanted. Exit **0** goal met, **3** stopped, **1** error.

## What it cannot do

- **It cannot see.** No image input, ever. These subcommands feed it text;
  a question about colour, spacing or anything absent from the a11y tree
  needs a screenshot and your own eyes.
- **It cannot count or do arithmetic.** Totals, sums and "how many" belong in
  code. Ask it what kind of thing it is looking at, not how many.
- **It cannot write.** Anything that produces text is still your job.
- **255 options.** `pick` spends one on `none_of_these`, so 254 candidates.
  Over that it refuses rather than keeping the first 254 — a target Jev was
  never shown cannot be reported missing, so a silent trim comes back
  confident and wrong. Narrow with `--grep`, or use `playwright-cli find`.
- **~32k tokens**, not the 64k Typesafe documents — that is the ceiling of
  the gateway pxy reaches. State above `MAX_STATE` is trimmed head-first and
  says so on stderr; the tail is then not being judged.
- **~450 ms per call** from here, so a loop runs at about two decisions a
  second. Ask every question in one call, never five calls of one question —
  extra questions are nearly free, extra calls are not.

## How it reads a pane

`tmux capture-pane -p` strips colour, so the selection is invisible and no
question about it can be answered. `jev pane` captures with `-e` and rewrites
the highlighted run as `» selected «` before asking — deterministic
preprocessing, so the model reads a marker rather than inferring one from
escape codes. This is the channel for "is the highlight on the row I think it
is" before any destructive keystroke.

A row counts as highlighted if it is reverse-video **or** has a background
colour, because which one a TUI uses is not something a caller can be asked
to know: fzf uses bold plus `48;5;236` and no reverse video at all. Against a
live fzf over systemd units it reads the selected row at 0.97, the adjacent
row at 0.01, and follows the selection as it moves.

## Requires

`pxy` on PATH with a live `[media] systemone` chain (`pxy ask --help`), and
for `jev gui`, the desktop skill's `scripts/gui`.
