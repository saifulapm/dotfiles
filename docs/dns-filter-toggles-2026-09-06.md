# DNS filter toggles: blocking categories on a timer — 2026-09-06

Until now the family DNS was all-or-nothing. YouTube was blocked at the
uBlockDNS account, and the only way to watch anything was `network-dns
Google` in the network panel — which unfiltered **everything**, helped only
the one device it was run on, and left every cache in the chain still holding
the old answer, so it felt like it needed a browser restart to take.

This replaces that with a switch per category, on the DNS Shield panel, plus
a fixed-duration "open it for a while and close it again by yourself".

## What changed

- **`bin/dns-filter`** — the CLI that talks to the uBlockDNS account API.
  `status [--json]`, `on <category>`, `off <category> [duration]`,
  `allow <domain>`, `unallow <domain>`, `allowed`, `reconcile`.
  Categories: `youtube social adult gambling`.
- **DNS Shield panel** — rebuilt as a control surface. A FILTERS section (one
  switch per category, `30m` / `2h` chips on the blocked ones, keys `1`-`4`)
  over an ALLOWED section (a box to add a domain, and each allowed domain with
  its own remove button). The five read-only CHAIN diagnosis rows and the
  footer blurb were removed; the one fact worth keeping from them — is *this*
  machine actually resolving through the filter — is now the verdict on the
  header's trailing edge (`FILTERED` / `FALLBACK` / `BYPASSED`).
- **`bin/network-dns`** now flushes resolved's cache after switching
  providers. That is the "I changed DNS and it didn't take" fix, and it is
  the whole fix for this machine — see the cache table below.
- **`ublockdns.service`** gains `-token-file /etc/ublockdns/token`
  (run_after_18), which subscribes the client to the account's rules stream
  so it drops its own cache the instant a rule changes.
- **dnsmasq** gets `cache-size=0` on helper machines (run_after_17).
- **`dns-filter-reconcile.timer`** — the backstop that re-blocks a category
  whose timed unblock expired while the machine was asleep or off.

## The account is the right layer

The home OpenWrt router (DoH), the office mini's chain, and every roaming
client all resolve through the **same uBlockDNS profile**. One PUT there
reaches the whole family at once — which is exactly what `network-dns` could
never do, since it only ever changed the machine it ran on.

## The API

Undocumented. Read out of the dashboard's own JS bundle
(`ublockdns.com/assets/index-*.js`) and verified by hand on 2026-09-06:

    POST /api/auth              {token}   → ubd_session cookie, 1 year
    GET  /api/profile/<id>                → the whole config object
    PUT  /api/profile/<id>      {lists, custom_rules, dns_provider,
                                 preset_id, policy_modules}
    GET  /api/policy                      → the module/preset catalogue

The token is the same 4-word account token the client takes
(`pass show uBlockDNS/key`); `bin/dns-filter` reads it from
`~/.config/dns-helper/token`, untracked like `profile` and `serve`.

`PUT` replaces the object wholesale — there is no PATCH — so every change is
a read-modify-write under `flock`. The server no-ops a semantically identical
body (`rules_version` does not move), which is what makes an already-correct
`on` free.

**This is the standing risk of the whole feature**: an undocumented API can
change shape without warning. `dns-filter` therefore reports rather than
guesses, and `status --json` always emits parseable JSON — including for its
own failures — so the panel degrades to a message rather than an empty list.

## How the four categories map

| Category | Mechanism |
|---|---|
| Social apps / Adult content / Gambling | `policy_modules` booleans, server-maintained HaGeZi lists |
| YouTube | a group of 7 `custom_rules`: `youtube.com`, `youtu.be`, `googlevideo.com`, `ytimg.com`, `youtubekids.com`, `youtube-nocookie.com`, `youtubei.googleapis.com` |

YouTube has to be the whole group: the apps and TV clients resolve
`googlevideo`/`ytimg`/`youtubei` directly and keep playing if only
`youtube.com` goes.

`||mask.icloud.com^` and `||mask-h2.icloud.com^` also live in `custom_rules`
and are **never touched** — they block iCloud Private Relay, which is a
bypass route around the entire filter, not a YouTube rule. Opening YouTube
for half an hour must not quietly open the tunnel that makes every other rule
optional.

Ads are deliberately not a toggle: they are the 45-list baseline, the thing
the service is for, and turning them off is not a thing anyone wanted.

## The allowlist: rescuing a domain a blocklist is wrong about

    dns-filter allow t.co
    dns-filter allowed
    dns-filter unallow t.co

The service parses `custom_rules` as ABP, and `@@||domain^` is an exception
that **beats all 46 blocklists**. That is how you keep a domain working
without turning off the list that catches it.

The case that prompted it (2026-09-06): **every link on x.com was dead.** X
wraps every outbound link in its `t.co` redirector, and `t.co` is on the
tracking lists — reasonably, since it *is* a click tracker, but blocking it
breaks the links rather than just the tracking. `allow t.co` fixes it and
leaves `analytics.twitter.com`, `static.ads-twitter.com` and `ads-api.x.com`
blocked, which is the right split.

The same list is managed from the panel's ALLOWED section — type a domain,
Enter or the `+` chip to add, the `×` beside a row to take it out. `dns-filter
status` prints it too. That visibility is deliberate: an exception overrides
everything, and a hole nobody can see is a hole nobody ever closes.

## Why a toggle now lands quickly

| Layer | Behaviour |
|---|---|
| uBlockDNS server | instant — the PUT *is* the change |
| the local client | instant, via the rules stream — **needs `-token-file`** |
| dnsmasq (helpers) | instant — `cache-size=0`, it is a router, not a cache |
| systemd-resolved | flushed by `dns-filter` and by `network-dns` |
| the browser | **not reachable from any script.** Chromium keeps its own host cache; it honours TTL, so it catches up within seconds to a minute |

`cache-size=0` is not an oversight. On a helper this dnsmasq is a two-line
router (`*.test` local, everything else to the client on 127.0.0.1) and the
client behind it caches already. A second cache in front bought nothing and
cost the one thing that mattered: uBlockDNS answers a block with a **300 s
TTL**, so this layer served `0.0.0.0` for five minutes after an unblock, to
every device on the LAN.

## Timed unblocks fail closed

`dns-filter off youtube 30m` arms a transient `systemd-run` timer for the
restore — but a transient timer does not survive a reboot, a logout, or a
suspend straight through its deadline, and it fails the wrong way round: the
category stays **open**.

So the deadline file in `~/.local/state/dns-helper/until-<category>` is the
real record, and `dns-filter reconcile` enforces it. It runs from
`dns-filter-reconcile.timer` (every 5 min) and from the panel on every open.
It costs nothing when idle — with no deadline file it exits before it reads a
token or opens a socket. Worst case is "a few minutes late", never "until
somebody notices".

## Verify

    dns-filter status                  # what is blocked, and until when
    dns-filter off youtube 30m         # then dig youtube.com → a real address
    dns-filter on youtube              # → 0.0.0.0 again, timer cancelled
    dns-filter allow t.co              # then check the panel's ALLOWED list
    qs ipc call bar open dnsshield     # the panel

## Two things the toggles broke, and the fixes

- **The health probe named a domain you can now unblock.** `chainHealthy`
  proved the filter worked by checking `youtube.com` came back `0.0.0.0` — so
  the moment you legitimately opened YouTube for half an hour, the shield went
  dim and the hero read "Chain up but NOT blocking". The probe now tests
  `doubleclick.net`: ads are the always-on baseline and the one thing no
  toggle can turn off.
- **`lanServing` was reading a key that no longer exists.** It looked at
  `state.bindLan`, which commit `421506c` renamed to `lanBound`/`lanIps`, so
  it was always `undefined` and warned on every probe. Nothing read it. Deleted
  along with `Model.rows()`, whose only consumer was the CHAIN section.
