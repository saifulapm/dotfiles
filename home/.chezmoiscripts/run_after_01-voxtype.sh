#!/usr/bin/env bash
# voxtype — the push-to-talk dictation daemon behind Alt-Alt and the
# bar's dictation indicator. It was this desktop's one hand install, on the
# grounds that voxtype.io/install.sh is a 404 (still true, rechecked
# 2026-08-11) — but upstream does publish bare per-arch release binaries for
# BOTH our arches, so the install is scriptable exactly like satty's. The NUC
# is what proved it had to be: a fresh machine printed the "voxtype not
# installed" nag on every single apply and dictation stayed inert until
# someone downloaded a binary by hand.
#
# ORDERING: 01, so this lands before run_after_02-user-timers.sh. `voxtype
# setup systemd` enables AND starts the daemon (verified 2026-08-11), and 02
# is what owns the unit's steady state — disabled. Installing later in the
# sequence would leave a fresh machine running the always-on 486 MB daemon
# until the next apply.
#
# VERSION PIN: v1.0.1, the current stable. The old note here said 0.7.5 was
# "the newest release with linux assets at all" — true when it was written,
# wrong since 1.0.0 (2026-08-29), which ships every linux arch we use. 1.x is
# also where the machine-readable surface arrived (`config schema --json`,
# `config get/set`, `info accel|models|engines --json`), and the bar's
# dictation panel is built entirely on it, so this pin is a floor for the shell
# and not just a preference.
#
# 1.1.0 is deliberately not taken: it has been in rc since 2026-09-01 and its
# headline features (OSD style packages, OpenVINO NPU) are for hardware and a
# frontend we do not use.
#
# THE PIN NOW WINS, which is a change: this used to install only a MISSING
# binary so a hand-upgrade could not be stomped. With the shell depending on a
# 1.x CLI, "whatever happens to be on disk" is not a version anything can rely
# on, so a mismatch reinstalls. `voxtype check-update` still works; it just
# gets reverted on the next apply, and the way to keep an upgrade is to bump
# this line.
#
# Failures warn instead of aborting, like the other fetch scripts — a flaky
# network must not stop the rest of a fresh-machine apply; dictation just
# stays inert until the next one.
set -uo pipefail

VERSION="1.0.1"

# small.en rather than upstream's base.en default: benchmarked on the M2
# 2026-08-08 and kept for technical proper nouns (base.en wrote "restot
# Postger SQL" where small.en wrote "restock PostgreSQL"). It is a 466 MB
# download against base.en's 141 MB — the one knob here worth turning on a
# slow link. Full numbers, including why it is 3.5x slower, in
# packages/manifest.toml.
MODEL="small.en"

# The guard below is a PATH lookup on a binary this script installs to
# ~/.local/bin, which bash sessions do NOT have on PATH (only fish adds it) —
# without this export a TTY or timer apply re-downloads it every run.
export PATH="$HOME/.local/bin:$PATH"

warn() { echo "voxtype: $*" >&2; }

# Upstream builds whisper.cpp per CPU feature level and ships no baseline
# x86_64 binary, so a pre-AVX2 x86 box gets a warn here rather than a SIGILL
# on first dictation. aarch64 has exactly one CPU build, which is all the
# Apple boxes can use anyway (`voxtype info variants` reports AVX2=false and
# no GPU there). The -onnx variants are deliberately not used: they swap the
# transcription engine to Parakeet, which is a model/accuracy decision rather
# than a packaging one, and nothing here is set up for it.
case "$(uname -m)" in
aarch64) asset="voxtype-$VERSION-linux-aarch64-cpu" ;;
x86_64)
  if grep -qw avx512f /proc/cpuinfo; then
    asset="voxtype-$VERSION-linux-x86_64-avx512"
  elif grep -qw avx2 /proc/cpuinfo; then
    asset="voxtype-$VERSION-linux-x86_64-avx2"
  else
    warn "upstream ships no pre-AVX2 x86_64 build — dictation stays inert here"
    exit 0
  fi
  ;;
*)
  warn "no upstream binary for $(uname -m) — dictation stays inert here"
  exit 0
  ;;
esac

# The sidecar that feeds the bar's dictation OSD its waveform. The daemon
# broadcasts 16-byte audio frames at 100 Hz on a unix socket, and quickshell
# cannot read a unix socket — this bridge is upstream's answer, one NDJSON line
# per frame on stdout for a QML Process to parse. Arch-only in its name: there
# is no CPU-feature split for it the way there is for the whisper binary.
bridge="voxtype-$VERSION-linux-$(uname -m)-audio-bridge"

base="https://github.com/peteonrails/voxtype/releases/download/v$VERSION"

# Version-compared rather than presence-checked, so bumping VERSION above is
# what performs an upgrade. `voxtype --version` prints "voxtype 1.0.1"; an
# absent binary leaves this empty, which is a mismatch and installs.
have=""
command -v voxtype >/dev/null 2>&1 && have="$(voxtype --version 2>/dev/null | awk '{print $2}')"

if [ "$have" != "$VERSION" ]; then
  tmp="$(mktemp -d)"

  # Checksummed because upstream publishes SHA256SUMS.txt next to the assets
  # and these are bare binaries, not packages with their own verification. An
  # empty `want` (asset renamed upstream) fails the comparison rather than
  # matching a truncated download.
  fetch() { # <asset> <dest>
    local want
    curl -fsSL -o "$tmp/$1" "$base/$1" || return 1
    want="$(awk -v a="$1" '$2 == a { print $1 }' "$tmp/SHA256SUMS.txt")"
    [ -n "$want" ] || return 1
    [ "$want" = "$(sha256sum "$tmp/$1" | cut -d' ' -f1)" ] || return 1
    # Install beside the target and RENAME over it, rather than writing the
    # target directly: the daemon may be running, and writing a busy
    # executable fails with ETXTBSY (hit on the first upgrade test — the
    # script reported "download or checksum" for what was neither). A rename
    # is atomic and leaves the running process on its old inode until it
    # exits, which is exactly the semantics wanted for a live upgrade.
    install -Dm755 "$tmp/$1" "$2.new" && mv -f "$2.new" "$2"
  }

  if curl -fsSL -o "$tmp/SHA256SUMS.txt" "$base/SHA256SUMS.txt" &&
    fetch "$asset" "$HOME/.local/bin/voxtype"; then
    echo "voxtype: installed $VERSION ($asset) to ~/.local/bin${have:+, was $have}"
    # A missing bridge costs the waveform and nothing else — the OSD falls back
    # to a state card and dictation itself never touches it — so this warns
    # rather than counting as a failed install.
    fetch "$bridge" "$HOME/.local/bin/voxtype-audio-bridge" ||
      warn "audio bridge download failed — the dictation OSD will draw no waveform"

    # The rename above left any RUNNING daemon on the old inode, still serving
    # the previous version — `config schema --json` has a whole
    # `daemon_version_differs` field for that state, which says how normal it
    # is. try-restart rather than restart: the daemon is normally stopped, and
    # starting one here would park the model in RAM for nothing. Skipped
    # mid-dictation for the reason everything else here is — restarting then
    # throws away the utterance being spoken.
    if [ "$(cat "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/voxtype/state" 2>/dev/null)" != "recording" ]; then
      systemctl --user try-restart voxtype.service >/dev/null 2>&1 || true
    fi
  else
    warn "install failed (download or checksum) — dictation stays inert until the next apply"
  fi
  rm -rf "$tmp"
fi

# Everything below needs the binary; a failed download above already warned.
command -v voxtype >/dev/null 2>&1 || exit 0

# The model is a separate ~466 MB download that lives outside this repo. The
# guard is the model FILE, not `voxtype setup check`, because `voxtype setup
# --download` also REWRITES config.toml's model= (verified 2026-08-11) — a
# machine where the model was switched by hand must not have that choice
# stomped on every apply.
if [ ! -e "$HOME/.local/share/voxtype/models/ggml-$MODEL.bin" ]; then
  if voxtype setup --download --model "$MODEL" --no-post-install </dev/null; then
    echo "voxtype: model $MODEL downloaded and set as default"
  else
    warn "model download failed — the daemon would start but transcribe nothing"
  fi
fi

# `voxtype setup systemd` writes ~/.config/systemd/user/voxtype.service, which
# is NOT chezmoi-managed (a restore has to re-run the command — that is what
# this block is). It also ENABLES it into graphical-session.target.wants and
# STARTS it, both verified 2026-08-11, and both are wrong here: the daemon
# preloads the whisper model, so an always-on one parks 486 MB doing nothing
# on machines with ~1.5 GB free. bin/voxtype-toggle starts it on the keybind
# in 0.17 s instead and voxtype-idle-stop.timer reaps it after ~90 s idle.
#
# Undoing that here is not a second owner of the unit's state: 02 owns the
# steady state and re-disables anything that flips it back on a later apply.
# This is the one moment 02 cannot cover — it deliberately never STOPS a
# running daemon (the idle timer does, because it checks for a dictation in
# progress first), and the daemon being stopped here is the one `setup
# systemd` started seconds ago, since this branch only runs when there was no
# unit on the machine at all.
#
# Tested on the file rather than the exit status: a TTY-only apply can fail
# the `start` half while still having written the unit and reloaded systemd,
# which is a success for our purposes.
if [ ! -f "$HOME/.config/systemd/user/voxtype.service" ]; then
  voxtype setup systemd </dev/null >/dev/null 2>&1
  if [ -f "$HOME/.config/systemd/user/voxtype.service" ]; then
    systemctl --user disable voxtype.service >/dev/null 2>&1 \
      || warn "disable after setup failed — check systemctl --user status voxtype.service"
    systemctl --user stop voxtype.service >/dev/null 2>&1 || true
    echo "voxtype: systemd unit written, left disabled (on demand via bin/voxtype-toggle)"
  else
    warn "'voxtype setup systemd' failed — Alt-Alt cannot start the daemon"
  fi
fi

# The dictation log the bar's panel reads: history, and the per-day talk-time
# the chart plots. bin/voxtype-capture is a passthrough filter — voxtype hands
# it the transcript on stdin and types whatever comes back — so wiring it here
# is what turns dictation into something with a memory. Everything it writes
# stays 0600 on this machine; the reasoning is in the script.
#
# Set through `voxtype config set` rather than by editing config.toml: that
# path is atomic, validating, and comment-preserving, and config.toml is not
# chezmoi-managed precisely because voxtype rewrites it itself.
#
# Guarded on the current value so a re-apply is silent. Not guarded on "unset",
# because a hand-set hook pointing somewhere else is exactly the drift this
# should correct.
# Voice activity detection: reject a recording with no speech in it BEFORE it
# reaches whisper. Not a nicety — with VAD off, whisper does not return an
# empty string for silence, it hallucinates. Measured here on a 10 s silent
# take (2026-09-04):
#
#   VAD off   14.5 s wall, 16.8 s of CPU, typed "Thank you." into the window
#   VAD on    10.2 s wall,  0.25 s of CPU, typed nothing
#
# So it is worth 67x the CPU and the whole class of wrong paste, and it
# matters more now that Alt-Alt makes an accidental start a one-hand slip.
# Guarded on the model FILE, like the whisper model above: 868 KB, and
# `setup vad` re-downloads unconditionally.
if [ ! -e "$HOME/.local/share/voxtype/models/ggml-silero-vad.bin" ]; then
  voxtype setup vad </dev/null >/dev/null 2>&1 \
    || warn "Silero VAD download failed — falling back to the built-in energy VAD"
fi

# backend deliberately left at `auto`, which picks Silero for whisper and the
# model-free energy detector for the ONNX engines. Writing "whisper" here
# would be a second place to remember if the engine ever changes.
if [ "$(voxtype config get vad.enabled 2>/dev/null)" != "true" ]; then
  if voxtype config set vad.enabled true >/dev/null 2>&1; then
    echo "voxtype: voice activity detection enabled"
    systemctl --user try-restart voxtype.service >/dev/null 2>&1 || true
  else
    warn "could not enable VAD — silent recordings will be transcribed as hallucinations"
  fi
fi

# ------------------------------------------------------------- preferences
# Settings that are opinions rather than correctness, so unlike the hook above
# they are written ONCE and never corrected. The test is the schema's
# `file_value`: null means the key is absent from config.toml entirely, and
# anything else — including a value equal to what we would write — means
# somebody chose it. `config get` cannot answer this, because it reports the
# RESOLVED value and an unset bool is indistinguishable from an explicit false.
schema="$(voxtype config schema --json 2>/dev/null || true)"

set_preference() { # <key> <value> <what it does>
  local state
  state="$(printf '%s' "$schema" |
    jq -r --arg k "$1" '.keys[] | select(.key==$k) | (if .file_value == null then "unset" else "set" end)' 2>/dev/null)"
  [ "$state" = "unset" ] || return 0
  if voxtype config set "$1" "$2" >/dev/null 2>&1; then
    echo "voxtype: $3"
    systemctl --user try-restart voxtype.service >/dev/null 2>&1 || true
  fi
}

# Whisper conditions its decoding on this text, so naming the vocabulary that
# actually gets dictated here biases it toward the right spelling. This is the
# documented fix for the exact failure recorded in packages/manifest.toml —
# base.en heard "restock PostgreSQL" as "restot Postger SQL". Free at runtime:
# it is prompt tokens, not a second pass.
set_preference whisper.initial_prompt \
  "Technical discussion about Laravel, PHP, React, TypeScript, pnpm, PostgreSQL, Redis, Fedora Asahi, niri, quickshell, chezmoi, Emacs, Tailscale, systemd, and git." \
  "vocabulary hint set for whisper"

# Short synthesised tones — nothing to download, the themes are generated in
# code. The one that matters is Cancelled, which is what a VAD rejection plays:
# without it a rejected dictation is completely silent and indistinguishable
# from one that never recorded, which is the single most confusing thing about
# having VAD on.
set_preference audio.feedback.enabled true \
  "audio feedback on (a rejected dictation now makes a sound)"

# Enter submits in Claude Code, Slack, Discord and most chat inputs, so a
# dictated multi-line message fires off at the first line break. Shift+Enter
# keeps it in the box.
set_preference output.shift_enter_newlines true \
  "newlines dictate as Shift+Enter"

# Long-form continuous transcription, off by default and useless until asked
# for — `voxtype meeting start` is what begins one, and nothing records
# implicitly. Turning it on here just makes the subcommand and the bar panel's
# meeting controls work. `meeting.audio.loopback_device` already defaults to
# "auto", which captures the far side of a call as well as the microphone.
set_preference meeting.enabled true \
  "meeting mode available (voxtype meeting start, or the bar panel)"

hook="$HOME/.dotfiles/bin/voxtype-capture"
if [ -x "$hook" ] && [ "$(voxtype config get output.post_process.command 2>/dev/null)" != "$hook" ]; then
  if voxtype config set output.post_process.command "$hook" >/dev/null 2>&1; then
    echo "voxtype: dictation log wired through bin/voxtype-capture"
    # Only if it is already up — the daemon is normally stopped, and starting
    # one here would park the model in RAM for nothing.
    systemctl --user try-restart voxtype.service >/dev/null 2>&1 || true
  else
    warn "could not set output.post_process.command — the dictation panel will show no history"
  fi
fi

# Two keys voxtype reads but `voxtype config set` refuses — they parse from the
# file and are absent from the settable schema, the same class as
# output.pre_recording_command. They have to be written by hand, so this is the
# one place here that edits config.toml directly.
#
# Guarded four ways: the section must already exist (both are created by the
# `config set` calls above, or by voxtype's own default config), the
# uncommented key must be absent, a backup is kept, and the result is VERIFIED
# by asking voxtype to parse the file back — restoring the backup if it cannot.
# A config voxtype refuses to parse is a daemon that will not start at all.
cfg="${XDG_CONFIG_HOME:-$HOME/.config}/voxtype/config.toml"

set_unsettable() { # <section> <key> <value> <what it buys>
  local section="$1" key="$2" value="$3" why="$4"
  [ -f "$cfg" ] || return 0
  grep -qE "^[[:space:]]*\[${section//./\\.}\][[:space:]]*$" "$cfg" || return 0
  grep -qE "^[[:space:]]*${key}[[:space:]]*=" "$cfg" && return 0

  cp -a "$cfg" "$cfg.bak"
  if awk -v sec="[$section]" -v line="$key = $value" '
      { print }
      $0 ~ "^[[:space:]]*\\" sec "[[:space:]]*$" && !done { print line; done = 1 }
    ' "$cfg" >"$cfg.new" && mv -f "$cfg.new" "$cfg" &&
    voxtype config get vad.enabled >/dev/null 2>&1; then
    rm -f "$cfg.bak"
    echo "voxtype: $why ($key = $value)"
    systemctl --user try-restart voxtype.service >/dev/null 2>&1 || true
  else
    mv -f "$cfg.bak" "$cfg"
    rm -f "$cfg.new"
    warn "could not set $key — $why is not in effect"
  fi
}

# What lets bin/voxtype-capture DROP a transcript rather than merely rewrite
# one. With the default `true`, a hook that prints nothing makes voxtype type
# the ORIGINAL text instead, so the silence-hallucination filter would be a
# no-op without this line.
set_unsettable "output.post_process" fallback_on_empty false \
  "hallucination filter armed"

# `vad.min_speech_duration_ms` is DELIBERATELY NOT SET, and the reason is worth
# keeping so nobody re-derives it. VAD's verdict is `segments > 0 AND total
# speech >= min_speech_duration_ms`, so raising the 100 ms default looks like
# the sharp knob against silence hallucinations. It was tried at 1000 ms on
# 2026-09-04 and rejected only 1 of 5 quiet-room takes, while costing every
# dictation shorter than a second.
#
# It failed because the premise was wrong. Measured through
# voxtype-audio-bridge on this machine, a "quiet" room peaks at 0.256 with 524
# of 528 frames above the bridge's own -40 dBFS speech threshold — LOUDER than
# a real-speech test that peaked at 0.203. VAD is not being fooled; the
# microphone genuinely hears that much. No threshold separates signal from
# noise when the noise is the same size as the signal, which is also why
# `vad.threshold = 0.7` measured WORSE than 0.5 (3 of 4 versus 2 of 4).
#
# The fix for that lives at the microphone, not in this file: the input is hot
# (source at 0.70 through the Asahi j493 filter chain) and a quieter room or a
# lower capture gain is what moves it. Revisit this key if that changes.

exit 0
