#!/usr/bin/env bash
# Keep the qt6 hold correct on every apply, and say so when the shell is
# broken. The decision, the reasoning and the self-lifting live in
# bin/qt6-hold; this is only the hook that makes a plain `chezmoi apply`
# behave like `just update-all` (which calls the same helper around its dnf
# step, where it can actually gate the transaction).
#
# Silent and root-free on a correct machine: qt6-hold only touches /etc when
# the state is wrong, so this adds no password prompt to an ordinary apply.
# The repair itself (bin/qshell-rebuild) installs the Qt devel stack and
# takes minutes, so it is never run from here — it is printed as a command.
set -uo pipefail

command -v qt6-hold >/dev/null 2>&1 || exit 0
rpm -q quickshell >/dev/null 2>&1 || exit 0

qt6-hold || echo "qshell-qt: could not set the qt6 hold (rerun 'chezmoi apply' in a terminal)" >&2

if ! qt6-hold --verify 2>/dev/null; then
  echo "qshell-qt: the shell cannot start against $(rpm -q qt6-qtbase) — run 'qshell-rebuild' to fix it" >&2
fi

exit 0
