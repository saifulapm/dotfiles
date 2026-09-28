#!/usr/bin/env bash
# BBR congestion control + fq qdisc (omarchy delta audit 2026-09-28, approved).
# Fedora's default is cubic over fq_codel; BBR keeps throughput up on lossy
# Wi-Fi and long paths, and fq is the pacing qdisc it is designed around.
#
# Both are modules on the Asahi kernel (CONFIG_TCP_CONG_BBR=m,
# CONFIG_NET_SCH_FQ=m). The kernel would autoload them when root writes the
# sysctl, but modules-load.d makes the boot order explicit instead:
# systemd-sysctl.service is ordered After=systemd-modules-load.service.
#
# Same shape as run_after_17-test-domains.sh's sysctl file: stage as the user,
# content-compare against /etc, and only ask for root when something changed.
set -uo pipefail
warn() { echo "tcp-bbr: $*" >&2; }

run_root() {
  if sudo -n true 2>/dev/null; then
    sudo "$@"
  elif [ -t 0 ] && sudo -v 2>/dev/null; then
    sudo "$@"
  elif command -v pkexec >/dev/null 2>&1 && [ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]; then
    echo "tcp-bbr: asking for authorization on screen…" >&2
    timeout 180 pkexec "$@"
  else
    return 1
  fi
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat >"$tmp/sysctl.conf" <<'EOF'
# BBR congestion control over the fq qdisc (managed by chezmoi, see
# run_after_57-tcp-bbr.sh). default_qdisc applies to qdiscs created after it
# is set, i.e. interfaces brought up after boot-time sysctl.
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF

cat >"$tmp/modules.conf" <<'EOF'
# Loaded before systemd-sysctl applies 99-tcp-bbr.conf (managed by chezmoi,
# see run_after_57-tcp-bbr.sh).
tcp_bbr
sch_fq
EOF

chmod 0644 "$tmp"/*.conf

root_sh=""
add() { root_sh="${root_sh}${1}"$'\n'; }
stale() { ! cmp -s "$1" "$2"; }

if stale "$tmp/modules.conf" /etc/modules-load.d/tcp-bbr.conf \
  || stale "$tmp/sysctl.conf" /etc/sysctl.d/99-tcp-bbr.conf; then
  add "install -D -m 0644 '$tmp/modules.conf' /etc/modules-load.d/tcp-bbr.conf"
  add "install -D -m 0644 '$tmp/sysctl.conf' /etc/sysctl.d/99-tcp-bbr.conf"
  add "modprobe tcp_bbr && modprobe sch_fq"
  add "sysctl --system >/dev/null"
fi

[ -n "$root_sh" ] || exit 0

if ! run_root /bin/sh -c "set -e
$root_sh"; then
  warn "root step failed or not authorized — BBR not applied (rerun 'chezmoi apply' in a terminal)"
  exit 0
fi
echo "tcp-bbr: $(sysctl -n net.ipv4.tcp_congestion_control) over $(sysctl -n net.core.default_qdisc)"
