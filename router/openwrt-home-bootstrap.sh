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
