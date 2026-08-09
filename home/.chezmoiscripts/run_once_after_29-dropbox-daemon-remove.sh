#!/usr/bin/env bash
# Removes the proprietary Dropbox daemon this repo used to install on the NUC
# (run_after_06-dropbox.sh, deleted 2026-08-10). Every machine now reaches
# Dropbox exactly one way — the rclone `Dropbox` remote behind the bar's
# `dropbox` widget — so the daemon, its CLI and its unit go, and all three
# boxes carry the same setup.
#
# WHAT THIS DOES NOT TOUCH: ~/Dropbox. On the NUC that directory holds the
# daemon's synced files, i.e. real data, and deleting it here would be
# deleting the user's files behind a `chezmoi apply`. It is left exactly as
# it is, and the script says so at the end when it finds one — the rclone
# widget mounts over that same path, and `rclone mount` needs an empty
# directory, so moving the old copy aside is a decision to make by hand.
#
# run_once_: this is a migration, not a state to maintain. Once every machine
# has applied it the file can be deleted from the repo.
set -uo pipefail

removed=0

# The unit first — stop before the binary it runs disappears.
unit="$HOME/.config/systemd/user/dropbox.service"
if [ -f "$unit" ]; then
  systemctl --user disable --now dropbox.service >/dev/null 2>&1 || true
  rm -f "$unit"
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  echo "dropbox-remove: dropbox.service disabled and removed"
  removed=1
fi

# The daemon's own supervisor survives its unit: dropboxd forks and the CLI
# can restart it, so kill whatever is still running before deleting the tree.
if pgrep -u "$USER" -x dropbox >/dev/null 2>&1 || pgrep -u "$USER" -f "dropbox-dist" >/dev/null 2>&1; then
  "$HOME/.local/bin/dropbox" stop >/dev/null 2>&1 || true
  pkill -u "$USER" -f "\.dropbox-dist" >/dev/null 2>&1 || true
  sleep 1
fi

if [ -d "$HOME/.dropbox-dist" ]; then
  rm -rf "$HOME/.dropbox-dist"
  echo "dropbox-remove: ~/.dropbox-dist deleted"
  removed=1
fi

# Their python3 control script, installed under the name bin/dropbox-status
# used to probe. Only ours is removed — a distro-packaged /usr/bin/dropbox
# (never installed by this repo) is none of our business.
if [ -f "$HOME/.local/bin/dropbox" ]; then
  rm -f "$HOME/.local/bin/dropbox"
  echo "dropbox-remove: ~/.local/bin/dropbox deleted"
  removed=1
fi

# Daemon state and its account metadata (~/.dropbox/info.json is what the old
# status helper read). Config, not content — the synced files are elsewhere.
if [ -d "$HOME/.dropbox" ]; then
  rm -rf "$HOME/.dropbox"
  echo "dropbox-remove: ~/.dropbox state deleted"
  removed=1
fi

((removed)) || exit 0

if [ -d "$HOME/Dropbox" ] && [ -n "$(ls -A "$HOME/Dropbox" 2>/dev/null)" ]; then
  echo "dropbox-remove: ~/Dropbox still holds the daemon's files and was NOT touched." >&2
  echo "    The bar's dropbox widget mounts the rclone remote at that same path and" >&2
  echo "    rclone needs it empty. When you have checked the contents:" >&2
  echo "        mv ~/Dropbox ~/Dropbox.daemon-backup && mkdir ~/Dropbox" >&2
fi

exit 0
