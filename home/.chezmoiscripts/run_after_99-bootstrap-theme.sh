#!/bin/bash
# First-boot theme bootstrap: if no active theme exists yet, activate the
# default so the foot and GTK configs are generated and the shell has tokens.
set -euo pipefail
state="$HOME/.local/state/qshell/theme.toml"
if [ ! -f "$state" ]; then
  "$(chezmoi source-path | xargs dirname)/bin/theme-set" tokyo-night
fi
