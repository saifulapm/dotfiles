#!/usr/bin/env bash
# Daemon trim (user decision 2026-08-08): the 8 GB machines run 10-15 day
# uptimes and every always-on daemon is rent. Audit found ~130 MB of
# distro-default residents doing nothing for a dev laptop: the abrt suite
# (abrtd + three abrt-dump-journald workers, 93 MB measured, tailing the
# journal continuously), rsyslog (30 MB, duplicating the journal into
# /var/log/messages forever), systemd-homed (zero managed homes — verified
# with `homectl list`), gssproxy (NFS/Kerberos on a box with no NFS) and
# raid-check.timer (single NVMe, no RAID). Also caps the journal at 200 M
# (SystemMaxUse) — the default cap is 10% of disk, ~4 G on these machines,
# which a long uptime will eventually reach.
#
# Disable-only via the system manager, re-checked on EVERY apply: the same
# self-heal reasoning as voxtype in 02-user-timers — package updates can
# re-apply presets and flip units back to enabled, and an apply-time disable
# quietly undoes that. gssproxy alone is MASKED, not disabled: it is already
# `disabled` yet running, because static auth-rpcgss-module.service pulls it
# in by Wants= at boot, and only a mask beats a dependency pull.
# Guarded per unit on the unit file existing, so a machine without (say)
# rsyslog installed skips it silently instead of warning every apply.
set -uo pipefail

off_units=(abrtd.service abrt-journal-core.service abrt-oops.service
  abrt-xorg.service abrt-vmcore.service rsyslog.service
  systemd-homed.service systemd-homed-activate.service raid-check.timer)

need_disable=()
for u in "${off_units[@]}"; do
  case "$(systemctl is-enabled "$u" 2>/dev/null)" in
    enabled | enabled-runtime) need_disable+=("$u") ;;
  esac
done

need_mask=0
if systemctl cat gssproxy.service >/dev/null 2>&1 &&
  [ "$(systemctl is-enabled gssproxy.service 2>/dev/null)" != masked ]; then
  need_mask=1
fi

journal_conf=/etc/systemd/journald.conf.d/50-size-cap.conf
need_journal=0
[ -f "$journal_conf" ] || need_journal=1

if [ ${#need_disable[@]} -eq 0 ] && [ "$need_mask" = 0 ] && [ "$need_journal" = 0 ]; then
  exit 0
fi

# Root, by whichever route this run can actually reach (same ladder as
# 22-memory): cached sudo, interactive sudo when a terminal exists, then
# pkexec so a background apply can land this with on-screen approval.
run_root() {
  if sudo -n true 2>/dev/null; then
    sudo "$@"
  elif [ -t 0 ] && sudo -v 2>/dev/null; then
    sudo "$@"
  elif command -v pkexec >/dev/null 2>&1 && [ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]; then
    echo "daemon trim: asking for authorization on screen…" >&2
    timeout 180 pkexec "$@"
  else
    return 1
  fi
}

# One root call — a pkexec route prompts once per call, so the disables, the
# mask and the journald cap travel together in a generated script.
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
cat >"$tmp" <<'EOF'
#!/bin/bash
set -euo pipefail
need_mask=$1 need_journal=$2 journal_conf=$3
shift 3

# --now is safe for all of these mid-apply: none holds user-visible state the
# way a dictation-in-progress does (the voxtype caveat does not transfer).
# A real `if`, not `[ ] &&` — under set -e an empty disable list would make
# the compound return 1 and kill this helper before the mask and journal cap,
# which is exactly the fresh-NUC case (nothing to disable, cap still needed).
if [ $# -gt 0 ]; then
  systemctl disable --now "$@"
fi

# Stopping homed and homed-activate in one call races their stop hooks:
# homed-activate's ExecStop (homectl deactivate-all) fails once homed is
# already gone, leaving a cosmetic 'failed' unit with zero home areas to
# deactivate. Clear the flag.
systemctl reset-failed systemd-homed-activate.service 2>/dev/null || true

if [ "$need_mask" = 1 ]; then
  systemctl mask --now gssproxy.service
fi

if [ "$need_journal" = 1 ]; then
  mkdir -p "$(dirname "$journal_conf")"
  printf '# Managed by ~/.dotfiles (run_after_26-trim-daemons.sh).\n[Journal]\nSystemMaxUse=200M\n' \
    >"$journal_conf"
  systemctl restart systemd-journald
fi
EOF
chmod +x "$tmp"

if ! run_root /bin/bash "$tmp" "$need_mask" "$need_journal" "$journal_conf" \
  ${need_disable[@]+"${need_disable[@]}"}; then
  echo "daemon trim: root step failed or not authorized — daemons untrimmed (rerun 'chezmoi apply' in a terminal)" >&2
  exit 0
fi
notes=""
[ "$need_mask" = 1 ] && notes="$notes; gssproxy masked"
[ "$need_journal" = 1 ] && notes="$notes; journal capped at 200M"
echo "daemon trim: disabled ${need_disable[*]:-nothing new}$notes"
