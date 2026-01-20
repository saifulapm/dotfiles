#!/bin/bash

# Setup Work directory with mise config

# Activate mise if available (needed when running from setup.sh)
if command -v mise &>/dev/null; then
    eval "$(mise activate bash)"
fi

mkdir -p "$HOME/Work"
mkdir -p "$HOME/Work/tries"

# Add ./bin to path for all items in ~/Work
cat >"$HOME/Work/.mise.toml" <<'EOF'
[env]
_.path = "{{ cwd }}/bin"
EOF

mise trust ~/Work/.mise.toml

# Install node globally - use mise install explicitly to ensure it's installed
mise use -g node@lts
mise install node@lts
