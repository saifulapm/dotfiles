#!/usr/bin/env bash
# dekho (github.com/saifulapm/dekho) — search films and series, stream them
# straight into mpv. The shell's Movies & TV hub is a front end for this
# binary and nothing else: `dekho api` answers every listing the panel draws
# and `dekho play --json` narrates a playback, so a machine without it has a
# hub that can only report that it is missing.
#
# Built once, guarded on the binary, warn-don't-abort — the same contract as
# run_after_29-nirisnap. THE FIRST BUILD IS LONG: dekho links librqbit, a
# whole BitTorrent stack, so a fresh machine spends several minutes here.
# That is why the guard is on the installed binary rather than on a version:
# an apply must never surprise-rebuild. `update-all` is what refreshes it —
# it advances the checkout and deletes the binary, and this reinstalls at the
# new revision on the apply that follows.
#
# ~/.local/src/dekho, NOT ~/Sites/github/dekho. The Sites copy is the
# development checkout and may sit on an unpushed branch mid-change; what
# every machine runs has to come from origin, deterministically, and this box
# is not special.
#
# The TMDB key is NOT set up here — it arrives as
# home/.chezmoitemplates/dekho.toml.age, rendered to ~/.config/dekho/config.toml
# by chezmoi itself. A machine with no age key gets the binary and no config,
# which is exactly the phase-1 install behaviour the mail templates have.
set -uo pipefail

warn() { echo "dekho: $*" >&2; }

[ -x "$HOME/.local/bin/dekho" ] && exit 0

export PATH="$HOME/.cargo/bin:$PATH"

for dep in cargo git; do
  command -v "$dep" >/dev/null 2>&1 || {
    warn "$dep missing — skipping (rerun after 03-dev-toolchain lands)"
    exit 0
  }
done

# mpv is what dekho hands the stream to. Not fatal — the build is still worth
# having — but a silent install that cannot play anything is worse than a line
# of warning here.
command -v mpv >/dev/null 2>&1 || warn "mpv is not installed; dekho will build but cannot play (packages/manifest.toml declares it)"

src="$HOME/.local/src/dekho"
# rev-parse rather than [ -d .git ]: same half-clone guard as the kakoune fork
# and nirisnap — a clone killed mid-transfer must not satisfy the check
# forever.
if ! git -C "$src" rev-parse HEAD >/dev/null 2>&1; then
  rm -rf "$src"
  mkdir -p "$HOME/.local/src"
  git clone --depth 1 https://github.com/saifulapm/dekho "$src" || {
    warn "clone failed"
    exit 0
  }
fi

echo "dekho: building (first run only — librqbit makes this a few minutes)"
if cargo build --release --quiet --manifest-path "$src/Cargo.toml"; then
  mkdir -p "$HOME/.local/bin"
  install -m755 "$src/target/release/dekho" "$HOME/.local/bin/dekho" \
    && echo "dekho: installed to ~/.local/bin/dekho"
else
  warn "build failed — try by hand: cargo build --release --manifest-path ~/.local/src/dekho/Cargo.toml"
fi

exit 0
