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
3. Arm the bootstrap script (appendix below, save as /tmp/openwrt-bootstrap.sh)
   on the WIRED machine (NUC):
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

## Appendix: the bootstrap script

The exact script that built the 2026-09-02 setup, kept here as reference
for a future rebuild — run it from the wired NUC after flashing, with
`~/.config/dns-helper/router.env` in place.

```bash
#!/bin/bash
# OpenWrt home-router bootstrap — reproduces the 2026-09-02 Archer C6(US) v2
# setup from a fresh flash (see docs/openwrt-home-2026-09-02.md for the
# flash itself and recovery). Run from a WIRED machine on the LAN (the NUC)
# right after uploading the factory image; it waits for first-boot OpenWrt
# on 192.168.1.1, refuses anything that is not passwordless-ssh OpenWrt,
# then configures in two phases and logs to /tmp/openwrt-bootstrap.log.
#
# ALL identity lives in ~/.config/dns-helper/router.env (this repo is
# public): WIFI_SSID WIFI_PSK WAN_IP WAN_MASK WAN_GW WAN_DNS1 WAN_DNS2
# DOH_PROFILE FALLBACK_DNS RESERVATIONS (space-separated name,mac,ip)
# EXEMPT_IPS (space-separated — skip the DNS hijack) SSH_KEY (path).
#
# Lessons baked in from the first run:
#  - phase 2 must WAIT FOR CLOCK SYNC: opkg over https fails TLS (wget
#    error 5) until sysntpd sets the date on first boot.
#  - https-dns-proxy ships two example instances and force_dns=1; both are
#    removed/disabled or you get a ubus hijack ahead of your own rules and
#    a dead 127.0.0.1#5054 dnsmasq entry.
#  - fw4 forbids list src_ip on redirects and mistranslates ACCEPT
#    redirects; hijack exemptions must be an ipset negated on the DNAT rule.
set -uo pipefail
exec >>/tmp/openwrt-bootstrap.log 2>&1
log() { echo "[$(date +%H:%M:%S)] $*"; }

ENV="$HOME/.config/dns-helper/router.env"
[ -f "$ENV" ] || { log "no $ENV — refusing to run"; exit 1; }
# shellcheck source=/dev/null
. "$ENV"
PUB=$(cat "${SSH_KEY}.pub")
SSH="ssh -i $SSH_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=4"

log "armed — waiting for fresh OpenWrt on 192.168.1.1"
for i in $(seq 1 240); do
    if ping -c1 -W1 192.168.1.1 >/dev/null 2>&1 \
        && $SSH -o PasswordAuthentication=no root@192.168.1.1 'test -f /etc/openwrt_release && echo OPENWRT' 2>/dev/null | grep -q OPENWRT; then
        log "OpenWrt confirmed"
        break
    fi
    sleep 5
    [ "$i" = 240 ] && { log "TIMEOUT waiting for OpenWrt"; exit 1; }
done

log "phase 1: identity, LAN, WAN, WiFi, reservations"
{
    cat <<EOF
set -e
mkdir -p /etc/dropbear
echo '$PUB' >> /etc/dropbear/authorized_keys
printf '%s\n%s\n' '$WIFI_PSK' '$WIFI_PSK' | passwd root >/dev/null
uci set network.lan.ipaddr='192.168.0.1'
uci set network.wan.proto='static'
uci set network.wan.ipaddr='$WAN_IP'
uci set network.wan.netmask='$WAN_MASK'
uci set network.wan.gateway='$WAN_GW'
uci -q delete network.wan.dns || true
uci add_list network.wan.dns='$WAN_DNS1'
uci add_list network.wan.dns='$WAN_DNS2'
for r in 0 1; do
  uci set wireless.radio\$r.disabled='0'
  uci set wireless.radio\$r.country='US'
  uci set wireless.default_radio\$r.ssid='$WIFI_SSID'
  uci set wireless.default_radio\$r.encryption='psk2'
  uci set wireless.default_radio\$r.key='$WIFI_PSK'
done
EOF
    for res in $RESERVATIONS; do
        IFS=, read -r name mac ip <<<"$res"
        cat <<EOF
uci add dhcp host >/dev/null
uci set dhcp.@host[-1].name='$name'
uci set dhcp.@host[-1].mac='$mac'
uci set dhcp.@host[-1].ip='$ip'
EOF
    done
    echo "uci commit; echo PHASE1-OK; (sleep 2; reboot) &"
} | $SSH root@192.168.1.1 sh -s
log "phase 1 pushed — router rebooting into 192.168.0.1"

sleep 20
log "waiting for router at 192.168.0.1 with WAN + synced clock"
for i in $(seq 1 120); do
    if $SSH root@192.168.0.1 '[ "$(date +%s)" -gt 1700000000 ] && ping -c1 -W2 8.8.8.8 >/dev/null 2>&1 && echo READY' 2>/dev/null | grep -q READY; then
        log "router up, WAN up, clock sane"
        break
    fi
    sleep 5
    [ "$i" = 120 ] && { log "TIMEOUT waiting for WAN/clock"; exit 1; }
done

log "phase 2: https-dns-proxy → uBlockDNS, fallback, ipset hijack"
{
    cat <<EOF
set -e
opkg update >/dev/null || { sleep 15; opkg update >/dev/null; }
opkg install https-dns-proxy luci-app-https-dns-proxy >/dev/null
while uci -q delete https-dns-proxy.@https-dns-proxy[0]; do :; done
uci add https-dns-proxy https-dns-proxy >/dev/null
uci set https-dns-proxy.@https-dns-proxy[-1].resolver_url='https://my.ublockdns.com/$DOH_PROFILE'
uci set https-dns-proxy.@https-dns-proxy[-1].bootstrap_dns='1.1.1.1,8.8.8.8'
uci set https-dns-proxy.@https-dns-proxy[-1].listen_addr='127.0.0.1'
uci set https-dns-proxy.@https-dns-proxy[-1].listen_port='5053'
uci set https-dns-proxy.config.force_dns='0'
uci commit https-dns-proxy
uci add firewall ipset >/dev/null
uci set firewall.@ipset[-1].name='dns_exempt'
uci set firewall.@ipset[-1].family='ipv4'
uci add_list firewall.@ipset[-1].match='src_net'
EOF
    for ip in $EXEMPT_IPS; do
        echo "uci add_list firewall.@ipset[-1].entry='$ip'"
    done
    cat <<EOF
uci add firewall redirect >/dev/null
uci set firewall.@redirect[-1].name='dns-hijack'
uci set firewall.@redirect[-1].src='lan'
uci set firewall.@redirect[-1].proto='tcp udp'
uci set firewall.@redirect[-1].src_dport='53'
uci set firewall.@redirect[-1].ipset='!dns_exempt'
uci set firewall.@redirect[-1].target='DNAT'
uci commit firewall
/etc/init.d/https-dns-proxy enable
/etc/init.d/https-dns-proxy restart
sleep 3
# The package's install-time default instances may have left stale dnsmasq
# forwards; drop every 127.0.0.1#50xx then let a restart re-add the real one.
for s in \$(uci -q get dhcp.@dnsmasq[0].server | tr ' ' '\n' | grep '^127.0.0.1#'); do
  uci del_list dhcp.@dnsmasq[0].server="\$s"
done
uci add_list dhcp.@dnsmasq[0].server='$FALLBACK_DNS'
uci set dhcp.@dnsmasq[0].strictorder='1'
uci commit dhcp
/etc/init.d/https-dns-proxy restart
sleep 2
/etc/init.d/dnsmasq restart
/etc/init.d/firewall restart >/dev/null 2>&1
echo PHASE2-OK
EOF
} | $SSH root@192.168.0.1 sh -s
log "phase 2 done — verifying"

sleep 2
V=$($SSH root@192.168.0.1 "nslookup youtube.com 127.0.0.1 2>/dev/null | tail -2" 2>/dev/null)
log "verify (expect 0.0.0.0/::): $V"
log "BOOTSTRAP COMPLETE"
```
