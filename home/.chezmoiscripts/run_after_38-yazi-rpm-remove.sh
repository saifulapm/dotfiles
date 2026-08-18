#!/usr/bin/env bash
# Retires the COPR-packaged yazi (lihaohong/yazi). Upstream's own release
# binary took the job over on 2026-08-18 — see run_after_10: the copr sat at
# 26.5.6 while upstream had shipped 26.8.15, whose headline feature is native
# drag-and-drop, and one person's rebuild cadence is not what the file manager
# on a daily driver should wait on.
#
# Ordering: run_after_10 installs ~/.local/bin/yazi first (10 sorts before 38),
# and this refuses to touch the rpm until that file exists — a failed download
# must never leave the machine with no file manager at all.
#
# run_after_, not run_once_after_: `rpm -q yazi` IS the guard, so this costs
# one rpm lookup per apply and disarms itself the moment the package is gone.
# A run_once_ script that skipped for lack of sudo — which every background
# apply does — would be recorded as done and never run again, the trap
# run_before_00 documents at its top.
set -uo pipefail

rpm -q yazi >/dev/null 2>&1 || exit 0

if [ ! -x "$HOME/.local/bin/yazi" ]; then
  echo "yazi-rpm-remove: ~/.local/bin/yazi not installed yet — keeping the rpm" >&2
  exit 0
fi

# Background applies (agents, keybinds, timers) have no controlling terminal,
# so sudo cannot prompt at all: skip loudly, same policy as run_before_00.
if ! sudo -v 2>/dev/null; then
  echo "yazi-rpm-remove: sudo unavailable — rerun 'chezmoi apply' in a terminal to drop the old rpm" >&2
  exit 0
fi

if sudo dnf remove -y yazi; then
  echo "yazi-rpm-remove: removed the COPR yazi rpm (/usr/bin/yazi, /usr/bin/ya)"
else
  echo "yazi-rpm-remove: dnf remove yazi failed" >&2
  exit 0
fi

# The repo file too — left enabled it keeps refreshing metadata for a package
# nothing installs any more. `remove` deletes the .repo file; `disable` only
# flips enabled=0 and is the fallback.
#
# The copr list is captured, not piped into `grep -q`: under `set -o pipefail`
# grep's early exit SIGPIPEs dnf and the pipeline reports failure on a MATCH,
# a bug this repo has already paid for twice.
coprs="$(dnf copr list 2>/dev/null || true)"
case "$coprs" in
  *lihaohong/yazi*)
    sudo dnf copr remove -y lihaohong/yazi \
      || sudo dnf copr disable -y lihaohong/yazi \
      || echo "yazi-rpm-remove: could not drop copr lihaohong/yazi — remove it by hand" >&2
    ;;
esac

exit 0
