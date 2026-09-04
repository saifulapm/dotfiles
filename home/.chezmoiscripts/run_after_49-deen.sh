#!/usr/bin/env bash
# deen (github.com/saifulapm/deen) — recite an ayah, be told which words were
# right. The shell's Islamic Hub is a front end for this binary and nothing
# else: `deen api` answers the text and `deen recite` scores a recitation, so a
# machine without it has a hub that can only report that it is missing.
#
# Three things to install, each guarded independently so a half-finished run
# resumes rather than restarting: the binary, the text, and the model.
#
# Built once, guarded on the binary, warn-don't-abort — the same contract as
# run_after_42-dekho. The build is quick (four small crates, no ML runtime and
# no HTTP client), which is the whole point of shelling out to voxtype for
# transcription rather than linking anything.
#
# ~/.local/src/deen, NOT ~/Sites/github/deen. The Sites copy is the development
# checkout and may sit on an unpushed branch mid-change; what every machine
# runs has to come from origin.
set -uo pipefail

warn() { echo "deen: $*" >&2; }

export PATH="$HOME/.cargo/bin:$PATH"

data="$HOME/.local/share/deen/quran.json"
duas="$HOME/.local/share/deen/duas.json"
model_dir="$HOME/.local/share/voxtype/models"
model="$model_dir/ggml-quran-base-q8.bin"
src="$HOME/.local/src/deen"

# ------------------------------------------------------------------ the binary
if [ ! -x "$HOME/.local/bin/deen" ]; then
  for dep in cargo git; do
    command -v "$dep" >/dev/null 2>&1 || {
      warn "$dep missing — skipping (rerun after 03-dev-toolchain lands)"
      exit 0
    }
  done

  # rev-parse rather than [ -d .git ]: a clone killed mid-transfer must not
  # satisfy the check for ever.
  if ! git -C "$src" rev-parse HEAD >/dev/null 2>&1; then
    rm -rf "$src"
    mkdir -p "$HOME/.local/src"
    git clone --depth 1 https://github.com/saifulapm/deen "$src" || {
      warn "clone failed"
      exit 0
    }
  fi

  if cargo build --release --quiet --manifest-path "$src/Cargo.toml"; then
    mkdir -p "$HOME/.local/bin"
    install -m755 "$src/target/release/deen" "$HOME/.local/bin/deen" \
      && echo "deen: installed to ~/.local/bin/deen"
  else
    warn "build failed — try by hand: cargo build --release --manifest-path $src/Cargo.toml"
  fi
fi

# -------------------------------------------------------------------- the text
# 4.4 MB of Uthmani script with Bangla and English, fetched once. The Quran does
# not change, so nothing refreshes this and update-all leaves it alone.
if [ ! -s "$data" ] && [ -x "$src/scripts/fetch-data" ]; then
  mkdir -p "$(dirname "$data")"
  echo "deen: fetching the Quran text (once)"
  if "$src/scripts/fetch-data" >"$data.tmp" 2>/dev/null; then
    mv "$data.tmp" "$data"
  else
    rm -f "$data.tmp"
    warn "could not fetch the Quran text — the hub will say so; rerun a chezmoi apply"
  fi
fi

# -------------------------------------------------------------------- the duas
# Hisn al-Muslim: 268 duas in 132 chapters, each with the book's own reference
# footnote. Fetched once and never refreshed, like the text — and separately
# guarded, so a machine that already has the Quran file picks this up on the
# next apply without refetching 5 MB it already has.
#
# The fetch fails loudly rather than installing a half-right book: it pulls
# sunnah.com's page and an archived copy of the same page pinned to a commit,
# and every field of all 268 has to match. See scripts/fetch-duas.
if [ ! -s "$duas" ] && [ -x "$src/scripts/fetch-duas" ]; then
  mkdir -p "$(dirname "$duas")"
  echo "deen: fetching the duas (once)"
  if "$src/scripts/fetch-duas" >"$duas.tmp" 2>/dev/null; then
    mv "$duas.tmp" "$duas"
  else
    rm -f "$duas.tmp"
    warn "could not fetch the duas — the hub's Duas screen will say so; rerun a chezmoi apply"
  fi
fi

# ------------------------------------------------------------------- the model
# Tarteel's Quran fine-tune of whisper-base, q8_0 (78 MB). Not the fp16 (141 MB):
# measured on Al-Fatiha the two produced byte-identical transcriptions and q8 was
# 20% faster, so the larger file buys nothing here.
if [ ! -s "$model" ]; then
  command -v curl >/dev/null 2>&1 || {
    warn "curl missing — cannot fetch the model"
    exit 0
  }
  mkdir -p "$model_dir"
  url="https://huggingface.co/ram-a-dhan/tarteel-whisper-quran-ggml/resolve/main/tarteel-ai-whisper-base-ar-quran-ggml-q8_0.bin"
  echo "deen: fetching the Quran speech model (78 MB, once)"
  if ! curl -fL --retry 3 --max-time 900 -o "$model.tmp" "$url"; then
    rm -f "$model.tmp"
    warn "model download failed — the hub will say so; rerun a chezmoi apply"
    exit 0
  fi

  # EVERY PUBLISHED ggml CONVERSION OF THIS MODEL IS BROKEN THE SAME WAY and
  # whisper.cpp refuses to load it:
  #
  #   tensor 'decoder.positional_embedding' has wrong size in model file
  #   shape: [512, 448, 1], expected: [512, 1024, 1]
  #
  # The header declares n_text_ctx = 1024 while the tensor is the standard 448.
  # Checked against two independent uploaders — it is the converter, not a bad
  # upload. Only the header lies, so this rewrites that one field: offset 24 is
  # 4 bytes of magic plus five int32s, and 448 is 0x1C0 little-endian.
  #
  # Guarded on the current value so a future upload that ships the right header
  # is left alone rather than corrupted into 448-of-448.
  ctx=$(od -An -tu4 -j24 -N4 "$model.tmp" 2>/dev/null | tr -d ' ')
  if [ "$ctx" = "1024" ]; then
    printf '\300\001\000\000' | dd of="$model.tmp" bs=1 seek=24 conv=notrunc status=none \
      && echo "deen: patched the model header (n_text_ctx 1024 → 448)"
  elif [ "$ctx" != "448" ]; then
    warn "unexpected n_text_ctx=$ctx in the downloaded model — leaving it unpatched"
  fi
  mv "$model.tmp" "$model"
fi

exit 0
