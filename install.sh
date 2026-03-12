#!/bin/bash

# Config
REPO="saifulapm/dotfiles"
BRANCH="main"

# ─────────────────────────────────────────────────────────────

set -e

DOTFILES="$HOME/.dotfiles"

# Ensure git is available
if ! command -v git &>/dev/null; then
    echo "Installing git..."
    sudo dnf install -y git
fi

echo "Cloning dotfiles..."
if [[ -d "$DOTFILES/.git" ]]; then
    git -C "$DOTFILES" fetch --quiet origin
    git -C "$DOTFILES" reset --hard --quiet "origin/$BRANCH"
else
    rm -rf "$DOTFILES"
    git clone --quiet "https://github.com/$REPO.git" "$DOTFILES"
fi

cd "$DOTFILES"
exec ./setup.sh
