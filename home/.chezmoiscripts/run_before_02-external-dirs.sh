#!/bin/bash
# Parent for the qshell data dir. Originally the parent for the wallpapers
# external: chezmoi extracts archive externals but does not create a
# destination's missing parent directories (found 2026-08-07 — the apply died
# with "mkdir …/qshell/backgrounds: no such file or directory"), and symlink
# mode turns a committed .keep into a stray symlink (see
# run_after_15-user-dirs). The wallpapers come from
# run_after_27-wallpapers.sh now and it makes this parent itself, but the
# directory is free to guarantee early and the rule above still holds for any
# future external under it. run_before, so the directory exists before the
# file/external phase that extracts into it.
set -euo pipefail
mkdir -p "$HOME/.local/share/qshell"
