#!/usr/bin/env bash
# Clipboard VIP (2026-08-11): 10.99.99.99 answers the clipboard endpoint on
# whichever machine is awake. Every box advertises the /32 (run_after_05)
# and Tailscale's HA subnet-router failover keeps the route pointed at an
# online one — the phone's shortcuts target http://10.99.99.99:9411/ and
# never name a machine again. Tailscale Services would be the purpose-built
# answer, but service hosts must be TAGGED nodes and Taildrop refuses
# tagged devices (kb/1106) — that trade would kill the Taildrop toast flow,
# so: a plain HA route, which needs no tags and works on every plan.
#
# Two root halves, combined into one call (a pkexec route prompts once):
#  * clipboard-vip.service — oneshot `ip addr replace` putting the VIP on
#    lo, so packets the route delivers here are locally accepted. `replace`
#    is idempotent and touches nothing else on lo.
#  * a firewalld rich rule admitting TCP 9411 from tailnet sources ONLY
#    (100.64.0.0/10). The socket listens wildcard now; the default zone's
#    drop keeps the LAN out, so this source-scoped rule is the single hole.
#    No v6 twin on purpose: the VIP is v4, and machine-to-machine traffic
#    rides tailscale serve inside tailscaled, never this port.
set -uo pipefail

vip="10.99.99.99"
unit="/etc/systemd/system/clipboard-vip.service"
rule='rule family="ipv4" source address="100.64.0.0/10" port port="9411" protocol="tcp" accept'

expected_unit() {
  cat <<UNIT
[Unit]
Description=Clipboard VIP address on loopback ($vip)
Documentation=file://$HOME/.dotfiles/docs/clipboard-2026-08-10.md

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/ip addr replace $vip/32 dev lo

[Install]
WantedBy=multi-user.target
UNIT
}

# Loud skips, like 19-dufs-firewall: without firewalld the wildcard socket
# would sit open on the LAN, so the VIP pieces wait until the firewall is up
# rather than trading convenience for that exposure.
command -v firewall-cmd >/dev/null 2>&1 \
  || { echo "clipboard-vip: firewalld not installed (00-install-packages pending?) — VIP not set up" >&2; exit 0; }
systemctl is-active --quiet firewalld 2>/dev/null \
  || { echo "clipboard-vip: firewalld not running — VIP not set up" >&2; exit 0; }

# Unprivileged guards for both halves: the rich-rule query is polkit-allowed
# in a session, the unit file is world-readable. Only a missing/changed half
# reaches for root.
unit_ok=0
[ -f "$unit" ] && expected_unit | cmp -s - "$unit" \
  && systemctl is-active --quiet clipboard-vip.service && unit_ok=1
rule_ok=0
firewall-cmd --query-rich-rule="$rule" >/dev/null 2>&1 && rule_ok=1
[ "$unit_ok" = 1 ] && [ "$rule_ok" = 1 ] && exit 0

# Same root ladder as 18/19: cached sudo, interactive sudo when a terminal
# exists, then pkexec so a background apply can land this on screen.
run_root() {
  if sudo -n true 2>/dev/null; then
    sudo "$@"
  elif [ -t 0 ] && sudo -v 2>/dev/null; then
    sudo "$@"
  elif command -v pkexec >/dev/null 2>&1 && [ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]; then
    echo "clipboard-vip: asking for authorization on screen…" >&2
    timeout 180 pkexec "$@"
  else
    return 1
  fi
}

tmp="$(mktemp)" || exit 0
expected_unit >"$tmp"
# Re-adding an existing rich rule is a warned no-op, so the combined call
# stays safe when only one half was missing.
if ! run_root /bin/sh -c "install -m 0644 '$tmp' '$unit' \
    && systemctl daemon-reload \
    && systemctl enable --now clipboard-vip.service \
    && firewall-cmd --quiet --add-rich-rule='$rule' \
    && firewall-cmd --quiet --permanent --add-rich-rule='$rule'"; then
  rm -f "$tmp"
  echo "clipboard-vip: not authorized — VIP inactive on this machine (rerun 'chezmoi apply' in a terminal)" >&2
  exit 0
fi
rm -f "$tmp"
echo "clipboard-vip: $vip on lo + firewalld 9411 open to tailnet sources (runtime + permanent)"
