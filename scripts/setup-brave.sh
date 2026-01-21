#!/bin/bash

# Setup Brave browser policy directory for theme support

POLICY_DIR="/etc/brave/policies/managed"
POLICY_FILE="$POLICY_DIR/color.json"

# Only run if Brave is installed
if ! flatpak list 2>/dev/null | grep -q "com.brave.Browser" && ! command -v brave-browser &>/dev/null && ! command -v brave &>/dev/null; then
    exit 0
fi

# Create policy directory if needed
if [[ ! -d "$POLICY_DIR" ]]; then
    sudo mkdir -p "$POLICY_DIR"
fi

# Create initial policy file if needed
if [[ ! -f "$POLICY_FILE" ]]; then
    echo '{"BrowserThemeColor": "#1e1e2e"}' | sudo tee "$POLICY_FILE" > /dev/null
fi

# Make file writable by user for future theme changes
sudo chown "$USER" "$POLICY_FILE" 2>/dev/null || true
