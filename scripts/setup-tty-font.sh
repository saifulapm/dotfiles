#!/bin/bash
# Setup readable TTY console font (Terminus 22pt)
# Useful for Fedora Asahi Minimal which starts in TTY

set -e

# Install terminus console fonts if missing
if ! rpm -q terminus-fonts-console &>/dev/null; then
    echo "Installing terminus-fonts-console..."
    sudo dnf install -y terminus-fonts-console
fi

# Set console font in vconsole.conf (Fedora standard)
VCONSOLE="/etc/vconsole.conf"

if grep -q "^FONT=" "$VCONSOLE" 2>/dev/null; then
    sudo sed -i 's/^FONT=.*/FONT=ter-v22n/' "$VCONSOLE"
else
    echo "FONT=ter-v22n" | sudo tee -a "$VCONSOLE" >/dev/null
fi

# Apply immediately
sudo setfont ter-v22n 2>/dev/null || true

echo "TTY console font set to Terminus 22pt (ter-v22n)"
echo "This persists across reboots via /etc/vconsole.conf"
