#!/usr/bin/env bash
# Retires the night light — sunsetr, its unit, its config and the state file
# the old wlsunset probe left behind. Replaces run_after_44-sunsetr.sh, which
# seeded all of it.
#
# WHY IT GOES (2026-09-04, measured on the MacBook rather than inferred):
# the feature never worked on this hardware and could not have. niri's own
# log says it at DEBUG on every start —
#
#     couldn't get gamma properties: missing GAMMA_LUT property
#     couldn't reset gamma: setting gamma is not supported
#
# — which is the two-step fallback in niri's tty backend giving up. The Apple
# panel exposes no GAMMA_LUT atomic property, so niri drops to the legacy
# CRTC path, and there `gamma_length` is 0, which trips its `ensure!`. That
# makes `get_gamma_size` return 0, which niri's GammaControlHandler maps to
# None, which makes zwlr_gamma_control_manager_v1.get_gamma_control answer
# `failed` before a single ramp is sent. sunsetr never checks for that event,
# so it logged clean sunrise transitions for 13 hours against a dead object.
#
# The cost of that was not zero: the daemon held ~50% of a core and 130 MB
# continuously (6h11m CPU in 13h uptime, measured), which on a laptop is the
# opposite of what a night light is worth.
#
# The mini and the NUC drive external monitors that probably DO carry a gamma
# LUT, so this is a fleet-wide removal of a feature that worked on some of the
# fleet — a deliberate call (user, 2026-09-04) rather than an oversight. If it
# ever comes back it comes back gated on a real gamma probe, not on whether a
# daemon happens to be running.
#
# run_after_, not run_once_after_, for the reason run_after_39 spells out: a
# run_once_ script is recorded as done the first time it runs, and the other
# two machines have not applied this yet. The guards below ARE the state, so
# this costs a handful of `test`s per apply and disarms itself once they pass.
set -uo pipefail

removed=0

# The unit first, and stop before disable: a running sunsetr holds the gamma
# state it applied, and on a machine where the ramps DID land, leaving it
# running with no unit file behind it would strand a warm screen with nothing
# left to reset it.
if systemctl --user is-active --quiet sunsetr.service 2>/dev/null; then
  systemctl --user stop sunsetr.service 2>/dev/null \
    && echo "sunsetr-remove: stopped sunsetr.service"
fi

# `systemctl --user disable` is NOT the tool here, and finding that out cost a
# run. chezmoi deletes the source file earlier in the same apply that runs this
# script, so by the time we get here ~/.config/systemd/user/sunsetr.service is
# already a DANGLING symlink and systemd answers `not-found` to is-enabled —
# which means disable is skipped and the enablement link under
# graphical-session.target.wants/ is orphaned with nothing left to remove it.
# So sweep by path instead: the unit symlink and every *.wants/ entry pointing
# at it. -L without -e is the precise signature of "chezmoi managed this and
# the source is gone"; a real file at any of these paths is somebody's
# deliberate replacement and is left exactly where it is.
units_dir="$HOME/.config/systemd/user"
while IFS= read -r stale; do
  [ -n "$stale" ] || continue
  if [ -L "$stale" ] && [ ! -e "$stale" ]; then
    rm -f "$stale" && removed=$((removed + 1))
  fi
done < <(find "$units_dir" -name 'sunsetr.service' -type l 2>/dev/null)

# Only when something actually went, so a settled machine costs nothing.
if [ "$removed" -gt 0 ]; then
  systemctl --user daemon-reload 2>/dev/null \
    && echo "sunsetr-remove: dropped the unit and its enablement link"
fi

# The vicinae script is COPIED, not symlinked (vicinae reads the scripts dir
# directly), so the dangling-symlink test above would never fire for it.
# Guarded on the shebang line the repo wrote, so a hand-written replacement
# at the same path survives.
vicinae_script="$HOME/.local/share/vicinae/scripts/toggle-nightlight.sh"
if [ -f "$vicinae_script" ] && grep -q '@vicinae.title Toggle Night Light' "$vicinae_script" 2>/dev/null; then
  rm -f "$vicinae_script" && removed=$((removed + 1))
fi

# sunsetr's own config tree. Never chezmoi-managed — run_after_44 seeded it
# once and then kept its hands off precisely because sunsetr rewrites it — so
# nothing else will ever clean it up. geo.toml holds a home location, which is
# the one file here worth removing rather than leaving to rot.
if [ -d "$HOME/.config/sunsetr" ]; then
  rm -rf "$HOME/.config/sunsetr" && removed=$((removed + 1))
fi

# The wlsunset-era discovery note, seeded 2026-08-07. It recorded exactly the
# fact that finally retired the feature, and has nothing left to gate.
if [ -f "$HOME/.local/state/qshell/nightlight-nogamma" ]; then
  rm -f "$HOME/.local/state/qshell/nightlight-nogamma" && removed=$((removed + 1))
fi

# The crate last: no sudo, so it lands on every apply including background
# ones. cargo owns ~/.cargo/bin, hence `cargo uninstall` rather than rm.
if [ -x "$HOME/.cargo/bin/sunsetr" ]; then
  if cargo uninstall sunsetr >/dev/null 2>&1; then
    echo "sunsetr-remove: uninstalled the sunsetr crate"
  else
    echo "sunsetr-remove: cargo uninstall sunsetr failed" >&2
  fi
fi

[ "$removed" -gt 0 ] && echo "sunsetr-remove: cleared $removed leftover(s) from the night-light stack"

exit 0
