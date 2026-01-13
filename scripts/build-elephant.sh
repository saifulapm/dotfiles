#!/bin/bash
# Build elephant and providers from source
# Elephant is the data provider backend for walker

set -e

ELEPHANT_DIR="$HOME/.local/share/elephant-src"
PROVIDERS_DIR="$HOME/.config/elephant/providers"
BIN_DIR="$HOME/.local/bin"

# Ensure Go is installed
if ! command -v go &>/dev/null; then
    echo "Error: Go is required to build elephant"
    echo "Install with: sudo dnf install golang"
    exit 1
fi

# Ensure directories exist
mkdir -p "$BIN_DIR"
mkdir -p "$PROVIDERS_DIR"

# Clone/update elephant
if [[ -d "$ELEPHANT_DIR" ]]; then
    echo "Updating elephant source..."
    cd "$ELEPHANT_DIR"
    git pull
else
    echo "Cloning elephant..."
    git clone https://github.com/abenz1267/elephant "$ELEPHANT_DIR"
    cd "$ELEPHANT_DIR"
fi

# Build main binary from module root
echo "Building elephant..."
cd "$ELEPHANT_DIR"
go build -buildvcs=false -trimpath -o elephant ./cmd/elephant
cp elephant "$BIN_DIR/"
echo "Installed: $BIN_DIR/elephant"

# Build providers from module root
cd "$ELEPHANT_DIR"

# All providers except archlinuxpkgs (Arch-specific)
PROVIDERS=(
    desktopapplications
    files
    bluetooth
    clipboard
    runner
    symbols
    calc
    menus
    providerlist
    websearch
    todo
    bookmarks
    unicode
    windows
    snippets
    nirisessions
    1password
    dnfpackages
)

echo ""
echo "Building providers..."
for provider in "${PROVIDERS[@]}"; do
    provider_path="./internal/providers/$provider"
    if [[ -d "$ELEPHANT_DIR/internal/providers/$provider" ]]; then
        echo "  Building: $provider"
        if go build -buildvcs=false -trimpath -buildmode=plugin -o "$PROVIDERS_DIR/${provider}.so" "$provider_path" 2>/dev/null; then
            echo "    OK"
        else
            echo "    Warning: Failed to build $provider"
        fi
    else
        echo "  Skipping: $provider (directory not found)"
    fi
done

echo ""
echo "Elephant build complete!"
echo "Binary: $BIN_DIR/elephant"
echo "Providers: $PROVIDERS_DIR/"
ls -la "$PROVIDERS_DIR/"

# Install systemd service with explicit path (avoids conflict with /usr/local/bin/elephant)
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICE_SRC="$DOTFILES_DIR/config/systemd/user/elephant.service"
SERVICE_DST="$HOME/.config/systemd/user/elephant.service"

if [[ -f "$SERVICE_SRC" ]]; then
    echo ""
    echo "Installing systemd service..."
    mkdir -p "$(dirname "$SERVICE_DST")"
    cp "$SERVICE_SRC" "$SERVICE_DST"
    systemctl --user daemon-reload
    systemctl --user enable elephant.service
    systemctl --user restart elephant.service
    echo "Service enabled and started"
else
    echo ""
    echo "To enable the service, run:"
    echo "  systemctl --user daemon-reload"
    echo "  systemctl --user enable elephant.service"
    echo "  systemctl --user start elephant.service"
fi
