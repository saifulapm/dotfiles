---
name: reminders
description: "Saiful's reminders through the `reminder` CLI: set one that rings on his desktop at a time, list what waits, and cancel one after he says yes. Use when he says 'remind me in 20 minutes to…', 'remind me at 17:30 to…', 'what reminders do I have', 'cancel my tea reminder'."
---

# reminders: set, list and cancel Saiful's reminders

`reminder` is a CLI on PATH. It works on the same reminders as the
launcher's `r ` mode. Each machine that is awake at a reminder's due time
rings it, and dots sync carries reminders between his machines.

When `command -v reminder` finds nothing, run `~/Codes/dotfiles/bin/reminder`.
When that is missing too, tell Saiful that this machine cannot set
reminders. Do not write the store file yourself.

## Set one

    reminder add <when> <text>

`<when>` takes two forms:

- `20m`, `1h` or `1h30m`: that long from now.
- `17:30`: the next 17:30 on this machine's clock, today or tomorrow.

Nothing else: no dates, no seconds, no words like "tomorrow". Change his
words into one form: "in 5 minutes" is `5m`, "in an hour and a half" is
`1h30m`, "at half five" in the evening is `17:30`.

`17:30` rings at the next 17:30, so it rings today while 17:30 is still
ahead. When he names tomorrow and that time is still ahead today, or he
names a later day, count the hours from now instead (`date` gives the
clock): at 10:00, "tomorrow at 17:30" is `31h30m`. The CLI prints the
clock and how far off it is; check it says the day he meant.

Put the text in single quotes, since bash would change `$50` or drop all
after a `#`; write a `'` inside it as `'\''`. Keep his words, short:
"remind me in 5 minutes to stretch" is `reminder add 5m 'stretch'`.

It prints what it set, such as `tea · in 20m · 10:20`. Give Saiful that
line. When it refuses (`Cannot set 0m: it is not in the future`, `At most
50 reminders can wait`), it exits 1 with the reason: tell him the reason,
and do not try another time he did not ask for.

## List them

    reminder list
    reminder list --json

`reminder list` prints one line per waiting reminder, soonest first: its
id, when it rings, and its text. It prints `no reminders` when none wait.
`reminder list --json` prints an array of `{id, text, due, created}`, with
`due` in milliseconds since the epoch.

## Cancel one: ask first

Never run `reminder rm` until Saiful says yes to that reminder. This holds
even when he asked you to cancel it, because the words may match more than
one.

1. Run `reminder list` and find the reminder he means.
2. Ask him, naming its text and when it rings: "Cancel 'stretch' at 10:25?"
   Then stop and wait for his answer.
3. After his yes, run `reminder rm <id>`. It prints `removed: stretch`.

`no pending reminder <id>` means it already rang or was cancelled. Tell
him so; there is nothing to undo.

There is no edit. To move a reminder, ask, cancel it, then add it again.
