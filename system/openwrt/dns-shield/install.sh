#!/bin/sh
# Runs on the router from /tmp/dns-shield-setup, detached: installs DNS Shield, and on any failure puts the backed-up config back.
S=/tmp/dns-shield-setup
log() { echo "dns-shield: $*"; }
fail() {
	log "FAILED $*, restoring"
	sh "$S/restore.sh"
	exit 1
}

[ -f "$S/backup.tar.gz" ] || { log "FAILED no backup.tar.gz, nothing written"; exit 1; }
[ -f "$S/stage/kid.conf" ] && [ -f "$S/stage/gambling.conf" ] || { log "FAILED payload incomplete, nothing written"; exit 1; }

if ! opkg list-installed | grep -q '^dnsmasq-full '; then
	log "fetching dnsmasq-full"
	opkg update >/dev/null 2>&1 || { log "FAILED opkg update, nothing written"; exit 1; }
	mkdir -p "$S/ipk"
	cd "$S/ipk" || exit 1
	for p in dnsmasq-full libnettle8 libnetfilter-conntrack3 libnfnetlink0 dnsmasq; do
		opkg download "$p" >/dev/null 2>&1 || { log "FAILED download $p, nothing written"; exit 1; }
	done
	cd / || exit 1
	rm -rf /var/opkg-lists
	# The dhcp config belongs to the dnsmasq package, so it is kept across the swap.
	cp /etc/config/dhcp "$S/dhcp.keep"
	log "swapping dnsmasq for dnsmasq-full"
	opkg remove dnsmasq >/dev/null 2>&1
	if ! opkg install "$S"/ipk/lib*.ipk "$S"/ipk/dnsmasq-full_*.ipk >/dev/null 2>&1; then
		opkg install "$S"/ipk/dnsmasq_*.ipk >/dev/null 2>&1
		cp "$S/dhcp.keep" /etc/config/dhcp
		fail "dnsmasq-full install"
	fi
	cp "$S/dhcp.keep" /etc/config/dhcp
	rm -f /etc/config/dhcp-opkg
fi
opkg list-installed | grep -q '^dnsmasq-full ' || fail "dnsmasq-full missing"
free=$(df -k /overlay | awk 'NR==2 {print $4}')
[ "${free:-0}" -gt 500 ] || fail "flash free ${free} KB"

/etc/init.d/https-dns-proxy stop >/dev/null 2>&1
/etc/init.d/https-dns-proxy disable >/dev/null 2>&1

M=dhcp.@dnsmasq[0]
for o in server doh_server doh_backup_server doh_backup_noresolv strictorder; do uci -q delete "$M.$o"; done
for s in /mask.icloud.com/ /mask-h2.icloud.com/ /use-application-dns.net/ 94.140.14.14 94.140.15.15; do uci add_list "$M.server=$s"; done
uci set "$M.noresolv=1"
uci -q delete dhcp.dns_shield
uci set dhcp.dns_shield=ipset
uci add_list dhcp.dns_shield.name=kid_block
for d in googlevideo.com facebook.com fbcdn.net instagram.com cdninstagram.com; do uci add_list "dhcp.dns_shield.domain=$d"; done
uci set dhcp.dns_shield.table=fw4
uci set dhcp.dns_shield.table_family=inet
uci set dhcp.dns_shield.family=4
# Members of a Kid set already there survive a second install.
if ! uci -q get firewall.kid >/dev/null; then
	uci set firewall.kid=ipset
	uci set firewall.kid.name=kid
	uci set firewall.kid.family=ipv4
	uci add_list firewall.kid.match=src_ip
fi
if ! uci -q get firewall.kid_mac >/dev/null; then
	uci set firewall.kid_mac=ipset
	uci set firewall.kid_mac.name=kid_mac
	uci set firewall.kid_mac.family=ipv4
	uci add_list firewall.kid_mac.match=src_mac
fi
uci commit dhcp
uci commit firewall

mkdir -p /etc/dns-shield
cp "$S/stage/kid.conf" "$S/stage/blocks.conf" "$S/stage/gambling.conf" /etc/dns-shield/
[ -f /etc/dns-shield/allow ] || : >/etc/dns-shield/allow
cp "$S/stage/dns-shield.init" /etc/init.d/dns-shield
chmod 755 /etc/init.d/dns-shield
cp "$S/stage/20-dns-shield.nft" /etc/nftables.d/20-dns-shield.nft
fw4 check >/dev/null 2>&1 || fail "fw4 check"

touch /etc/crontabs/root
grep -q 'dns-shield' /etc/crontabs/root || echo '17 */6 * * * tail -n 3000 /tmp/dns-shield/kid.log >/tmp/dns-shield/kid.trim && cat /tmp/dns-shield/kid.trim >/tmp/dns-shield/kid.log # dns-shield' >>/etc/crontabs/root
/etc/init.d/cron enable
/etc/init.d/cron restart

log "restarting dnsmasq, firewall and the Kid resolver"
/etc/init.d/dnsmasq restart || fail "dnsmasq restart"
/etc/init.d/firewall restart >/dev/null 2>&1 || fail "firewall restart"
/etc/init.d/dns-shield enable
/etc/init.d/dns-shield restart || fail "dns-shield start"
sleep 3
nslookup example.com 127.0.0.1 >/dev/null 2>&1 || fail "the house resolver does not answer"
ps w | grep -q '[d]ns-shield/kid.conf' || fail "the Kid resolver is not running"
nft list chain inet fw4 dns_shield_forward >/dev/null 2>&1 || fail "the forward chain is not loaded"
nft list set inet fw4 kid_mac >/dev/null 2>&1 || fail "the kid_mac set is not loaded"
ram=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
log "installed flash_free_kb=$(df -k /overlay | awk 'NR==2 {print $4}') ram_available_kb=$ram"
