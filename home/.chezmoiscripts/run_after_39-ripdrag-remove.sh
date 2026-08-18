#!/usr/bin/env bash
# Retires the drag-out hand yazi no longer needs: the ripdrag crate and the
# gtk4-devel headers that existed only to compile it.
#
# Why they go (2026-08-18, user call): yazi 26.8.15 does drag-and-drop
# NATIVELY over kitty's OSC 72 protocol, so the <C-n> keybinding that opened a
# floating window of draggable icons is gone from keymap.toml. Nothing else on
# this machine compiles against GTK4 — satty ships a prebuilt binary and links
# the gtk4 RUNTIME, which is installed by the portal chain and stays.
#
# Dropping them from run_after_09 and the manifest stops FUTURE installs; it
# uninstalls nothing, which is what this script is for. run_after_, not
# run_once_after_: the two guards below are the state, so it costs a `test` and
# an `rpm -q` per apply and disarms itself once both are gone. A run_once_
# script that skipped for lack of sudo — every background apply — would be
# recorded as done and never run again (the trap run_before_00 documents).
set -uo pipefail

# The crate first: no sudo, so it lands on every apply including background
# ones. cargo owns ~/.cargo/bin, hence `cargo uninstall` rather than rm.
if [ -x "$HOME/.cargo/bin/ripdrag" ]; then
  if cargo uninstall ripdrag >/dev/null 2>&1; then
    echo "ripdrag-remove: uninstalled the ripdrag crate"
  else
    echo "ripdrag-remove: cargo uninstall ripdrag failed" >&2
  fi
fi

rpm -q gtk4-devel >/dev/null 2>&1 || exit 0

# Background applies have no controlling terminal, so sudo cannot prompt: skip
# loudly and let the next terminal apply finish the job. Same policy as
# run_before_00 and run_after_38.
if ! sudo -v 2>/dev/null; then
  echo "ripdrag-remove: sudo unavailable — rerun 'chezmoi apply' in a terminal to drop gtk4-devel" >&2
  exit 0
fi

# --no-autoremove is deliberate: gtk4-devel drags in a long tail of -devel
# packages (pango, cairo, gdk-pixbuf, graphene…), and letting dnf decide which
# of those are now "unused" on a machine that builds Qt and Rust GUIs is how a
# cleanup turns into a broken toolchain. Only the package we named goes.
if sudo dnf remove -y --no-autoremove gtk4-devel; then
  echo "ripdrag-remove: removed gtk4-devel (the gtk4 runtime is untouched)"
else
  echo "ripdrag-remove: dnf remove gtk4-devel failed" >&2
fi

exit 0
