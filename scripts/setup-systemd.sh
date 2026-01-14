#!/bin/bash
# Setup systemd user services

set -e

echo "Setting up systemd user services..."

# Enable waybar to start with niri
systemctl --user add-wants niri.service waybar.service

# Reload systemd
systemctl --user daemon-reload

echo "Systemd services configured!"
echo "- waybar: starts with niri"
