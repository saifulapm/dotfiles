#!/bin/bash
# Setup iwd as NetworkManager wifi backend

set -e

echo "Setting up iwd as wifi backend..."

# Create NetworkManager config to use iwd
sudo mkdir -p /etc/NetworkManager/conf.d/
echo -e "[device]\nwifi.backend=iwd" | sudo tee /etc/NetworkManager/conf.d/iwd.conf

# Enable and start iwd
sudo systemctl enable --now iwd

# Restart NetworkManager to apply changes
sudo systemctl restart NetworkManager

echo ""
echo "iwd setup complete!"
echo "WiFi is now managed by iwd via NetworkManager"
