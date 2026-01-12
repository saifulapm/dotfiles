#!/bin/bash

# Install lazygit - terminal UI for git
# https://github.com/jesseduffield/lazygit

set -euo pipefail

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

INSTALL_DIR="$HOME/.local/bin"

main() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║            lazygit Installer                   ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}"
    echo ""

    mkdir -p "$INSTALL_DIR"

    # Get latest release
    log_info "Fetching latest lazygit release..."
    local api_url="https://api.github.com/repos/jesseduffield/lazygit/releases/latest"
    local release_info
    release_info=$(curl -s "$api_url")

    local version
    version=$(echo "$release_info" | jq -r '.tag_name' | sed 's/^v//')
    log_info "Latest version: $version"

    # Determine architecture
    local arch
    arch=$(uname -m)
    local lg_arch
    case "$arch" in
        x86_64) lg_arch="x86_64" ;;
        aarch64) lg_arch="arm64" ;;
        *) echo "Unsupported architecture: $arch"; exit 1 ;;
    esac

    # Download
    local download_url="https://github.com/jesseduffield/lazygit/releases/download/v${version}/lazygit_${version}_Linux_${lg_arch}.tar.gz"
    local tmp_dir
    tmp_dir=$(mktemp -d)

    log_info "Downloading lazygit..."
    curl -L -o "$tmp_dir/lazygit.tar.gz" "$download_url"

    log_info "Extracting..."
    tar -xzf "$tmp_dir/lazygit.tar.gz" -C "$tmp_dir"

    log_info "Installing to $INSTALL_DIR..."
    install -m755 "$tmp_dir/lazygit" "$INSTALL_DIR/lazygit"

    rm -rf "$tmp_dir"

    log_success "lazygit $version installed!"
    echo ""
    echo "Run 'lazygit' in any git repository to start"
    echo ""
}

main "$@"
