#!/usr/bin/env bash
# cliamp — seeds ~/.config/cliamp/config.toml on a machine that has none, and
# nothing else. The binary itself comes from run_after_10, the station list is
# a chezmoi symlink, and the UI theme is rendered by bin/theme-apply.
#
# WHY THIS FILE IS NOT CHEZMOI-MANAGED, unlike every other config here:
# cliamp WRITES to config.toml. Pressing `t` in the player calls config.Save
# to persist the theme, and `cliamp setup` rewrites or appends a whole
# [provider] block per service — both through fileutil.WriteFileAtomic, which
# is write-temp-then-rename. In symlink mode that does not write THROUGH the
# symlink, it REPLACES it with a regular file. Managed, this file would mean:
# the repo goes dirty every time the theme changes, `chezmoi apply` silently
# reverts a `cliamp setup` run, and a Spotify or YouTube Music credential ends
# up in a public repo. So the repo seeds it once and then keeps its hands off.
#
# radios.toml is the opposite case and IS managed (home/dot_config/cliamp/):
# cliamp only ever reads it — the `f` favourite key writes radio_favorites.toml
# beside it — so a station added there is a diff you commit, exactly the way
# the old bin/radio's radio-stations file worked.
#
# Guarded on the file's absence, never on its contents: a config edited by
# hand, or filled in by `cliamp setup`, survives every future apply untouched.
set -uo pipefail

config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/cliamp"
config="$config_dir/config.toml"

[ -e "$config" ] && exit 0

mkdir -p "$config_dir" || exit 0

# 0600 to match what cliamp itself writes — this file grows API credentials
# the first time `cliamp setup` runs against Spotify or YouTube Music.
umask 077
cat >"$config" <<'EOF'
# cliamp — https://github.com/bjarneo/cliamp
#
# Seeded by the dotfiles (home/.chezmoiscripts/run_after_40-cliamp.sh) and
# then LEFT ALONE: cliamp rewrites this file itself, so it is deliberately not
# a symlink into the repo. Edit it freely; no apply will revert you.
#
# The station list beside it, radios.toml, IS a repo file — add stations
# there and commit them.

# ---------------------------------------------------------------- appearance

# "qshell" is not a cliamp built-in: bin/theme-apply RENDERS
# ~/.config/cliamp/themes/qshell.toml from whatever desktop theme is active
# and then pokes a running cliamp over its IPC socket, so the player
# re-colours in lock-step with the bar, foot, btop and everything else.
# Setting a built-in name here (dracula, gruvbox, nord, tokyo-night, …) opts
# out of that and pins one palette forever. `t` in the player previews the
# full list; whatever you pick is saved back HERE, over this line.
theme = "qshell"

# Winamp's own bar analyser. `v` cycles all 29, `Ctrl+V` opens the picker with
# a live preview, `V` goes full screen. Options: Bars, BarsDot, Rain,
# BarsOutline, Bricks, Columns, ClassicPeak, Wave, Scatter, Flame, Retro,
# Pulse, Matrix, Binary, Sakura, Firework, Bubbles, Logo, Terrain, Scope,
# Heartbeat, Butterfly, Ascii, Firefly, Mosaic, Sand, Geyser, ClassicLED,
# Stereo, None.
visualizer = "Bars"

# Bar height tracks volume, the way the real Winamp behaved. false decouples
# them, so the spectrum stays readable when you are playing quietly.
vis_volume_linked = true

# false = the player uses the whole terminal. true caps it at 80 columns.
compact = false

# Lowers the UI cadence and forces the visualizer off — the same thing
# `--low-power` does for one session. Worth turning on for a long battery
# flight; `v` still cycles the visualizer back at any time.
low_power = false

# ----------------------------------------------------------------- playback

# Start on the radio browser: 30 000+ radio-browser.info stations plus every
# station in radios.toml. Other values: navidrome, spotify, plex, jellyfin,
# emby, qobuz, soundcloud, netease, yt, youtube, ytmusic. `--provider X`
# overrides for one session, and R/S/P/J/E/Y/C/M/Q/L switch in the player.
provider = "radio"

# dB, not percent (range: volume_min..6). 0 is unity gain.
volume = 0
volume_min = -50

# "off" | "all" | "one" — `r` cycles it, `z` toggles shuffle.
repeat = "off"
shuffle = false

# L+R downmix. `m` toggles.
mono = false

# Where `o` (file browser) opens, and the parent of ~/Music/cliamp, where
# `Ctrl+S` saves a track pulled off YouTube or SoundCloud.
initial_directory = "~/Music"

# Shift+Left / Shift+Right. Plain arrows stay at 5s.
seek_large_step_sec = 30

# --------------------------------------------------------------------- EQ

# "Flat", "Rock", "Pop", "Jazz", "Classical", "Bass Boost", "Treble Boost",
# "Vocal", "Electronic", "Acoustic" — `e` cycles them. Set "Custom" (or leave
# it empty) to use the ten manual gains below instead.
eq_preset = "Flat"

# 70Hz, 180Hz, 320Hz, 600Hz, 1kHz, 3kHz, 6kHz, 12kHz, 14kHz, 16kHz, in dB
# (-12..12). Only read when eq_preset is "Custom" or empty.
eq = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

# ------------------------------------------------------------ audio engine

# Defaults, spelled out so the knobs are visible. cliamp's backend is ALSA,
# bridged to PipeWire by the pipewire-alsa package (packages/manifest.toml) —
# without that bridge this plays in total silence with no error at all.
sample_rate = 44100        # 22050 | 44100 | 48000 | 96000 | 192000
resample_quality = 4       # 1..4, 4 = best sinc interpolation
bit_depth = 16             # 16, or 32 for float PCM on ffmpeg-decoded formats

# Speaker buffer in ms (50..5000). LEFT AT THE DEFAULT deliberately: this is
# also the worst-case lag between hitting pause and the sound actually
# stopping, so it is not free. Raise it to 2000 only if a radio stream on a
# flaky connection keeps dropping out — that is the one case it buys anything.
buffer_ms = 250

# -------------------------------------------------------------- diagnostics

# debug | info | warn | error. The log is ~/.config/cliamp/cliamp.log, and it
# is the first place to look when a YouTube track dies on "waiting for audio
# data: EOF" — the real yt-dlp message lands there.
log_level = "info"

# ---------------------------------------------------------------- providers
#
# Everything below is optional and most of it wants an interactive login, so
# run `cliamp setup` rather than editing by hand: it validates each service
# live and rewrites just that service's block. Any string here can also be
# read from the environment by writing it as "$VAR" or "${VAR}", which is how
# to keep a token out of this file entirely.

# SoundCloud needs no account: enabling it registers the provider, gives
# Ctrl+F search, plays pasted soundcloud.com links through yt-dlp, and seeds
# the browse view with search-backed genre lists (Trending, Hip-Hop,
# Electronic, House, Lo-Fi, Indie, Pop). Add `user = "yourname"` to browse a
# profile's tracks/likes/reposts, and `cookies_from = "chromium"` to reuse a
# signed-in browser session for Go+ tracks.
[soundcloud]
enabled = true

# Spotify needs Premium; sign in by pressing `S` in the player. No client_id
# on purpose: with none, cliamp falls back to the shared librespot client,
# which predates Spotify's 2024-11-27 cutoff and is therefore the ONLY way
# Ctrl+F search works at all — a freshly registered developer app is stuck in
# Development Mode and gets 400 "Invalid limit" on every /v1/search. The cost
# is a globally shared rate limit (occasional 429s when the pool is busy).
# Register your own app and set client_id here if you would rather have a
# private quota and no search. `cliamp spotify reset` clears a stale login.
[spotify]
bitrate = 320              # 96 | 160 | 320

# YouTube / YouTube Music.
#
# CORRECTION 2026-08-18, measured: upstream's docs/youtube-music.md claims this
# "works out of the box with built-in fallback credentials". NOT TRUE of the
# released binary — external/ytmusic/fallback.go declares the credential pool
# and leaves it EMPTY in the public source, so v1.63.2 prints
#
#   YouTube: no credentials available (configure client_id/client_secret ...)
#
# at startup and the `Y` provider browser has nothing to show. Browsing YOUR
# playlists and Liked Music therefore needs your own Google Cloud OAuth client
# (Desktop type, YouTube Data API v3 enabled) — `cliamp setup`, or the two
# keys below.
#
# What needs NO credentials, because it goes through yt-dlp rather than the
# API: Ctrl+F YouTube search, pasting any YouTube URL, `u`, and `music <query>`.
#
# cookies_from is NOT optional for PLAYBACK either, also measured: YouTube 403s
# the audio download for most music content unless yt-dlp presents a signed-in
# session AND is newer than Fedora's build. Both halves are required — neither
# alone works. Full test matrix in the yt-dlp entry of packages/manifest.toml.
# Uncomment cookies_from once a yt-dlp newer than 2026.06.09 is on PATH;
# chromium must be signed in to YouTube.
# [ytmusic]
# client_id = "${YTMUSIC_CLIENT_ID}"
# client_secret = "${YTMUSIC_CLIENT_SECRET}"
# cookies_from = "chromium"
# expand_playlist = true   # false resolves a list= URL as a single video

# NetEase Cloud Music rides a browser session rather than an API key — sign in
# at music.163.com, then `cliamp setup` and pick the browser.
# [netease]
# enabled = true
# cookies_from = "chromium"
# user_id = "..."

# Self-hosted libraries. All four are `cliamp setup` territory; the browse
# view drills artist -> album -> track and Ctrl+F hits the server's own search.
# [navidrome]
# url = "https://music.example.com"
# user = "saiful"
# password = "${NAVIDROME_PASSWORD}"
# [plex]
# url = "http://plex.local:32400"
# token = "${PLEX_TOKEN}"
# [jellyfin]
# url = "https://jelly.example.com"
# token = "${JELLYFIN_TOKEN}"
# [emby]
# url = "https://emby.example.com"
# token = "${EMBY_TOKEN}"
EOF

echo "cliamp: seeded $config"
exit 0
