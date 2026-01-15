#!/bin/bash
# Setup browser configuration

DOTFILES="${DOTFILES:-$HOME/.dotfiles}"

# Link chromium flags
ln -sf "$DOTFILES/config/chromium-flags.conf" ~/.config/chromium-flags.conf

echo "Browser setup complete"
echo "Extension will load from: $DOTFILES/default/chromium/extensions/copy-url"
