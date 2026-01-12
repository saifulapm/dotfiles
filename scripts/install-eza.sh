#!/bin/bash

# Install eza - modern replacement for ls
# https://github.com/eza-community/eza

set -euo pipefail

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

EZA_BIN="$HOME/.local/bin/eza"

install_via_cargo() {
    log_info "Installing eza via cargo..."

    # Check if cargo is available
    if ! command -v cargo &>/dev/null; then
        log_info "Cargo not found, installing rust toolchain..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
        source "$HOME/.cargo/env"
    fi

    cargo install eza

    # Link to local bin
    mkdir -p "$HOME/.local/bin"
    if [[ -f "$HOME/.cargo/bin/eza" ]]; then
        ln -sf "$HOME/.cargo/bin/eza" "$EZA_BIN"
    fi
}

install_via_binary() {
    log_info "Installing eza from pre-built binary..."

    local arch
    arch=$(uname -m)
    local eza_arch
    case "$arch" in
        x86_64) eza_arch="x86_64" ;;
        aarch64) eza_arch="aarch64" ;;
        *) log_warn "Unsupported architecture: $arch, falling back to cargo"; install_via_cargo; return ;;
    esac

    # Get latest release
    local api_url="https://api.github.com/repos/eza-community/eza/releases/latest"
    local release_info
    release_info=$(curl -s "$api_url")

    local version
    version=$(echo "$release_info" | jq -r '.tag_name' | sed 's/^v//')

    local download_url
    download_url=$(echo "$release_info" | jq -r ".assets[] | select(.name | contains(\"${eza_arch}\") and contains(\"linux\") and contains(\"musl\") and (contains(\".tar.gz\"))) | .browser_download_url" | head -1)

    if [[ -z "$download_url" || "$download_url" == "null" ]]; then
        log_warn "Could not find binary for $eza_arch, falling back to cargo"
        install_via_cargo
        return
    fi

    local tmp_dir
    tmp_dir=$(mktemp -d)
    cd "$tmp_dir"

    log_info "Downloading eza $version..."
    curl -L -o eza.tar.gz "$download_url"
    tar -xzf eza.tar.gz

    mkdir -p "$HOME/.local/bin"
    install -m755 eza "$EZA_BIN"

    cd /
    rm -rf "$tmp_dir"

    log_success "eza $version installed to $EZA_BIN"
}

setup_aliases() {
    local bashrc="$HOME/.bashrc"

    if ! grep -q "alias ls=" "$bashrc" 2>/dev/null || ! grep -q "eza" "$bashrc" 2>/dev/null; then
        log_info "Adding eza aliases to ~/.bashrc..."
        cat >> "$bashrc" << 'EOF'

# eza aliases (modern ls replacement)
if command -v eza &>/dev/null; then
    alias ls='eza'
    alias ll='eza -l'
    alias la='eza -la'
    alias lt='eza --tree'
    alias l='eza -l'
fi
EOF
    fi
}

main() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║            eza Installer (ls replacement)      ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}"
    echo ""

    # Check if jq is available for binary install
    if command -v jq &>/dev/null; then
        install_via_binary
    else
        log_warn "jq not found, using cargo installation"
        install_via_cargo
    fi

    setup_aliases

    echo ""
    log_success "eza installation complete!"
    echo ""
    echo "Run 'source ~/.bashrc' to activate aliases"
    echo ""
    echo "Usage:"
    echo "  ls   - List files with icons"
    echo "  ll   - Long list"
    echo "  la   - List all including hidden"
    echo "  lt   - Tree view"
    echo ""
}

main "$@"
