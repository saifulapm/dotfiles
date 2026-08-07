#!/bin/bash
# Parent for the wallpapers external: chezmoi extracts archive externals but
# does not create a destination's missing parent directories (found
# 2026-08-07 — the apply died with "mkdir …/qshell/backgrounds: no such file
# or directory"), and symlink mode turns a committed .keep into a stray
# symlink (see run_after_15-user-dirs). run_before, so the directory exists
# before the file/external phase that extracts into it.
set -euo pipefail
mkdir -p "$HOME/.local/share/qshell"
