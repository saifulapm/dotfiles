#!/usr/bin/env bash
# voxtype — the push-to-talk dictation daemon behind Mod+Ctrl+X / F9 and the
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
# VERSION PIN: v0.7.5, the newest release with linux assets at all —
# v1.0.0-rc1 (2026-06-04) ships macos-universal only. So "latest" via the
# GitHub API (the run_after_10 pattern) is not usable here; recheck when a 1.0
# with linux binaries lands. Upgrades stay `voxtype check-update` or a bump
# here: this script only ever installs a MISSING binary, it never overwrites
# one already on disk.
#
# Failures warn instead of aborting, like the other fetch scripts — a flaky
# network must not stop the rest of a fresh-machine apply; dictation just
# stays inert until the next one.
set -uo pipefail

VERSION="0.7.5"

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

base="https://github.com/peteonrails/voxtype/releases/download/v$VERSION"

if ! command -v voxtype >/dev/null 2>&1; then
  tmp="$(mktemp -d)"
  # Checksummed because upstream publishes SHA256SUMS.txt next to the assets
  # and this is a bare binary, not a package with its own verification. An
  # empty `want` (asset renamed upstream) fails the comparison rather than
  # matching a truncated download.
  if curl -fsSL -o "$tmp/voxtype" "$base/$asset" &&
    curl -fsSL -o "$tmp/SHA256SUMS.txt" "$base/SHA256SUMS.txt" &&
    want="$(awk -v a="$asset" '$2 == a { print $1 }' "$tmp/SHA256SUMS.txt")" &&
    [ -n "$want" ] &&
    [ "$want" = "$(sha256sum "$tmp/voxtype" | cut -d' ' -f1)" ] &&
    install -Dm755 "$tmp/voxtype" "$HOME/.local/bin/voxtype"; then
    echo "voxtype: installed $VERSION ($asset) to ~/.local/bin"
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
# in 0.2 s instead and voxtype-idle-stop.timer reaps it after 10 min idle.
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
    warn "'voxtype setup systemd' failed — Mod+Ctrl+X / F9 cannot start the daemon"
  fi
fi

exit 0
