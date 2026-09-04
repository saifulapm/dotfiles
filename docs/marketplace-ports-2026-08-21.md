# Six widgets ported from the omarchy plugin marketplace — 2026-08-21

> **Five of these six are still here.** The night light (sunsetr) was removed
> fleet-wide on 2026-09-04: this MacBook's panel exposes no gamma LUT, so niri
> answers `failed` to every gamma-control request and the daemon warmed nothing
> while holding ~50% of a core. The rest of this document is left as written —
> it is the record of the port, not of the current tree. See the sunsetr note
> in `packages/manifest.toml` for the measurement.

User ask: survey `HANCORE-linux/omarchy-plugin-marketplace` (815 plugins), then
adopt six of them — sunsetr, passwordstore, removable-drives,
localhost/omaport, omassh and timezones — into this shell, working on all three
machines.

**Nothing was installed from the marketplace.** Every one of those plugins
targets `omarchy-shell` on Hyprland: `omarchy plugin add`,
`~/.config/omarchy/plugins/`, `hyprctl`, omarchy's theme JSON. This shell is
niri and our own Quickshell tree, so all six are re-implementations against our
own services and conventions, the way `MonitorModel.js` already re-implements
their monitor panel on niri's IPC. The upstream repos were read for behaviour
and for the decisions worth keeping; no code was copied.

---

## What landed

| Widget id | Bar | CLI | Upstream read |
|---|---|---|---|
| `nightlight` | `NightLight*.qml` | `bin/nightlight` | Varantha/omarchy-sunsetr |
| `pass` | `Pass*.qml` | `bin/pass-store` | hegjon/omarchy-passwordstore |
| `drives` | `Drives*.qml` | `bin/drives` | Wian47/omarchy-removable-drives |
| `ports` | `Ports*.qml` | `bin/ports` | sahzudin/omaport (see below) |
| `ssh` | `Ssh*.qml` | `bin/ssh-hosts` | sahzudin/omassh |
| `timezones` | `Timezones*.qml` | `bin/timezone-offsets` | sspaeti/omarchy-timezones-plugin |

Each is the same five-part shape the bar already uses — widget, service,
`Model.js`, panel, and a `bin/` script that does the gathering — so the QML
never has to know what an `ssh_config` or a `/sys/class/block` counter looks
like. Every `Model.js` has a `.test.js` beside it; `node <file>` is the runner,
as with `WarpModel.js`.

126 model tests, all passing.

## The no-polling rule, and where each one sits against it

This was the constraint that shaped the most decisions, so it is worth a table.

| Widget | Cadence | Why it is allowed |
|---|---|---|
| `nightlight` | none | `sunsetr status --json --follow` streams one JSON object per state change. A feature about the time of day, and it needed no clock at all. |
| `ssh` | none | `FileView` on `~/.ssh/config`; probes at startup and panel open. |
| `pass` | none | `FileView` on `~/.password-store/.git/index` — `pass` auto-commits every change, so the index moves on exactly the right events. |
| `drives` | udev follower, plus **1 Hz while the panel is open** | `udevadm monitor` covers arrival and removal. The 1 Hz half is a throughput sample and cannot be an event: a rate is two counter readings and a clock. It is the approved *panels refreshing while open* exception, gated in the service on `panelOpen` or a pending eject. |
| `ports` | **2 s while the panel is open** | A socket entering LISTEN has no event source short of a privileged netlink subscription. Same approved exception; nothing runs while the panel is shut, and the tooltip is honestly stale until you click. |
| `timezones` | Quickshell's `SystemClock` (Minutes) | The same object the clock widget ticks on, so a second widget showing times adds no second timer. Offsets are re-read only at a DST boundary the service schedules for itself — about four process launches a year. |

## Seven things that were wrong on the first try

Each of these was caught by testing rather than by reading, which is the reason
they are written down.

**1. `sunsetr -b` reports success for a daemon that is already failing.**
The first reading of "Starting sunsetr via niri compositor / Background process
started" was taken as a working start. It is the *launcher* saying it spawned a
child; the child then exited 1 with `Geo mode requires coordinates but none are
configured`. Geo mode does **not** fall back to the system timezone at runtime —
that lookup happens only when sunsetr *generates* a config. `run_after_44`
therefore borrows the generator: it runs sunsetr once against a scratch
directory purely to have it resolve this machine's timezone, reads the two
numbers back out, and writes them to `geo.toml`.

**2. `geo.toml` is the right home for coordinates, and upstream says so.**
`sunsetr help geo`: the file exists to be gitignored. This repo is public and a
home location is not something to commit. Per machine it also means the NUC and
the two laptops each aim themselves.

**3. `Host *` glob-expanded into the working directory.** `bin/ssh-hosts`
reported that `~/.dotfiles` contains hosts named `README.md` and `justfile`,
because splitting a `Host` line needs word splitting but must not do pathname
expansion. Fixed with `set -f`, turned back on for exactly the one word an
`Include` glob occupies.

**4. btrfs broke the root-disk guard.** `findmnt -no SOURCE /` answers
`/dev/nvme0n1p3[/root]` — the subvolume in brackets — which lsblk rejects and a
naive strip turns into the nonsense name `nvme0n1p3[/root]`. The exclusion then
matches nothing, and on a machine that BOOTS from a hotplug device the system
disk would have been offered for ejection. `--nofsroot` returns the bare device.

**5. zdump's end-of-time sentinel became a DST transition.** Zones with no DST
(UTC, Asia/Tokyo and this machine's own) reported their next transition 2.1 billion years
out, because zdump emits a far-future sentinel row for every zone and it parses
perfectly well. Bounded to the zdump range actually requested; those zones now
correctly report 0.

**6. `Intl is not defined` in Quickshell's QML engine.** Measured by running a
probe inside the real engine, not inferred from Qt's ICU linkage, which is
present and irrelevant. Without ECMA-402 there is no
`toLocaleString(…, {timeZone})`, so the world clock computes wall clocks from
UTC offsets instead — and that is why `bin/timezone-offsets` exists at all.

**7. Four glyphs were the wrong icons, and the font had all of them.**
Every codepoint I used was present in `SymbolsNerdFont-Regular.ttf`, so a cmap
check said fine — but presence is not identity. `U+F0394` is `md-new-box`, a
box with the word NEW in it, and it was the night-light hero. `U+F013F` was a
chevron, `U+F06F3` a desktop monitor, `U+F129E` a luggage tag. Found by
rendering the panel and looking at it. Fixed by rendering candidate grids
through the real font stack and picking by eye: night is `U+F0594`, auto
`U+F0450`, lan `U+F0318`, drives `U+F02CA`, folder-open `U+F0770`, stop-circle
`U+F0666`. **A codepoint in the cmap proves the glyph exists, not that it is
the icon you meant** — the only check that works is looking at it.

## A git forge is not a host (2026-08-21, after first use)

The SSH panel initially listed all six `Host` blocks in `~/.ssh/config`, and
three of them were `github.com`, `github.com-work` and `github.com-project` —
aliases that exist so git picks a particular key per GitHub account, all
resolving to `ssh.github.com:443` with different `IdentityFile`s. In a
launcher whose entire verb is "open a terminal there", half the list could
never do anything: GitHub answers SSH and then says "successfully
authenticated, but GitHub does not provide shell access".

I had noticed this while porting and shipped them anyway, on the reasoning
that the config is the source of truth and filtering by guesswork is worse.
That was the wrong call — being faithful to the config is not the same as
being useful, and the widget is a launcher, not a config viewer.

The fix filters rather than deletes: a host whose RESOLVED hostname is a known
forge is dropped from the default list, and comes straight back if you search
for it by name — `ssh -T github.com-work` is exactly how you check which
account a key belongs to. When one does appear it is marked `git remote — no
shell` in the warning colour. The hero says `3 hosts · 3 git remotes hidden`
rather than a bare `3 hosts`, because a widget quietly disagreeing with a
config you can read is how someone stops trusting it.

Matching is on the resolved hostname, not the alias, so `Host work` pointing at
ssh.github.com is caught and a machine you happened to name "github" is not.
The suffix test is dot-anchored: `notgithub.com` is not a forge.

## The ports panel is omaport, not omarchy-localhost (2026-08-21, after first use)

Worth stating plainly, because the table above originally credited both: only
**omaport** was ported. Its model is what got built — every TCP listener, a
scope column, search, and a kill guarded against PID reuse. From
**omarchy-localhost** exactly one idea was taken, the phone QR, and none of
what actually makes it that plugin: it discovers *dev servers specifically*,
names the framework behind each (Vite, Next, Astro, Rails), finds Docker and
Compose services, and offers open-in-editor and restart.

That turned out to be the wrong one of the two to build for this machine. On a
setup where caddy, dnsmasq, mailpit, three database proxies, two php-fpm
proxies, dufs and tailscale are all permanent and all deliberate, "every TCP
listener" is sixteen rows of plumbing above the one row you opened the panel
for. omarchy-localhost's framing — *the list is what you started* — was the
right one, and omaport's safety is what should be underneath it.

**The filter.** A listener is DECLARED if a systemd unit holds it or `ss`
cannot attribute it; everything else is something you started. Declared rows
are hidden from the default list and come back on search — including by name,
because `unit` is in the search haystack and nobody thinks of the database as
"3306". The hero says `1 listener · 16 services hidden` rather than a bare
count, and the empty case reads "Nothing running that you started."

The `unit` column is filled from two places, and the second needs care:
`systemctl list-sockets` on both managers covers socket activation, and the
process's own cgroup covers a plain service like `dufs` or `hub` that holds
its own socket. A `pnpm dev` started in a terminal ALSO sits in a `.service`
cgroup — the terminal's — so the cgroup unit only counts when the listening
process is that unit's `MainPID`. That comparison needs no denylist of
terminal names, which is why it is the check used.

**No exposure exception, deliberately.** The first version forced any
wide-bound declared service through the filter so the security warning stayed
visible. That put sshd, llmnr and the clipboard socket on screen permanently
in the warning colour — the exact noise the filter exists to remove, and all
three are in the manifest on purpose. A declared wide bind is deliberate; what
the warning is FOR is an *undeclared* process on 0.0.0.0, and that is shown
because it is undeclared. The bar icon and its tooltip still count every
listener, so nothing is silently dropped.

**A dedup bug found on the way.** `sort -u -k1,1n` uniqued on the port number
alone, so a port listening on several addresses kept one arbitrary row: 8787
has three (tailnet v4, tailnet v6, loopback) and the survivor was an
unattributed tailnet row, hiding the loopback one `ss` could actually name a
process for. Now unique on port AND bind, with the panel grouping them back to
one row per port — keeping the widest scope, because that is the honest answer
to "who can reach this", and preferring the member that can be named.

**Two things measured while checking that a real dev server actually appears.**

`ss`'s `comm` is the kernel's 16-byte task name, and it is wrong for exactly
the processes this panel exists to show: node renames its main thread, so
every Vite, Next, Astro and Shopify CLI server reported itself as
`MainThread`. `bin/ports` now reads argv instead — and goes one further, since
a dev server is usually a runtime running a tool (`node …/node_modules/.bin/vite`,
argv[0] = "node", the interesting word is argv[1]). A known runtime defers to
its first non-flag argument, so that row reads `vite`; `node -e '…'` correctly
stays `node`, because `-e` is a flag.

A transient systemd unit declares nothing. `bin/app-run` launches everything
as its own `app-<cmd>-<random>.service` and the process IS that unit's
MainPID, so a dev server started from the menu or the launcher was being filed
as infrastructure and hidden — the precise opposite of what a launcher-started
process should be. Checked with systemd's `Transient` property rather than by
matching the generated unit name, which would have been a guess.

Verified end to end: a server started in tmux under `/tmp/shopfront` appears
within the panel's 2 s refresh as `4321 · shopfront · vite · this machine
only`, and one started via `app-run` appears beside it.

Still not ported from omarchy-localhost, and still worth having if it is ever
wanted: framework detection and a restart action.

## A TextInput eats Alt chords (2026-08-21, reported)

The pass panel's `Alt+U`, `Alt+O` and `Alt+E` did nothing. The cause is a Qt
behaviour worth writing down, because the obvious diagnosis is wrong.

Those chords were handled at the card's key catcher, where every other panel's
keys live, on the reasoning that a focused TextInput swallows plain keys but
lets modified ones through. It does that for **Ctrl** and not for **Alt**:
Qt's line control inserts any key event that carries text, and on this layout
`Alt+U` carries the text "u". So the field inserted a literal `u` — the search
box quietly filling with letters was the visible symptom — and, critically,
ACCEPTED the event. An accepted event does not propagate, so no amount of
fixing key bubbling could ever have reached the panel.

The fix is a `chord` signal on `PanelTextField`, emitted from a
`Keys.onPressed` that runs ahead of the input's own handling (Keys.priority
defaults to BeforeItem) for any key with Alt or Ctrl held. The panel connects
it to the same function its key catcher calls, so a chord works whether or not
the field happens to hold focus. It is opt-in: the four other panels using
this component connect nothing and are unaffected.

**The same bug from the other direction, in the ports panel.** Its footer
advertised `c copies · q shows a QR · d opens the folder · x stops it`, and
every one of those typed a letter into the search box instead. A panel whose
text field holds focus for its whole life cannot have single-letter shortcuts
at all. They are now `Alt+C` / `Alt+Q` / `Alt+D` / `Alt+X`, through the same
signal, and the footer says so.

**And a second failure found while verifying the first.** Every pass action
closes the panel — right for the success case, since you want to get on with
pasting — which left a FAILURE with nowhere to appear. `Alt+U` on an entry
with no `login:` line ran the correct verb, failed for the correct reason, and
produced complete silence. Failures now raise a notification carrying
bin/pass-store's own message, which names the missing FIELD and never the
contents of any field.

## Security notes

**`bin/pass-store` holds the rules, so the QML does not have to.** No secret
ever touches `argv` (`/proc/<pid>/cmdline` is world-readable): clipboard actions
go through `pass -c`, which pipes internally and clears after 45 s, and typing
goes through `wtype -`, which reads stdin. The shell process only ever holds
entry *names* — which were never secret, because gpg encrypts contents and not
filenames. That is the same fact that makes the store a separate private repo.

`pass otp` is gated on the extension actually being installed. Without
pass-otp, `pass otp foo` does not fail — pass falls through to its own `show`
and reports that an entry named "otp" is not in the store, which is a confusing
thing to surface for a missing package.

**`bin/ports kill` requires the process start time back.** PIDs are recycled;
between a panel drawing a row and a click landing on it, the process can exit
and its number be handed to something else. The pair (pid, starttime) is unique
for the life of the machine, so requiring it makes the recycled-PID kill
impossible rather than unlikely. The check is re-done against `/proc` at the
moment of the signal, not in the QML. Root-owned sockets are listed — they are
part of an honest answer to "what is listening" — but never killable.

**`bin/ports` classifies tailnet binds separately from LAN.** A v6 tailnet
address was initially reported as "local network", which is the one
misclassification here with a consequence: it reads as "reachable by anyone on
the coffee-shop wifi" when it is not.

## Cost

Cold start, measured in a nested compositor, fresh compositor per run,
alternating between a pristine `HEAD` checkout and this tree:

```
baseline  185  181  176     median 181 ms
six new   198  195  194     median 195 ms
```

**+14 ms**, about 8%. Idle RSS and idle CPU are not measured here — `just bench`
is the authoritative harness for all four numbers and it restarts the session
shell, so it wants an unlocked session.

## Verified on screen

After `chezmoi apply` (2026-08-21, NUC, DP-3 at 3840x2160): all six widgets
render on the live bar, and five of the six panels were opened and inspected.

- **Night light** — moon hero, `Lamplight · 3300K · 90% gamma`, `NEUTRAL AT
  05:28`, Auto ticked.
- **SSH** — the three real machines, recency-ordered. It first showed all six
  `Host` blocks, three of which are github transports; see below.
- **Passwords** — 2 entries as leaf-over-folder, and the footer reads
  `Alt+O code`, which is the pass-otp capability gate proving itself: that hint
  was absent before the apply installed the extension.
- **Ports** — after the filter below: one row for the throwaway server that
  was actually running, `1 listener · 16 services hidden`, and searching
  `mysql` brings `3306 · mysql84-proxy` straight back.
- **World clock** — Dhaka 20:00 / London 15:00 (−5h) / New York 10:00 (−10h),
  every row on the same columns, business hours shaded, midnight marked. It
  sits in the bar's CENTER section, beside the clock (user call 2026-08-21) —
  the only one of the six that is not on the right. It is a clock, it belongs
  next to the clock, and being centred also stops the widest panel on the bar
  opening three-quarters of the way across a 4K screen.
- **Drives** — `bar open drives` answers `no widget with a panel: drives`,
  which is correct: nothing is plugged into this machine and the widget only
  exists while a drive does.

## Not done

- **`just bench`** has not been run: it stops `qshell.service` and measures for
  60 s. The +14 ms above is the nested-compositor substitute; idle RSS and idle
  CPU remain unmeasured.
- **`drives` has never seen a removable drive.** The NUC has one NVMe disk and
  nothing hotplug, so `bin/drives` correctly prints nothing there. The row
  shapes and the human sizes were verified by running the same lsblk+jq
  pipeline with the removable filter lifted; the udev path and the `udisksctl`
  actions are unexercised until something is plugged in.
- **`pass` copy/type/otp were not run.** They would trigger a gpg pinentry and
  touch a real secret on a locked session. `list`, `caps`, the recency
  ordering, the traversal refusal and the otp gate were all tested.
- **pass-otp is not installed yet.** It is in `packages/manifest.toml` and
  lands on the next `chezmoi apply`; until then `pass-store caps` reports only
  `type` and the panel hides the Alt+O hint, which is the intended behaviour.

## Rejected while porting

- **omassh's periodic re-read of `Include`d files.** Upstream polls to catch
  edits a single watcher cannot see. That is exactly the cadence the no-polling
  rule refuses, and panel-open re-reads everything anyway.
- **Reusing `NetworkQrPanel` for the ports QR.** It is built around an SSID and
  a passphrase; generalizing a working surface to carry a URL is a bigger
  change than painting sixty rectangles in the ports panel. `bin/network-qr`
  did grow a `--text` mode, so there is one qrencode wrapper rather than two.
- **Fuzzy-match scoring in `PassModel`.** A password store holds tens of
  entries. Exact/prefix/substring/subsequence bands already order them; gap and
  cluster scoring on top would reorder the tail for no perceptible gain.

## Capturing a 2FA QR from the passwords panel (2026-08-21, evening)

Adding a TOTP secret used to mean leaving the desktop: `screenshot-qr`, then
`wl-paste | pass otp insert <path>` in a terminal. It is now one gesture from
the panel — a QR chip in the hero, or `Alt+N`.

**The shape.** The chip (or the chord) closes the panel, runs `screenshot-qr`,
and reopens the panel showing what the code *says it is*: issuer, account,
type, digit count. Then the only question left — which entry does it belong
to? — is asked as the ordinary searchable list, with a `Create a new entry`
row at its foot carrying an editable `otp/<Issuer>/<account>` path. Enter
files it, Escape throws the code away and gives the ordinary list back.

**THE SECRET NEVER ENTERS THE SHELL PROCESS**, and that is why there are two
new `bin/pass-store` verbs rather than a `wl-paste` in QML:

```
pass-store otp-scan                       issuer<TAB>account<TAB>type<TAB>digits
pass-store otp-save insert|append <entry> the URI, on stdin, into `pass otp`
```

Both read the clipboard themselves. `screenshot-qr` puts the payload there with
`wl-copy --sensitive`, which `bin/clipboard-capture` and
`bin/clipboard-sync-push` both honour, so a captured URI reaches neither the
clipboard history nor the other two machines. The shell only ever holds four
identity fields and an entry NAME — the same class of thing it already held.
`PassModel.parseCapture` refuses anything that is not those four fields, so a
URI cannot be rendered as if it were an issuer even by accident.

The capability is one gate, `qr`, and it covers the whole chain —
screenshot-qr, zbarimg, wl-paste AND pass-otp. A capture that ends in "pass-otp
is not installed" has wasted a region selection to say so.

### Closing the panel first is the whole sequencing problem

The panel holds `WlrKeyboardFocus.Exclusive`; wayfreeze and slurp need the
pointer and the keyboard. With the panel up there is no region selection at
all. But `close()` is not enough on its own either: it starts a fade, and the
surface stays mapped until the fade ends, while **wayfreeze screenshots the
screen the moment it starts** — so a capture launched on the keypress would
freeze a picture of the panel sitting over the QR being captured. The launch
waits for the window's `visible` to go false, which is an event and not a
guessed delay. The panel that asked is also the only one that reopens
(`captureOwner`): there is one service for the whole bar but a panel per
screen, and every one of them hears `captureReady`.

### Four things that were wrong, or wrong in the tools

**1. A cancelled selection and a captured code both exited 0.** `screenshot-qr`
exits 0 when slurp is cancelled, which is right for a person pressing Escape
and useless to a caller that has to decide whether to reopen: the clipboard
still holds whatever the LAST capture put there, so the panel would have
reopened showing a code captured ten minutes ago. It grew an opt-in
`--exit-codes` flag — cancel becomes 2 — and the menu entry keeps the old
behaviour untouched.

**2. `pass otp insert -f` is not what protects an entry, and `-f` is not why.**
pass's `yesno` opens with `[[ -t 0 ]] || return 0` — with a pipe on stdin it
answers ITSELF, yes. So `-f` only matters for a terminal, and an insert over an
existing path would have replaced that entry, password and all, in silence.
`otp-save insert` refuses an existing path outright; `-f` stays purely so that
`pass` never asks a question no terminal can answer. The panel says the same
thing while the field still has focus, but the script's refusal is the one that
actually protects the file.

**3. `pass otp append` REPLACES an existing code rather than appending, and
does not consult `-f` for that prompt either** (read from
`/usr/lib/password-store/extensions/otp.bash`, confirmed against the throwaway
store). A replaced TOTP seed is gone — re-enrolment is the only way back — so
`otp-save append` refuses an entry that already carries an `otpauth://` line.
That check is the one place these verbs decrypt anything, through `pass show`
like every other read here, and it is `awk` rather than `grep -q`: grep exits
on the first match, `pass` takes SIGPIPE for it, and under `set -o pipefail`
the pipeline would report failure for the case that FOUND something —
inverting the guard.

**4. The chip's tooltip drew behind the search field** (spotted by the user
while this was being built). `PanelHint` warns about exactly this in its own
header: a hint hangs off the bottom of its anchor, and the next row of the
panel is a later sibling that paints over everything the hero owns, whatever z
the hint sets. `above: true` is the documented escape, but the hero is the
FIRST row and there is nothing above it but the card's edge. Fixed by lifting
`PanelHero` itself to `z: 1` — one line, and every hero hint in the tree had
the same defect. Verified by forcing the hint visible and looking at it before
and after; nothing else overlaps the hero, so there is nothing for it to get in
front of.

### The first thing that went wrong in real use (2026-08-21, same evening)

"I click the QR icon, it's disabled." And it was — but the interesting part is
why, because two separate mistakes had to line up.

The chip was drawn `enabled: !pass.capturing`, so a capture already in flight
greyed it out. In the session that produced the report, a `slurp` had been
waiting for a region for **four minutes**: the click had started a capture, the
selection was never completed, and from then on the chip was dim, `Alt+N` did
nothing, and neither said a word about why. A control that disables itself and
offers no explanation is indistinguishable from a broken one.

Worse, that state could not be got out of from inside the shell. `bin/screenshot-qr`
ran the picker as `region="$(slurp)"`, and **bash defers a trap until the
foreground command finishes** — a command substitution is a foreground command,
so a TERM aimed at the script did not reach slurp. Killing the capture left the
picker holding the screen. The selection now runs in the background with
`wait`, which IS interruptible, and one trap kills slurp and wayfreeze
together. That also cleans up the case where the shell itself restarts: the
`--pdeathsig TERM` that kills the script now takes the picker with it instead
of orphaning it.

So: the chip is never disabled. While a capture is waiting, its tooltip says
"start the region selection over", pressing it (or `Alt+N`) abandons the
waiting selection and begins a fresh one — a Process cannot be restarted before
it has actually gone, so the abandoned one's exit launches its replacement and
that exit is deliberately silent — and opening the panel shows a note saying a
selection is waiting on the screen. Nothing about the feature is reachable only
by knowing it is there.

**One thing still unexplained**: in that session wayfreeze was no longer
running while slurp still was, so the screen was not frozen and the capture had
no visible sign at all — "nothing visible happened" is exactly how it was
described. Three candidates were checked and none of them is it. wayfreeze is
on the shell service's own PATH. It ignores the keyboard unless
`--enable-keyboard` is passed, so an Escape aimed at the picker cannot have
closed it. And it is not SIGPIPE from the closed stdout a Process with no
collector can hand a child: launched that way in a nested compositor it starts
and stays up. The capture worked on the live session once the fixes above were
in, so this is left as a thing to watch rather than a chase — and it matters
much less now, because a capture with no visible freeze is one the panel
announces and can call off.

### Smaller decisions

- **Spaces in a suggested path become dashes.** The entries imported in bulk
  from Google Authenticator arrived with multi-word issuers hyphenated or
  joined, never spaced, so the suggestion matches that. A slash in an issuer
  becomes a dash too — "Acme/Prod" would otherwise silently create a folder.
  The field is editable, so this follows the existing convention rather than
  inventing a rule — and it is the
  same rule `bin/otp-import`'s `pass_path` already applies, down to the
  `otp/unnamed` fallback, so a code imported in bulk out of Google
  Authenticator and one captured off the screen land at the same path.
- **`Create a new entry` sits at the FOOT of the destination list.** The common
  case is filing a code against an entry that already exists; a synthetic row
  at the top would cost that case an arrow key every time.
- **The capture outlives the panel.** It is cleared when it lands in the store,
  or when Escape throws it away — so a save that failed, or a panel closed by
  accident, resumes where it left off instead of losing the code.
- **`Alt+N` means "new" in both places it appears** — a new code in the ordinary
  list, a new entry for the one just captured. It is swallowed in the path
  field as well: an unclaimed Alt chord types its letter, and a stray `n` in a
  store path is a bad way to find that out.
- **The clipboard is not cleared after a successful save.** The URI is
  `--sensitive`, so nothing records it, and clearing would take the user's
  clipboard with it on a flow they may want to repeat. One line
  (`wl-copy --clear`) if that turns out to be the wrong call.

### Verified, and how

Against a throwaway store in the job's tmp dir, encrypted to a throwaway
passphraseless key in a throwaway `GNUPGHOME` — so append could be tested
end to end without a single real entry being decrypted. `~/.password-store`
was read for filenames only and its git tree is unchanged.

- `otp-scan` on an `Issuer:account%40example.com` label, one with a percent-
  encoded space, a label-only `hotp/` URI with no issuer parameter, a
  non-otpauth clipboard and a `secret=`-less URI.
- `otp-save insert` writes the URI verbatim; over an existing path it refuses.
  `otp-save append` keeps the password and the `login:` line and adds the code;
  onto an entry that already has one it refuses; onto a missing entry, `../`
  and `/etc/passwd` it refuses.
- In a nested compositor, driven by `wtype` with `screenshot-qr` stubbed: the
  chip renders and is gated (with `screenshot-qr` off PATH the chip and the
  `Alt+N` hint both disappear and the chord does nothing); `Alt+N` fires with
  the search field focused and full of text; the panel closes, captures and
  reopens on the identity; both destinations write correctly; Escape leaves
  captured mode; a cancel (exit 2) and a failure (exit 1) both leave the panel
  shut and silent, the second because screenshot-qr has already said so itself.
- A refused append raised the notification, which is how a failure reaches
  someone after the panel has closed — the same path Alt+U's failures use.
- 176 model assertions pass; the shell loads in the nested compositor with no
  new warnings, `bench:first-bar` unchanged at ~195 ms.

**Not verified: the region selection itself.** slurp and wayfreeze need a
pointer, and a nested compositor has no way to drive one that does not also
move the real cursor, so `screenshot-qr` was stubbed at its exit code for the
panel tests and exercised for real only from a terminal. The one thing left
untested is therefore the part that was already working before this feature
existed.

**A trap for the next person testing in a nested compositor.** The recipe in
this file (`WAYLAND_DISPLAY=wayland-N qs -p …`) silently does the wrong thing
from a non-interactive job: `QT_QPA_PLATFORM` is `wayland;xcb` here, `DISPLAY`
is still the outer session's, and Qt falls through to xcb and draws the bar on
the REAL screen — layer-shell attached properties failing is the tell. Use
`env -u DISPLAY WAYLAND_DISPLAY=wayland-N QT_QPA_PLATFORM=wayland`.
