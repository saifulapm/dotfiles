#!/usr/bin/env bash
# Load hid_apple from the initramfs on the MacBook, so the internal keyboard
# binds to its real driver on FIRST registration instead of being rebound.
#
# The failure this pre-empts (omarchy-mac docs/apple-silicon-trackpad.md, on an
# M2 MacBook Air): the internal keyboard and trackpad come from dockchannel-hid
# and first bind to hid-generic, then get destroyed and re-created once
# hid_apple / hid_magicmouse finish loading. That churn reshuffles the
# /dev/input/eventN minors exactly while udev, logind and the compositor are
# starting; on an unlucky boot logind's TakeDevice answers ENOENT and libinput
# never retries, so the device is dead for the whole session.
#
# MOST OF THIS IS ALREADY HANDLED ON FEDORA, which is why the drop-in names one
# module rather than two (audited 2026-09-10):
#
#   * dracut-asahi's 91kernel-modules-asahi already instmods dockchannel-hid,
#     apple-dockchannel, spi-hid-apple and friends, so the transport is in the
#     initramfs — mkinitcpio users have to add that themselves.
#   * hid_magicmouse is BUILTIN on the Asahi kernel (modinfo returns
#     "(builtin)"), so the TRACKPAD — the device omarchy actually saw die —
#     cannot lose this race here at all.
#
# That leaves hid_apple, still a module, still loaded late, still able to churn
# the keyboard node. Cheap insurance rather than a fix for an observed bug:
# nothing in this fleet's logs has shown the symptom.
#
# NOT VERIFIED ON THE POSITIVE PATH. This was written on the Mac mini, which
# has no dockchannel at all (its keyboard and trackpad are Bluetooth, where an
# initramfs cannot matter), so the guard below was only ever watched to
# correctly no-op. The MacBook is where it will first do something.
set -uo pipefail

warn() { echo "apple-hid-initramfs: $*" >&2; }

[ "$(uname -m)" = aarch64 ] || exit 0
grep -Faiq 'apple,' /proc/device-tree/compatible 2>/dev/null || exit 0

# The gate is the dockchannel HID transport in the device tree, not "is this a
# Mac": the Mac mini is Apple Silicon too and would otherwise rebuild its
# initramfs for a race it cannot have. Empty on the mini, present on the
# MacBook.
find /proc/device-tree -maxdepth 4 -iname '*dockchannel*' 2>/dev/null | grep -q . || exit 0

# Only worth forcing what is actually a module. A builtin named in
# force_drivers is merely noise, but naming a driver that does not exist at all
# is how a future kernel breaks every rebuild — so ask modinfo, do not assume.
[ "$(modinfo -F filename hid_apple 2>/dev/null)" != "" ] || exit 0
[ "$(modinfo -F filename hid_apple 2>/dev/null)" = "(builtin)" ] && exit 0

conf=/etc/dracut.conf.d/50-apple-hid.conf
[ -f "$conf" ] && exit 0

run_root() {
  if sudo -n true 2>/dev/null; then
    sudo "$@"
  elif [ -t 0 ] && sudo -v 2>/dev/null; then
    sudo "$@"
  elif command -v pkexec >/dev/null 2>&1 && [ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]; then
    echo "apple-hid-initramfs: asking for authorization on screen…" >&2
    timeout 600 pkexec "$@"
  else
    return 1
  fi
}

tmp=$(mktemp)
cat >"$tmp" <<'CONF'
# Bind the internal Apple keyboard to hid_apple on first registration instead
# of letting hid-generic take it and be rebound mid-boot, which reshuffles the
# input event minors while logind is claiming them.
# Managed by ~/.dotfiles (run_after_55-apple-hid-initramfs.sh).
force_drivers+=" hid_apple "
CONF

if ! run_root install -m 0644 "$tmp" "$conf"; then
  rm -f "$tmp"
  warn "could not write $conf"
  exit 0
fi
rm -f "$tmp"

# Only the RUNNING kernel, not --regenerate-all. kernel-install re-runs dracut
# for every kernel installed from here on, so the drop-in reaches future
# initramfses by itself; regenerating every kernel already on disk costs
# minutes on each apply's first run to fix up fallback images that would only
# ever be booted deliberately.
echo "apple-hid-initramfs: rebuilding the initramfs for $(uname -r)"
run_root dracut --force ||
  warn "dracut failed — the drop-in takes effect on the next kernel update"

exit 0
