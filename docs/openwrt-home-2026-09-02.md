# Home router: OpenWrt on the Archer C6(US) v2 — 2026-09-02

The home TP-Link Archer C6 was flashed to OpenWrt so the family DNS filter
(uBlockDNS over DoH: ads + YouTube + YouTube Kids, incl. the apps) runs
NATIVELY in the router — no helper machine required for the home network.

## What runs on the router

- OpenWrt 24.10.8, image `tplink_archer-c6-v2-us` (**US variant — the EU
  `archer-c6-v2` image has different partitioning; never mix them**; the
  label on the bottom says which one you have).
- `https-dns-proxy` → `https://my.ublockdns.com/<profile>` (DoH), plugged
  into dnsmasq with `strictorder` and a plain-DNS fallback appended — so a
  uBlockDNS outage degrades to unfiltered-but-working internet.
- Port-53 DNS hijack (fw4 DNAT) so devices with hardcoded DNS are filtered
  too, EXCEPT the machines in the `dns_exempt` ipset (our own boxes, which
  run their own filter chain — see run_after_17/18). fw4 gotchas: redirects
  reject list `src_ip` and mistranslate `target ACCEPT`; the negated ipset
  on the DNAT rule is the only clean exemption mechanism.
- The package's own `force_dns` is disabled (it would install a second,
  exemption-less hijack via ubus) and its two example resolver instances
  are deleted (they leave a dead `127.0.0.1#5054` in dnsmasq otherwise).
- LuCI at http://192.168.0.1 — root, password = the WiFi passphrase.

## Fresh setup / re-flash

1. Secrets live OUTSIDE this public repo in `~/.config/dns-helper/router.env`
   (WIFI_SSID/PSK, WAN static details, DOH_PROFILE, FALLBACK_DNS,
   RESERVATIONS, EXEMPT_IPS, SSH_KEY). Recreate it from the pass store or
   the ISP contract if lost.
2. Download + sha256-verify the factory image from
   downloads.openwrt.org releases → targets/ath79/generic. Keep a copy on
   the wired machine.
3. Arm `router/openwrt-home-bootstrap.sh` on the WIRED machine (NUC):
   it waits for first-boot OpenWrt on 192.168.1.1 and does everything —
   phase 1 (LAN/WAN/WiFi/reservations, reboot) and phase 2 (packages, DoH,
   hijack+ipset, fallback), with the first-boot clock-sync wait that the
   original run was missing (opkg fails TLS until NTP syncs).
4. Flash from the stock/LuCI web UI (System → Firmware upgrade; from
   OpenWrt use the `sysupgrade` image instead of `factory`).
5. Verify from a LAN client: `dig @192.168.0.1 youtube.com` → `0.0.0.0`;
   `dig @8.8.8.8 youtube.com` → `0.0.0.0` from a family device (hijack),
   real answer from an exempt machine.

## Recovery

- Stock-firmware config backup: `backup-ArcherC6v2-2026-09-02.bin`
  (Downloads / archived) restores the pre-OpenWrt TP-Link setup after a
  stock re-flash.
- TFTP de-brick: serve `ArcherC6v2_tp_recovery.bin` from a WIRED box at
  192.168.0.66 (force 100 Mbit if link training fails), hold reset while
  powering on.
- OpenWrt config snapshot: `sysupgrade -b /tmp/backup.tar.gz` on the
  router; keep a copy off-router after every change.

## Known quirks

- QCA9886 5 GHz uses `ath10k-ct`; if WiFi gets flaky, swap to the non-ct
  `kmod-ath10k` + firmware (documented on the OpenWrt device page).
- The office Deco is app-managed and stays stock: its DHCP points at the
  mini helper (run_after_17/18 machine) with a plain fallback, so office
  filtering follows the mini's power state by design.
