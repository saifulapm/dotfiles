#!/bin/bash

# Omarchy Chromium Installer/Updater for Fedora (x86_64 and aarch64)
# Based on: https://github.com/omacom-io/omarchy-chromium

set -e

ARCH=$(uname -m)
REPO_API="https://api.github.com/repos/omacom-io/omarchy-chromium/releases/latest"
INSTALL_DIR="/opt/omarchy-chromium"
VERSION_FILE="${INSTALL_DIR}/.version"
DOTFILES="${DOTFILES:-$HOME/.dotfiles}"
TMP_DIR=""

cleanup() { [[ -n "$TMP_DIR" ]] && rm -rf "$TMP_DIR"; }
trap cleanup EXIT

info() { echo -e "\033[0;34m[INFO]\033[0m $1"; }
success() { echo -e "\033[0;32m[SUCCESS]\033[0m $1"; }
error() { echo -e "\033[0;31m[ERROR]\033[0m $1"; exit 1; }

# Re-run with sudo if not root
if [[ $EUID -ne 0 ]]; then
    exec sudo "$0" "$@"
fi

# Check system architecture
if [[ "$ARCH" != "x86_64" && "$ARCH" != "aarch64" ]]; then
    error "Unsupported architecture: $ARCH"
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
    error "Could not find $ARCH package in latest release"
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
    TMP_DIR=$(mktemp -d)
    cd "$TMP_DIR"

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

    # Update desktop database
    update-desktop-database /usr/share/applications 2>/dev/null || true

    success "Omarchy Chromium $LATEST_VERSION installed!"
fi

# Setup user config (runs as the actual user, not root)
ACTUAL_USER="${SUDO_USER:-$USER}"
ACTUAL_HOME=$(getent passwd "$ACTUAL_USER" | cut -d: -f6)
ACTUAL_DOTFILES="$ACTUAL_HOME/.dotfiles"

info "Setting up browser config for $ACTUAL_USER..."

# Link chromium flags
sudo -u "$ACTUAL_USER" ln -sf "$ACTUAL_DOTFILES/config/chromium-flags.conf" "$ACTUAL_HOME/.config/chromium-flags.conf"

success "Setup complete!"
echo ""
echo "Extension loaded from: $ACTUAL_DOTFILES/default/chromium/extensions/copy-url"
echo "Theme will apply automatically when you change themes."
