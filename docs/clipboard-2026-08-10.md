# Tailnet clipboard — Universal Clipboard, minus Apple (2026-08-10)

Copy on one device, paste on another, across the iPhone and every machine on
the tailnet. Between Linux machines it is fully automatic; the iPhone is one
tap each way — that floor is Apple's, not ours: iOS forbids apps from reading
the clipboard in the background, which is why nothing (KDE Connect,
Pushbullet, anything) replicates Universal Clipboard and only Apple can ship
it inside the OS.

## How it fits together

- **`bin/clipboard-serve`** — a tiny HTTP handler, socket-activated
  per-connection on `127.0.0.1:9411` (`clipboard-serve.socket` +
  `clipboard-serve@.service`). `GET /` answers the clipboard's bytes,
  `POST /` sets them. Nothing runs while nobody asks.
- **`tailscale serve --bg --http=80 9411`** (wired by
  `run_after_05-tailscale.sh`) publishes that loopback port to the tailnet as
  `http://<machine>.taila27604.ts.net/`. tailscaled terminates the connection
  inside the WireGuard tunnel: no port on any real interface, nothing for
  firewalld, unreachable from LAN/internet, encrypted in transit. Plain HTTP
  because this tailnet has no cert domains enabled — and the tunnel already
  encrypts.
- **`clipboard-sync.service`** — `wl-paste --watch` on text selections,
  session-scoped like qshell. Every local copy is POSTed to every peer
  `bin/clipboard-sync-push` discovers from `tailscale status`: all *online
  Linux* nodes on the tailnet. Nothing is configured per machine — all the
  boxes run this same setup (and the same local hostname; tailscale dedupes
  them to `fedora`, `fedora-1`, …), so the node list is the peer list and
  self is excluded for free.
- **Loop safety**: peer-to-peer posts carry `X-Clipboard-Relay: 1` — the
  receiver records the bytes so its own watcher won't re-broadcast them
  (that suppression is what prevents ping-pong when two copies land faster
  than their relays cross). A post *without* the header (the iPhone) reached
  one machine only, so that machine's watcher deliberately *does* fan it out
  to the rest. The terminator underneath both: a receiver never re-copies
  bytes its clipboard already holds.
- **What never syncs**: empty selections, bodies over 1 MiB, and
  password-manager selections (`CLIPBOARD_STATE=sensitive` /
  `x-kde-passwordManagerHint`, same guards as `clipboard-capture`). Note the
  flip side: `GET /` serves whatever is on the clipboard right now —
  including a `pass -c` password during its 45 s window. Only this tailnet's
  devices can ask, but it is worth knowing.

## iPhone — two Shortcuts, one tap each

Tailscale's VPN toggle must be on (the app can stay backgrounded).

**"Send Clipboard"** (iPhone → machines):

1. Shortcuts app → **+** → name it "Send Clipboard".
2. Add **Get Contents of URL**: `http://fedora.taila27604.ts.net/` → *Show
   More* → Method **POST** → Request Body **File** → pick the **Clipboard**
   variable.
3. Optional: **Show Notification** ("Sent ✓").
4. To also send selected text without copying first: in the shortcut's info
   sheet enable **Show in Share Sheet** (input: Text), set the body to
   **Shortcut Input**, and "If there's no input → **Get Clipboard**".

Rich text is handled on the receiving side: iOS apps often put *only* RTF
on the clipboard (the Claude app does), and the Shortcut then uploads
`{\rtf1\ansi…` word soup — Shortcuts' own Text coercion was tried and did
NOT reliably convert it. `clipboard-serve` detects an RTF body and converts
it with `pandoc -f rtf -t plain --wrap=none` (verified against a real
Claude-app payload; on any pandoc failure the original bytes pass through
untouched), so no shortcut needs a workaround.

One POST is enough: the receiving machine fans it out to every other peer.
The URL can name any machine that's likely to be on — each node has its own
(`fedora`, `fedora-1`, … per `tailscale status`); pointing the shortcut at
the main desktop is the sensible default.

The receiving machine shows a toast — "󰅌 Clipboard from iphone172" with a
content preview (`tailscale serve` forwards the sender's tailnet IP;
`tailscale whois` names it). Only person-sent posts toast: the machines'
own relay traffic is deliberately silent, and the toast is popup-only
(`-a qshell` is ephemeral to the shell) since the clipboard picker already
keeps the content itself.

**"Fetch Clipboard"** (machines → iPhone — pull is the only direction iOS
permits):

1. **Get Contents of URL**: same URL, Method **GET**.
2. **Copy to Clipboard** with *Contents of URL* as input.

Make both one-tap: **Action Button** (Settings → Action Button → Shortcut),
**Back Tap** (Settings → Accessibility → Touch → Back Tap → Double Tap), a
Lock-Screen widget, or Home-Screen icons.

## Adding a machine (the Mac mini, the NUC)

Nothing clipboard-specific to do. On a fresh box the ordinary bring-up is
the whole setup:

1. `chezmoi apply` — installs the scripts, enables `clipboard-serve.socket`
   and `clipboard-sync.service` (run_after_02).
2. `tailscale up` — once logged in, the next `chezmoi apply` (or rerunning
   run_after_05 by hand) publishes the serve mapping. `tailscale serve
   status` should show `/ proxy http://127.0.0.1:9411`.

From that moment the machine both receives (its serve URL is live) and
sends (the push watcher discovers online Linux peers per copy). The other
machines need no edits — they'll find the new node on its first copy.
Old/stale tailnet nodes (`arch`, macOS boot-siblings of these machines) are
filtered out by the online + Linux checks, and cost nothing.

## Troubleshooting

- `systemctl --user status clipboard-serve.socket clipboard-sync.service`
- `curl -s http://127.0.0.1:9411/` — the handler alone;
  `curl -s http://fedora.taila27604.ts.net/` — through tailscaled.
- `tailscale serve status` — the :80 → 9411 mapping (persisted in
  tailscaled's profile; re-created by `chezmoi apply` if reset).
- Handler stderr lands in the journal:
  `journalctl --user -u 'clipboard-serve@*'`.
- The transient `run-*.scope`-style unit holding the clipboard after a push
  is `wl-copy --foreground` and exits at the next local copy — expected.
