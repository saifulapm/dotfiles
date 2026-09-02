# Office DNS: the mini as filter for the Deco network — 2026-09-02

The office runs a TP-Link **Deco X60** mesh, which cannot be flashed or
scripted (its web UI at 192.168.68.1 exposes only Status and System — no
DHCP, no DNS, no reservations; everything real lives in the phone app). So
unlike home, the filtering does not live in the router: the **mini** serves
the office LAN with the same dnsmasq → uBlockDNS chain every helper runs
(run_after_17/18), and the Deco simply hands it out.

Result, which is what was asked for: **filtered while the mini is on,
ordinary working internet when it is off.**

## What is configured

Deco app → More → Advanced:

- **DHCP Server** → Primary DNS `192.168.68.56` (the mini), Secondary DNS
  `94.140.14.14` (AdGuard). The secondary is the "internet still works"
  guarantee; it blocks ads but not YouTube, which is fine here — the child
  devices are on the home network.
- **Address Reservation** → `20:A5:CB:C8:D5:6F` → `192.168.68.56`.

On the mini:

- `~/.config/dns-helper/serve` = `wld0`, `~/.config/dns-helper/profile` =
  the uBlockDNS profile id (both untracked; see run_after_18).
- Its wifi is pinned to the **permanent** MAC:
  `nmcli connection modify eCommerceStaff 802-11-wireless.cloned-mac-address permanent`.
  NetworkManager's default is a stable-per-connection RANDOM MAC derived
  from the machine id, so a fresh install would come back as a different
  device and silently lose the reservation — the one manual step to redo
  when this machine is reinstalled.
- Its own resolver is pinned with `network-dns uBlockDNS` — see the trap
  below, this is not optional on a machine that serves its own network.

## The trap: the helper resolving through itself

The hour it was switched on, the office went to timeouts. The Deco had
started handing out `192.168.68.56` as DNS — and the mini is a DHCP client
of its own network, so **the mini began asking itself**. Its uBlockDNS
client normally bootstraps against hardcoded public resolvers, but a wifi
reconnect made that fail for a moment, and it fell back to "system DNS",
which by then was its own LAN address: client → dnsmasq → client, wedged,
every lookup timing out until the client was restarted.

The fix is to pin the helper's own resolver to **127.0.0.1** (the client
itself), which `network-dns uBlockDNS` now does. That exact address is
load-bearing: the client's anti-loop guard (`HasDNS127001` in its source)
recognises only the literal `127.0.0.1`, so pointing the link there makes
it refuse the system-DNS fallback entirely. Pinning to dnsmasq's
`127.0.0.2` instead prevents only the LAN-address loop, not the loopback
one. `*.test` keeps working either way — the resolved drop-in routes
`~test` to `127.0.0.2` as a routing domain (verified).

## Verify

From any office client:

    dig @192.168.68.56 youtube.com +short     # 0.0.0.0
    dig @192.168.68.56 example.com +short     # a real address
    nmcli -f DHCP4 device show <iface> | grep domain_name_servers
                                              # 192.168.68.56 94.140.14.14

On the mini: `qs ipc call bar open dnsshield` — the panel's rows say
whether the client, the forwarder, the LAN listener and a live block test
all agree. `resolvectl status <iface>` must show `127.0.0.1`, never the
mini's own LAN address.

## Known limits

- If the mini's LAN address ever changes, dnsmasq follows it (the `serve`
  marker names the interface, not an IP) but the **Deco's DNS field does
  not** — no automation can reach an app-managed Deco. The reservation is
  what keeps that from happening; the panel is what makes it visible.
- Clients drift to the AdGuard secondary on any hiccup and stay there for
  a while (systemd-resolved does this too — seen at home). Ads stay
  blocked, YouTube does not, which is acceptable for this network.
