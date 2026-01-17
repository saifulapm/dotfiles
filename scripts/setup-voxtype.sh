#!/bin/bash
# Install voxtype - downloads RPM for x86_64, builds from source for ARM64

set -e

UPDATE_MODE=false
[[ "$1" == "--update" ]] && UPDATE_MODE=true

DOTFILES="${DOTFILES:-$HOME/.dotfiles}"
ARCH=$(uname -m)

if command -v voxtype &>/dev/null && [[ "$UPDATE_MODE" == "false" ]]; then
    echo "voxtype already installed"
    exit 0
fi

TEMP_DIR=$(mktemp -d)
cleanup() { rm -rf "$TEMP_DIR"; }
trap cleanup EXIT

echo "Detected architecture: $ARCH"

if [[ "$ARCH" == "x86_64" ]]; then
    # x86_64: Download RPM from GitHub releases
    echo "Fetching latest voxtype release..."

    LATEST_RELEASE=$(curl -sL "https://api.github.com/repos/peteonrails/voxtype/releases/latest")
    VOXTYPE_VERSION=$(echo "$LATEST_RELEASE" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')

    if [[ -z "$VOXTYPE_VERSION" ]]; then
        echo "Error: Could not determine latest voxtype version"
        exit 1
    fi

    echo "Latest version: $VOXTYPE_VERSION"

    RPM_URL=$(echo "$LATEST_RELEASE" | grep '"browser_download_url"' | grep '\.rpm"' | sed -E 's/.*"([^"]+)".*/\1/' | head -1)

    if [[ -z "$RPM_URL" ]]; then
        echo "Error: Could not find RPM download URL"
        exit 1
    fi

    RPM_NAME=$(basename "$RPM_URL")
    echo "Downloading $RPM_NAME..."

    cd "$TEMP_DIR"
    curl -sL "$RPM_URL" -o "$RPM_NAME"
    sudo dnf install -y "./$RPM_NAME"
else
    # ARM64/aarch64: Build from source
    echo "Building voxtype from source for $ARCH..."

    # Install build dependencies
    sudo dnf install -y clang alsa-lib-devel

    cd "$TEMP_DIR"
    git clone https://github.com/peteonrails/voxtype
    cd voxtype

    echo "Compiling (this may take a few minutes)..."
    cargo build --release

    echo "Installing to /usr/local/bin..."
    # Stop voxtype systemd service before replacing binary
    systemctl --user stop voxtype.service 2>/dev/null || true
    sleep 1
    sudo cp target/release/voxtype /usr/local/bin/
fi

# Setup config
mkdir -p ~/.config/voxtype
if [[ ! -f ~/.config/voxtype/config.toml ]]; then
    cp "$DOTFILES/config/voxtype/config.toml" ~/.config/voxtype/
    echo "Config installed to ~/.config/voxtype/config.toml"
fi

# Download whisper model and setup systemd
echo "Setting up voxtype (downloading AI model ~150MB)..."
voxtype setup --download --no-post-install
voxtype setup systemd

echo ""
echo "Voxtype installed!"
echo "Add keybind in niri for: voxtype record toggle"
echo "Edit ~/.config/voxtype/config.toml for options"
