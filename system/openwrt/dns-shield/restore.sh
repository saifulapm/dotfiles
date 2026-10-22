#!/bin/sh
# Runs on the router from /tmp/dns-shield-setup: puts dhcp, firewall and https-dns-proxy back from the backup and removes everything DNS Shield added.
S=/tmp/dns-shield-setup
[ -f "$S/backup.tar.gz" ] || { echo "dns-shield: FAILED restore: no backup.tar.gz"; exit 1; }
/etc/init.d/dns-shield stop >/dev/null 2>&1
/etc/init.d/dns-shield disable >/dev/null 2>&1
cd / && tar xzf "$S/backup.tar.gz" etc/config/dhcp etc/config/firewall etc/config/https-dns-proxy || { echo "dns-shield: FAILED restore: tar"; exit 1; }
rm -f /etc/nftables.d/20-dns-shield.nft /etc/init.d/dns-shield /etc/config/dhcp-opkg
rm -rf /etc/dns-shield
[ -f /etc/crontabs/root ] && sed -i '/dns-shield/d' /etc/crontabs/root
[ -s /etc/crontabs/root ] || rm -f /etc/crontabs/root
/etc/init.d/https-dns-proxy enable
/etc/init.d/dnsmasq restart
/etc/init.d/firewall restart >/dev/null 2>&1
/etc/init.d/https-dns-proxy restart
echo "dns-shield: restored"
