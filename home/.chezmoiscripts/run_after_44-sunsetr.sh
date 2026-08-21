#!/usr/bin/env bash
# sunsetr — seeds ~/.config/sunsetr/ (the config and the two forcing presets)
# on a machine that has none, and enables the user unit. The binary itself
# comes from run_after_09-cargo-tools.sh; bin/nightlight is the CLI face and
# the bar's nightlight widget is the graphical one.
#
# WHY THE CONFIG IS NOT CHEZMOI-MANAGED, unlike most config here: sunsetr
# WRITES to sunsetr.toml. `sunsetr set night_temp=3000` — which the panel's
# temperature controls and any keybinding use — rewrites the file in place,
# as does `sunsetr geo` after an interactive city pick. This is the cliamp
# situation exactly (run_after_40): managed, the repo would go dirty every
# time the temperature was nudged, and `chezmoi apply` would silently revert
# whatever was set. So the repo seeds it once and then keeps its hands off.
#
# Guarded on each file's absence, never on its contents: a config edited by
# hand survives every future apply untouched.
#
# COORDINATES GO IN geo.toml, NOT IN THE CONFIG, and they are resolved per
# machine rather than written here. Two reasons, one of them a correction.
#
# The correction: geo mode does NOT fall back to the system timezone at
# runtime. A coordinate-free geo config makes sunsetr exit 1 with "Geo mode
# requires coordinates but none are configured" — measured 2026-08-21, after
# a first reading of `sunsetr -b` mistook its "Background process started"
# for a successful start when the daemon behind it was already failing. The
# timezone lookup happens only when sunsetr GENERATES a config, which is what
# resolve_coordinates below borrows: it runs sunsetr once against a scratch
# directory purely to have it write the coordinates for this machine's
# timezone, and reads them back out.
#
# The reason geo.toml rather than the config: upstream made that file exactly
# for this, "gitignored for privacy" in its own words (`sunsetr help geo`),
# and this repo is PUBLIC. A home location is not something to commit. Per
# machine it also means the NUC and the two laptops each aim themselves, and
# `sunsetr geo` can re-pick a city on one of them without touching the others
# or dirtying the repo.
set -uo pipefail

config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/sunsetr"

# 0600 to match what sunsetr itself writes when it generates a default config.
umask 077

seed_config() {
  local config="$config_dir/sunsetr.toml"
  [ -e "$config" ] && return 0
  mkdir -p "$config_dir" || return 0

  cat >"$config" <<'EOF'
# sunsetr — https://psi4j.github.io/sunsetr/configuration/
#
# Seeded by the dotfiles (home/.chezmoiscripts/run_after_44-sunsetr.sh) and
# then LEFT ALONE: sunsetr rewrites this file itself on `sunsetr set` and
# `sunsetr geo`, so it is deliberately not a symlink into the repo. Edit it
# freely; no apply will revert you.
#
# The bar's nightlight widget and bin/nightlight drive the two presets in
# presets/ rather than editing this file, so forcing day or night for an
# evening leaves everything here alone.

#[Backend]
# "auto" detects the compositor. On niri that resolves to the universal
# Wayland gamma path (wlr-gamma-control), and sunsetr says so on startup:
# "Starting sunsetr via niri compositor". Do not pin this to "hyprland" —
# that backend drives hyprsunset, which is not installed and not wanted.
backend = "auto"

# "geo" computes sunrise and sunset for the actual location, every day, so
# the schedule tracks the season instead of drifting away from it. The other
# modes (static, center, finish_by, start_at) are for pinning fixed clock
# times — see the sunset/sunrise keys below, which only "geo" ignores.
transition_mode = "geo"

#[Geolocation]
# DELIBERATELY ABSENT HERE — the coordinates live in geo.toml beside this
# file, which upstream keeps out of version control on purpose and which this
# repo (public) therefore never carries. run_after_44-sunsetr.sh writes it
# once per machine from the system timezone.
#
# `sunsetr geo` opens a city picker and, because geo.toml exists, writes the
# choice THERE rather than here — so re-aiming a machine never dirties this
# file. Setting latitude/longitude here would override it; don't.

#[Smoothing]
# Fade rather than step, including at startup and shutdown — a login that
# snapped straight to 3300 K read as a display fault the first time.
smoothing = true
startup_duration = 0.5
shutdown_duration = 0.5
adaptive_interval = 1

#[Time-based config]
# Temperature in kelvin (1000-20000), gamma as a percentage (10-200).
# 6500 K is the neutral daylight point every panel here is calibrated to, so
# day is "no filter at all" rather than a mild one. 3300 K at night is
# upstream's default and roughly a halogen bulb; 2700 K is candlelight and
# noticeably orange, 4500 K is barely there. The gamma drop at night is
# small on purpose — it dims without crushing the dark end of a photo.
night_temp = 3300
day_temp = 6500
night_gamma = 90
day_gamma = 100
update_interval = "auto"

#[Static config]
# Only read in static mode. The presets in presets/day and presets/night are
# what actually use these — see their own files.
static_temp = 6500
static_gamma = 100

#[Manual transitions]
# Ignored in geo mode. Kept so switching transition_mode to "static",
# "center", "finish_by" or "start_at" has something sensible to land on.
sunset = "19:00:00"
sunrise = "06:00:00"
transition_duration = 45
EOF

  echo "sunsetr: seeded $config"
}

# The two forcing presets. A preset is a partial config: every field it omits
# falls back to the base file above, so these carry three lines each. Applying
# one pins the display until `sunsetr preset default` hands the schedule back
# — which is exactly the Auto / Day / Night triple the bar widget draws, and
# what `nightlight day|night|auto` sets.
seed_preset() {
  local name="$1" temp="$2" gamma="$3" note="$4"
  local dir="$config_dir/presets/$name"
  local file="$dir/sunsetr.toml"
  [ -e "$file" ] && return 0
  mkdir -p "$dir" || return 0

  cat >"$file" <<EOF
# sunsetr preset "$name" — seeded by the dotfiles
# (home/.chezmoiscripts/run_after_44-sunsetr.sh), then left alone.
#
# $note
#
# Apply:   sunsetr preset $name    (or: nightlight $name)
# Release: sunsetr preset default  (or: nightlight auto)
transition_mode = "static"
static_temp = $temp
static_gamma = $gamma
EOF

  echo "sunsetr: seeded $file"
}

# Resolve this machine's coordinates ONCE, into geo.toml.
#
# sunsetr has no "print the coordinates for my timezone" command, and its
# timezone->coordinate table is a Rust crate (tzf-dist) with no shell
# equivalent worth reimplementing. What it does have is config generation: a
# run against a directory with no config writes one, and the geolocation it
# writes is this machine's timezone resolved. So borrow that — point it at a
# scratch directory, wait for the file, read the two numbers, throw the
# scratch away.
#
# It is killed as soon as the file appears, which is before it finishes
# initializing the gamma backend, so this does not visibly tint the display.
# Once per machine, on the apply that first installs sunsetr.
resolve_coordinates() {
  local geo="$config_dir/geo.toml"
  [ -e "$geo" ] && return 0
  command -v sunsetr >/dev/null 2>&1 || {
    echo "sunsetr: binary missing (cargo pass has not run yet?) — geo.toml deferred to the next apply" >&2
    return 0
  }
  # A running instance holds the single-instance lock, so the scratch run
  # would never get far enough to write anything. It cannot be running
  # without coordinates, so this state means geo.toml was removed by hand.
  if systemctl --user -q is-active sunsetr.service 2>/dev/null; then
    echo "sunsetr: service is running — not re-resolving coordinates; run 'sunsetr geo' to change location" >&2
    return 0
  fi

  local scratch; scratch="$(mktemp -d)" || return 0
  sunsetr -c "$scratch" >/dev/null 2>&1 &
  local pid=$!
  # ~5 s of 0.1 s polls. Generation is the first thing it does; this is a
  # ceiling for a cold page cache, not an expected wait.
  local i
  for i in $(seq 50); do
    [ -s "$scratch/sunsetr.toml" ] && break
    sleep 0.1
  done
  kill -TERM "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null

  local lat lon
  lat="$(grep -E '^[[:space:]]*latitude[[:space:]]*=' "$scratch/sunsetr.toml" 2>/dev/null | head -1 | sed 's/.*=[[:space:]]*//')"
  lon="$(grep -E '^[[:space:]]*longitude[[:space:]]*=' "$scratch/sunsetr.toml" 2>/dev/null | head -1 | sed 's/.*=[[:space:]]*//')"
  rm -rf "$scratch"

  # Both must be numeric. Anything else and we write nothing: an empty or
  # half-written geo.toml would be worse than none, because the absence is
  # what makes the next apply try again.
  if ! [[ $lat =~ ^-?[0-9]+(\.[0-9]+)?$ && $lon =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
    echo "sunsetr: could not resolve coordinates from the system timezone — run 'sunsetr geo' to pick a city" >&2
    return 0
  fi

  mkdir -p "$config_dir" || return 0
  cat >"$geo" <<EOF
# sunsetr geolocation — NOT a repo file, and deliberately so: this is the one
# thing in ~/.config/sunsetr that says where you are, and github.com/saifulapm/
# dotfiles is public. Upstream reads geo.toml in preference to the coordinates
# in sunsetr.toml precisely so it can be gitignored (see 'sunsetr help geo').
#
# Written once by home/.chezmoiscripts/run_after_44-sunsetr.sh, from this
# machine's system timezone ($(timedatectl show -p Timezone --value 2>/dev/null || echo unknown)).
# Re-pick a city any time with 'sunsetr geo'; it rewrites this file, not the
# config. Delete it and the next apply resolves the timezone again.
latitude = $lat
longitude = $lon
EOF
  echo "sunsetr: resolved coordinates to $lat, $lon -> $geo"
}

seed_config
resolve_coordinates
seed_preset day 6500 100 \
  "Holds the display neutral whatever the clock says — the override for editing photos, checking a design against a client's screen, or a late night that should not look like one."
seed_preset night 3300 90 \
  "Holds the filter on whatever the clock says — the override for a dark room in the afternoon, or a flight."

# Enable always; start only inside a graphical session (the unit is
# Requisite=graphical-session.target — run_after_34-dshift.sh's split).
state="$(systemctl --user is-system-running 2>/dev/null || true)"
if [ "$state" = "running" ] || [ "$state" = "degraded" ]; then
  systemctl --user daemon-reload || true
  systemctl --user enable sunsetr.service 2>/dev/null \
    || echo "sunsetr: enable sunsetr.service failed" >&2
  if systemctl --user -q is-active graphical-session.target; then
    # restart rather than start: a seeded-config change or a freshly built
    # binary should take effect on this apply, not at the next login.
    systemctl --user restart sunsetr.service 2>/dev/null \
      || echo "sunsetr: start failed — check systemctl --user status sunsetr" >&2
  fi
  echo "sunsetr: sunsetr.service enabled"
fi

exit 0
