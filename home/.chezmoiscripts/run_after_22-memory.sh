#!/usr/bin/env bash
# Memory headroom (user decision 2026-08-08): heavy sessions on the 8 GB
# machines drove systemd-oomd to kill working apps mid-work. macOS survives
# the same load by compressing + swapping without limit; approximate that:
# 16 G of disk swap total (Asahi ships 8 G at /var/swap/swapfile, zswap in
# front of it) and zstd as the zswap compressor (Asahi's kernel default lzo
# compresses measurably worse). The oomd-patience half is pure user config
# (dot_config/systemd/user/slice.d/50-oomd-patient.conf, live after 02's
# daemon-reload) and the on-screen warning is mempressure.service — this
# script is only the root-owned pieces. Runtime-gated: a machine without
# zswap (NUC — stock zram) just gets the swapfile.
set -uo pipefail

# Gate on the artifact this script creates being ACTIVE, not on total swap
# (audit 2026-08-08): the old `SwapTotal < 15 GiB` test assumed Asahi's 8 G
# swapfile underneath — on a NUC whose zram tops out below 7 G it never
# settled, re-prompting for sudo on every apply while doing nothing.
# `grep -x >/dev/null`, never `grep -qx`: -q exits at the first match, which
# SIGPIPEs swapon mid-write and makes pipefail report 141 for an active swapfile.
need_swap=0
swapon --show=NAME --noheadings | grep -x /var/swap/swapfile2 >/dev/null || need_swap=1

need_zstd=0
if [ "$(cat /sys/module/zswap/parameters/enabled 2>/dev/null)" = "Y" ] &&
  [ "$(cat /sys/module/zswap/parameters/compressor)" != "zstd" ]; then
  need_zstd=1
fi

if [ "$need_swap" = 0 ] && [ "$need_zstd" = 0 ]; then
  exit 0
fi

# Root, by whichever route this run can actually reach (same ladder as
# 01-autologin): cached sudo, interactive sudo when a terminal exists, then
# pkexec so a background apply can land this with on-screen approval.
run_root() {
  if sudo -n true 2>/dev/null; then
    sudo "$@"
  elif [ -t 0 ] && sudo -v 2>/dev/null; then
    sudo "$@"
  elif command -v pkexec >/dev/null 2>&1 && [ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]; then
    echo "memory: asking for authorization on screen…" >&2
    timeout 180 pkexec "$@"
  else
    return 1
  fi
}

# One root call — a pkexec route prompts once per call, so swapfile creation
# and the zswap switch travel together in a generated script.
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
cat >"$tmp" <<'EOF'
#!/bin/bash
set -euo pipefail
need_swap=$1 need_zstd=$2

if [ "$need_swap" = 1 ]; then
  mkdir -p /var/swap
  if [ ! -f /var/swap/swapfile2 ]; then
    # btrfs refuses plain-file swap (COW): mkswapfile handles nocow itself.
    if [ "$(stat -f -c %T /var/swap)" = btrfs ]; then
      btrfs filesystem mkswapfile --size 8g /var/swap/swapfile2
    else
      fallocate -l 8G /var/swap/swapfile2
      chmod 600 /var/swap/swapfile2
      mkswap /var/swap/swapfile2
    fi
  fi
  grep -q '^/var/swap/swapfile2 ' /etc/fstab ||
    echo '/var/swap/swapfile2 swap swap sw 0 0' >>/etc/fstab
  # --fixpgsz fallback: btrfs mkswapfile stamps a 4 K-page signature, which
  # the Asahi 16 K kernel refuses — reinitialize for the running page size.
  swapon --show=NAME --noheadings | grep -x /var/swap/swapfile2 >/dev/null ||
    swapon /var/swap/swapfile2 2>/dev/null ||
    swapon --fixpgsz /var/swap/swapfile2
fi

if [ "$need_zstd" = 1 ]; then
  # crypto zstd is =m on the Asahi kernel: load it now and every boot
  # (modules-load runs before tmpfiles-setup), then point zswap at it.
  printf '# Managed by ~/.dotfiles (run_after_22-memory.sh): zswap compressor.\nzstd\n' \
    >/etc/modules-load.d/zstd.conf
  printf '# Managed by ~/.dotfiles (run_after_22-memory.sh).\nw /sys/module/zswap/parameters/compressor - - - - zstd\n' \
    >/etc/tmpfiles.d/zswap.conf
  modprobe zstd
  echo zstd >/sys/module/zswap/parameters/compressor
fi
EOF
chmod +x "$tmp"

if ! run_root /bin/bash "$tmp" "$need_swap" "$need_zstd"; then
  echo "memory: root step failed or not authorized — swap/zswap incomplete (rerun 'chezmoi apply' in a terminal)" >&2
  exit 0
fi
echo "memory: swap $(awk '/^SwapTotal:/ {printf "%.1fG", $2/1048576}' /proc/meminfo) total, zswap compressor $(cat /sys/module/zswap/parameters/compressor 2>/dev/null || echo n/a)"
