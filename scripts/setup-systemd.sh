#!/bin/bash
# Setup systemd user services

set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICE_DIR="$HOME/.config/systemd/user"

echo "Setting up systemd user services..."

# Copy service files
mkdir -p "$SERVICE_DIR"
cp "$DOTFILES_DIR/config/systemd/user/"*.service "$SERVICE_DIR/" 2>/dev/null || true

# Reload systemd
systemctl --user daemon-reload

# Enable services to start with niri
systemctl --user add-wants niri.service waybar.service
systemctl --user add-wants niri.service swaybg.service
systemctl --user add-wants niri.service mako.service
systemctl --user add-wants niri.service swayidle.service

# Enable elephant and voxtype to start with graphical session
systemctl --user enable elephant.service 2>/dev/null || true
systemctl --user enable voxtype.service 2>/dev/null || true

echo "Systemd services configured!"
echo "- waybar: starts with niri"
echo "- swaybg: starts with niri"
echo "- mako: starts with niri"
echo "- swayidle: starts with niri"
echo "- elephant: starts with graphical-session"
echo "- voxtype: starts with graphical-session"
