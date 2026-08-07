#!/usr/bin/env bash
# sherpa-onnx — the neural text-to-speech behind `screenshot-ocr --speak`
# (Mod+Ctrl+Shift+6, "Read Region Aloud"). Fedora packages no usable neural
# TTS: flite and espeak-ng are 1990s formant/diphone synths, and the good
# engines all ship as Python wheels. sherpa-onnx is the exception — one
# prebuilt C++ binary that runs Kokoro (82M-param neural) and Kitten (15M)
# from the same CLI, so this desktop gets a natural-sounding voice without a
# venv, a pip, or a second Python on the box.
#
# Unlike satty this is a TREE, not a single binary: the tool needs its own
# libonnxruntime, so it lands in ~/.local/share rather than ~/.local/bin and
# bin/screenshot-ocr is the only thing that sets its LD_LIBRARY_PATH. Nothing
# goes on PATH; there is no daemon and no systemd unit — the model loads per
# invocation and exits, which is what keeps a 300 MB resident process off a
# laptop that runs ~1.5 GB free (see bin/mem-pressure-warn).
#
# Only the two TTS binaries are kept. The tarball also carries ~40 ASR, VAD,
# speaker-ID and keyword-spotting tools this desktop has no use for; voxtype
# already owns speech-to-text here.
#
# MODEL CHOICE: int8 throughout, deliberately. Measured on the M2 (2026-08-08)
# with --num-threads=4:
#   kokoro-int8-multi-lang-v1_0   330 MB peak RSS   RTF 0.59   (the default)
#   kitten-nano-en-v0_8-int8      143 MB peak RSS   RTF 0.16   (fallback)
# The fp32 Kokoro is 3.5x the download for no audible gain at this listening
# distance. Both beat realtime, which is what makes the streaming player
# (sherpa-onnx-offline-tts-play) start speaking almost immediately.
#
# Failure warns instead of aborting, like every other install script here: a
# flaky network must not stop a fresh-machine apply, and screenshot-ocr falls
# back through piper → espeak-ng → flite on its own when this is absent.
set -uo pipefail

VERSION="v1.13.4"
dest="$HOME/.local/share/sherpa-onnx"
models=(kokoro-int8-multi-lang-v1_0 kitten-nano-en-v0_8-int8)
base="https://github.com/k2-fsa/sherpa-onnx/releases/download"

warn() { echo "sherpa-onnx: $*" >&2; }

# Upstream names the two arches differently — aarch64 gets a "-cpu" variant,
# x64 does not — so this is a lookup, not a substitution.
case "$(uname -m)" in
aarch64) asset="sherpa-onnx-$VERSION-linux-aarch64-shared-cpu.tar.bz2" ;;
x86_64) asset="sherpa-onnx-$VERSION-linux-x64-shared.tar.bz2" ;;
*)
  echo "sherpa-onnx: no upstream binary for $(uname -m)" >&2
  exit 0
  ;;
esac

# Binaries: pinned, so a version bump above re-installs rather than no-ops.
if [ "$(cat "$dest/.version" 2>/dev/null)" != "$VERSION" ]; then
  tmp="$(mktemp -d)"
  if curl -fsSL -o "$tmp/sherpa.tar.bz2" "$base/$VERSION/$asset" &&
    tar -xjf "$tmp/sherpa.tar.bz2" -C "$tmp" --strip-components=1 &&
    [ -d "$tmp/bin" ] && [ -d "$tmp/lib" ]; then
    mkdir -p "$dest/bin" "$dest/lib" "$dest/models"
    install -m755 "$tmp/bin/sherpa-onnx-offline-tts" \
      "$tmp/bin/sherpa-onnx-offline-tts-play" "$dest/bin/" &&
      cp -f "$tmp"/lib/*.so* "$dest/lib/" &&
      echo "$VERSION" >"$dest/.version" &&
      echo "sherpa-onnx: installed $VERSION to $dest"
  else
    warn "binary install failed — read-aloud falls back to flite"
  fi
  rm -rf "$tmp"
fi

# Models: guarded individually so a network drop mid-apply resumes cleanly
# instead of re-fetching the ~163 MB both times.
for m in "${models[@]}"; do
  [ -d "$dest/models/$m" ] && continue
  mkdir -p "$dest/models"
  tmp="$(mktemp -d)"
  if curl -fsSL -o "$tmp/$m.tar.bz2" "$base/tts-models/$m.tar.bz2" &&
    tar -xjf "$tmp/$m.tar.bz2" -C "$tmp" &&
    [ -d "$tmp/$m" ]; then
    mv "$tmp/$m" "$dest/models/$m" && echo "sherpa-onnx: fetched model $m"
  else
    warn "model $m failed to download"
  fi
  rm -rf "$tmp"
done

exit 0
