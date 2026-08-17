#!/usr/bin/env bash
# Cloudflare's own desktop client stays off — the bar's `warp` widget is the
# interface here. The manifest note beside the cloudflare-warp entry has claimed
# "we do not run it" since the port; nothing actually enforced that, and the RPM
# autostarts the applet at every login, so the claim was false until 2026-08-17
# (user decision: no GUI, no tray item).
#
# The package offers three ways back in. Two are files chezmoi can shadow, and
# does — dot_config/autostart and dot_local/share/applications both carry a copy
# of com.cloudflare.WarpTaskbar.desktop, the first with Hidden=true so systemd's
# xdg-autostart generator skips it, the second with NoDisplay=true so the
# launcher does not offer it. This script is the third, which is not a file to
# shadow: warp-desktop-svc.service, a user unit the package's systemd preset
# enables. It is the GTK client's own backend. Stopping it changes nothing about
# warp-cli or warp-svc — verified here on 2026-08-17 by connecting, reading
# `tunnel stats` and disconnecting with it stopped.
#
# Disabled, not masked: masking fails a start with a confusing error, and if a
# machine ever enrolls in a Zero Trust organization the SSO and DEX paths belong
# to the client again. One command puts the whole thing back:
#
#     systemctl --user enable --now warp-desktop-svc
#
# run_after_ rather than run_once_: this is a state to hold, not a migration. A
# `dnf upgrade` of cloudflare-warp re-runs the preset, and `just update-all`
# applies after dnf, so the next apply undoes it again.
set -uo pipefail

# Nothing to do where the package is not installed.
[ -f /usr/lib/systemd/user/warp-desktop-svc.service ] || exit 0

applet=app-com.cloudflare.WarpTaskbar@autostart.service

# The quiet path, which is every apply after the first: nothing enabled, no
# generated applet unit, no applet running.
if [ "$(systemctl --user is-enabled warp-desktop-svc 2>/dev/null)" = "disabled" ] \
  && [ "$(systemctl --user is-active warp-desktop-svc 2>/dev/null)" = "inactive" ] \
  && ! systemctl --user cat "$applet" >/dev/null 2>&1 \
  && ! pgrep -x warp-taskbar >/dev/null 2>&1; then
  exit 0
fi

changed=0

if [ "$(systemctl --user is-enabled warp-desktop-svc 2>/dev/null)" != "disabled" ] \
  || [ "$(systemctl --user is-active warp-desktop-svc 2>/dev/null)" != "inactive" ]; then
  systemctl --user disable --now warp-desktop-svc >/dev/null 2>&1 || true
  echo "warp-no-desktop-client: warp-desktop-svc disabled"
  changed=1
fi

# A session that logged in before the Hidden=true override landed still has the
# generated unit and the applet with it. The generator only re-runs on reload,
# so stop the unit first and let the reload retire it.
if systemctl --user cat "$applet" >/dev/null 2>&1; then
  systemctl --user stop "$applet" >/dev/null 2>&1 || true
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  echo "warp-no-desktop-client: tray applet stopped, autostart unit retired"
  changed=1
fi

# Started by hand from the launcher entry before its shadow existed, so under no
# unit at all. -x, never -f: "warp-taskbar" appears in this script's own command
# line and in the desktop files, and -f would match those.
if pgrep -x warp-taskbar >/dev/null 2>&1; then
  pkill -x warp-taskbar >/dev/null 2>&1 || true
  echo "warp-no-desktop-client: stray warp-taskbar killed"
  changed=1
fi

((changed)) || exit 0
exit 0
