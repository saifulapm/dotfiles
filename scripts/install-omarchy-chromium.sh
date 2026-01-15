#!/bin/bash

# Omarchy Chromium Installer/Updater for Fedora (aarch64)
# Based on: https://github.com/omacom-io/omarchy-chromium

set -e

ARCH="aarch64"
REPO_API="https://api.github.com/repos/omacom-io/omarchy-chromium/releases/latest"
INSTALL_DIR="/opt/omarchy-chromium"
VERSION_FILE="${INSTALL_DIR}/.version"
DOTFILES="${DOTFILES:-$HOME/.dotfiles}"

info() { echo -e "\033[0;34m[INFO]\033[0m $1"; }
success() { echo -e "\033[0;32m[SUCCESS]\033[0m $1"; }
error() { echo -e "\033[0;31m[ERROR]\033[0m $1"; exit 1; }

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root (use sudo)"
fi

# Check system architecture
system_arch=$(uname -m)
if [[ "$system_arch" != "aarch64" ]]; then
    error "This script is for aarch64 architecture. Your system is: $system_arch"
fi

# Install dependencies
info "Checking dependencies..."
for dep in curl jq tar zstd; do
    if ! command -v "$dep" &>/dev/null; then
        dnf install -y "$dep"
    fi
done

# Get latest version
info "Fetching latest version..."
release_info=$(curl -s "$REPO_API")
LATEST_VERSION=$(echo "$release_info" | jq -r '.tag_name' | sed 's/^v//')
DOWNLOAD_URL=$(echo "$release_info" | jq -r ".assets[] | select(.name | contains(\"${ARCH}\")) | .browser_download_url")
PACKAGE_NAME=$(echo "$release_info" | jq -r ".assets[] | select(.name | contains(\"${ARCH}\")) | .name")

if [[ -z "$LATEST_VERSION" ]] || [[ -z "$DOWNLOAD_URL" ]]; then
    error "Could not find aarch64 package in latest release"
fi

info "Latest version: $LATEST_VERSION"

# Check installed version
if [[ -f "$VERSION_FILE" ]]; then
    INSTALLED_VERSION=$(cat "$VERSION_FILE")
    if [[ "$INSTALLED_VERSION" == "$LATEST_VERSION" ]]; then
        success "Already up to date!"
    else
        info "Update available: $INSTALLED_VERSION → $LATEST_VERSION"
    fi
fi

# Download and extract if not up to date
if [[ ! -f "$VERSION_FILE" ]] || [[ "$(cat "$VERSION_FILE")" != "$LATEST_VERSION" ]]; then
    temp_dir=$(mktemp -d)
    cd "$temp_dir"

    info "Downloading omarchy-chromium..."
    curl -L -o "$PACKAGE_NAME" "$DOWNLOAD_URL"

    info "Extracting..."
    tar -xf "$PACKAGE_NAME"

    # Install
    info "Installing..."
    mkdir -p "$INSTALL_DIR"
    [[ -d "usr" ]] && cp -r usr/* /usr/ 2>/dev/null || true
    [[ -d "opt" ]] && cp -r opt/* /opt/ 2>/dev/null || true

    echo "$LATEST_VERSION" > "$VERSION_FILE"

    # Cleanup
    cd /
    rm -rf "$temp_dir"

    # Update desktop database
    update-desktop-database /usr/share/applications 2>/dev/null || true

    success "Omarchy Chromium $LATEST_VERSION installed!"
fi

# Setup user config (runs as the actual user, not root)
ACTUAL_USER="${SUDO_USER:-$USER}"
ACTUAL_HOME=$(getent passwd "$ACTUAL_USER" | cut -d: -f6)

info "Setting up browser config for $ACTUAL_USER..."

# Link chromium flags
sudo -u "$ACTUAL_USER" ln -sf "$DOTFILES/config/chromium-flags.conf" "$ACTUAL_HOME/.config/chromium-flags.conf"

success "Setup complete!"
echo ""
echo "Extension loaded from: $DOTFILES/default/chromium/extensions/copy-url"
echo "Theme will apply automatically when you change themes."
