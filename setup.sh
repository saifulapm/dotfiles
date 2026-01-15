#!/bin/bash

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Cache sudo credentials upfront
echo "This script requires sudo access."
sudo -v || exit 1
# Keep sudo alive in background
(while true; do sudo -n true; sleep 50; done) &
SUDO_PID=$!
trap "kill $SUDO_PID 2>/dev/null" EXIT

# Install gum if not present
if ! command -v gum &>/dev/null; then
    echo "Installing gum..."
    sudo dnf install -y gum &>/dev/null
fi

read_list() {
    local file="$1"
    [[ -f "$file" ]] && grep -v '^#' "$file" | grep -v '^$' || true
}

header() {
    echo ""
    gum style --foreground 12 --bold "[$1]"
}

done_msg() {
    gum style --foreground 10 "  ✓ $1"
}

skip_msg() {
    gum style --foreground 11 "  ○ $1"
}

spin() {
    gum spin --spinner dot --title "$1" -- "${@:2}"
}

# Check if symlink points to correct target
is_linked() {
    local target="$1"
    local link="$2"
    [[ -L "$link" && "$(readlink "$link")" == "$target" ]]
}


# Banner
echo ""
gum style --border rounded --padding "0 2" --border-foreground 14 --bold "Fedora Asahi Setup"
echo ""

# ─────────────────────────────────────────────────────────────
# COPR Repositories
# ─────────────────────────────────────────────────────────────
if [[ -f "$DOTFILES/copr.list" ]]; then
    repos=$(read_list "$DOTFILES/copr.list")
    if [[ -n "$repos" ]]; then
        header "COPR Repositories"
        count=0
        while IFS= read -r repo; do
            if ! dnf repolist | grep -q "${repo##*/}"; then
                echo -n "  Enabling $repo... "
                sudo dnf copr enable -y "$repo" >/dev/null 2>&1 && echo "done" || echo "failed"
                ((count++))
            fi
        done <<< "$repos"
        done_msg "$count repos enabled"
    fi
fi

# ─────────────────────────────────────────────────────────────
# RPMFusion Repository
# ─────────────────────────────────────────────────────────────
header "RPMFusion Repository"
if ! rpm -q rpmfusion-free-release &>/dev/null; then
    echo -n "  Enabling RPMFusion Free... "
    sudo dnf install -y "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" && echo "done" || echo "failed"
    echo -n "  Enabling RPMFusion Non-Free... "
    sudo dnf install -y "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm" && echo "done" || echo "failed"
    done_msg "RPMFusion enabled"
else
    skip_msg "RPMFusion already enabled"
fi

# ─────────────────────────────────────────────────────────────
# FFmpeg (from RPMFusion, replaces free versions)
# ─────────────────────────────────────────────────────────────
if ! rpm -q ffmpeg &>/dev/null; then
    header "FFmpeg"
    spin "  Installing ffmpeg (RPMFusion)" sudo dnf install -y --allowerasing ffmpeg ffmpeg-libs ffmpeg-devel
    done_msg "ffmpeg installed"
fi

# ─────────────────────────────────────────────────────────────
# DNF Packages
# ─────────────────────────────────────────────────────────────
if [[ -f "$DOTFILES/packages.list" ]]; then
    packages=$(read_list "$DOTFILES/packages.list")
    if [[ -n "$packages" ]]; then
        header "DNF Packages"
        installed=0
        skipped=0
        while IFS= read -r pkg; do
            if ! rpm -q "$pkg" &>/dev/null; then
                spin "  Installing $pkg" sudo dnf install -y "$pkg"
                ((installed++))
            else
                ((skipped++))
            fi
        done <<< "$packages"
        done_msg "$installed installed, $skipped skipped"
    fi
fi

# ─────────────────────────────────────────────────────────────
# Flatpak Packages
# ─────────────────────────────────────────────────────────────
if [[ -f "$DOTFILES/flatpak.list" ]]; then
    flatpaks=$(read_list "$DOTFILES/flatpak.list")
    if [[ -n "$flatpaks" ]]; then
        header "Flatpak Packages"
        if ! command -v flatpak &>/dev/null; then
            spin "  Installing Flatpak" sudo dnf install -y flatpak
            flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
        fi
        installed=0
        skipped=0
        while IFS= read -r pkg; do
            if ! flatpak list --app | grep -q "$pkg"; then
                spin "  Installing $pkg" flatpak install -y flathub "$pkg"
                ((installed++))
            else
                ((skipped++))
            fi
        done <<< "$flatpaks"
        done_msg "$installed installed, $skipped skipped"
    fi
fi

# ─────────────────────────────────────────────────────────────
# Snap Packages
# ─────────────────────────────────────────────────────────────
if [[ -f "$DOTFILES/snap.list" ]]; then
    snaps=$(read_list "$DOTFILES/snap.list")
    if [[ -n "$snaps" ]]; then
        header "Snap Packages"
        if ! command -v snap &>/dev/null; then
            spin "  Installing Snapd" sudo dnf install -y snapd
            sudo ln -sf /var/lib/snapd/snap /snap 2>/dev/null || true
        fi
        installed=0
        skipped=0
        while IFS= read -r pkg; do
            pkg_name=$(echo "$pkg" | awk '{print $1}')
            if ! snap list "$pkg_name" &>/dev/null; then
                spin "  Installing $pkg_name" sudo snap install $pkg
                ((installed++))
            else
                ((skipped++))
            fi
        done <<< "$snaps"
        done_msg "$installed installed, $skipped skipped"
    fi
fi

# ─────────────────────────────────────────────────────────────
# Fonts
# ─────────────────────────────────────────────────────────────
if [[ -d "$DOTFILES/fonts" ]]; then
    shopt -s nullglob
    fonts=("$DOTFILES/fonts"/*)
    shopt -u nullglob

    header "Fonts"
    mkdir -p ~/.local/share/fonts
    installed=0
    skipped=0
    for font in "${fonts[@]}"; do
        name=$(basename "$font")
        [[ "$name" == ".gitkeep" ]] && continue
        if [[ ! -e "$HOME/.local/share/fonts/$name" ]]; then
            cp -r "$font" ~/.local/share/fonts/
            ((installed++))
        else
            ((skipped++))
        fi
    done
    if [[ $installed -gt 0 ]]; then
        spin "  Updating font cache" fc-cache -f
    fi
    done_msg "$installed installed, $skipped skipped"
fi

# ─────────────────────────────────────────────────────────────
# Cargo Packages
# ─────────────────────────────────────────────────────────────
if [[ -f "$DOTFILES/cargo.list" ]]; then
    cargo_pkgs=$(read_list "$DOTFILES/cargo.list")
    if [[ -n "$cargo_pkgs" ]]; then
        header "Cargo Packages"
        if ! command -v cargo &>/dev/null; then
            spin "  Installing Rust" bash -c 'curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y 2>/dev/null'
            source "$HOME/.cargo/env"
        fi
        installed=0
        skipped=0
        while IFS= read -r pkg; do
            if ! command -v "$pkg" &>/dev/null; then
                spin "  Installing $pkg" cargo install "$pkg" 2>/dev/null || true
                ((installed++))
            else
                ((skipped++))
            fi
        done <<< "$cargo_pkgs"
        done_msg "$installed installed, $skipped skipped"
    fi
fi

# ─────────────────────────────────────────────────────────────
# Go Packages
# ─────────────────────────────────────────────────────────────
if [[ -f "$DOTFILES/go.list" ]]; then
    go_pkgs=$(read_list "$DOTFILES/go.list")
    if [[ -n "$go_pkgs" ]]; then
        header "Go Packages"
        if ! command -v go &>/dev/null; then
            spin "  Installing Go" sudo dnf install -y golang 2>/dev/null
        fi
        if command -v go &>/dev/null; then
            installed=0
            skipped=0
            while IFS= read -r pkg; do
                name=$(basename "$pkg" | cut -d'@' -f1)
                if ! command -v "$name" &>/dev/null; then
                    spin "  Installing $name" go install "$pkg" 2>/dev/null || true
                    ((installed++))
                else
                    ((skipped++))
                fi
            done <<< "$go_pkgs"
            done_msg "$installed installed, $skipped skipped"
        fi
    fi
fi

# ─────────────────────────────────────────────────────────────
# Config Symlinks (~/.config)
# ─────────────────────────────────────────────────────────────
if [[ -d "$DOTFILES/config" ]]; then
    shopt -s nullglob
    configs=("$DOTFILES/config"/*)
    shopt -u nullglob

    header "Config Symlinks"
    mkdir -p ~/.config
    linked=0
    skipped=0
    for item in "${configs[@]}"; do
        name=$(basename "$item")
        # Skip directories that are generated by theme script or handled separately
        [[ "$name" == "home" || "$name" == "systemd" ]] && continue
        if ! is_linked "$item" "$HOME/.config/$name"; then
            rm -rf "$HOME/.config/$name"
            ln -sf "$item" "$HOME/.config/$name"
            ((linked++))
        else
            ((skipped++))
        fi
    done
    done_msg "$linked linked, $skipped skipped"
fi

# ─────────────────────────────────────────────────────────────
# Home Directory Dotfiles
# ─────────────────────────────────────────────────────────────
if [[ -d "$DOTFILES/config/home" ]]; then
    shopt -s nullglob
    home_files=("$DOTFILES/config/home"/*)
    shopt -u nullglob
    if [[ ${#home_files[@]} -gt 0 ]]; then
        header "Home Dotfiles"
        linked=0
        skipped=0
        for item in "${home_files[@]}"; do
            name=$(basename "$item")
            if ! is_linked "$item" "$HOME/$name"; then
                rm -rf "$HOME/$name"
                ln -sf "$item" "$HOME/$name"
                ((linked++))
            else
                ((skipped++))
            fi
        done
        done_msg "$linked linked, $skipped skipped"
    fi
fi

# ─────────────────────────────────────────────────────────────
# Partial Symlinks
# ─────────────────────────────────────────────────────────────
if [[ -f "$DOTFILES/symlinks.list" ]]; then
    symlinks=$(read_list "$DOTFILES/symlinks.list")
    if [[ -n "$symlinks" ]]; then
        header "Partial Symlinks"
        linked=0
        skipped=0
        while IFS=: read -r src dest; do
            [[ -z "$src" || -z "$dest" ]] && continue
            src_path="$DOTFILES/$src"
            dest_path="$HOME/$dest"
            if [[ -e "$src_path" ]]; then
                if ! is_linked "$src_path" "$dest_path"; then
                    mkdir -p "$(dirname "$dest_path")"
                    rm -rf "$dest_path"
                    ln -sf "$src_path" "$dest_path"
                    ((linked++))
                else
                    ((skipped++))
                fi
            fi
        done <<< "$symlinks"
        done_msg "$linked linked, $skipped skipped"
    fi
fi

# ─────────────────────────────────────────────────────────────
# Custom Executables
# ─────────────────────────────────────────────────────────────
if [[ -d "$DOTFILES/bin" ]]; then
    shopt -s nullglob
    bins=("$DOTFILES/bin"/*)
    shopt -u nullglob

    header "Custom Executables"
    mkdir -p ~/.local/bin
    linked=0
    skipped=0
    for script in "${bins[@]}"; do
        [[ -f "$script" ]] || continue
        name=$(basename "$script")
        [[ "$name" == ".gitkeep" ]] && continue
        chmod +x "$script"
        if ! is_linked "$script" "$HOME/.local/bin/$name"; then
            ln -sf "$script" ~/.local/bin/"$name"
            ((linked++))
        else
            ((skipped++))
        fi
    done
    done_msg "$linked linked, $skipped skipped"
fi

# ─────────────────────────────────────────────────────────────
# Custom Scripts (always run for updates)
# ─────────────────────────────────────────────────────────────
if [[ -d "$DOTFILES/scripts" ]]; then
    shopt -s nullglob
    scripts=("$DOTFILES/scripts"/*.sh)
    shopt -u nullglob
    if [[ ${#scripts[@]} -gt 0 ]]; then
        header "Running Scripts"
        count=0
        for script in "${scripts[@]}"; do
            [[ -f "$script" ]] || continue
            name=$(basename "$script")
            chmod +x "$script"
            spin "  Running $name" "$script" || true
            ((count++))
        done
        done_msg "$count scripts completed"
    fi
fi

# ─────────────────────────────────────────────────────────────
# Theme Setup
# ─────────────────────────────────────────────────────────────
if [[ -x "$DOTFILES/bin/theme" ]]; then
    header "Theme Setup"
    # Apply default theme if not set
    if [[ ! -f "$HOME/.config/nova/current/theme.name" ]]; then
        spin "  Applying catppuccin theme" "$DOTFILES/bin/theme" set catppuccin
        done_msg "Default theme applied"
    else
        current_theme=$(cat "$HOME/.config/nova/current/theme.name")
        skip_msg "Theme already set: $current_theme"
    fi
fi

# ─────────────────────────────────────────────────────────────
# Done
# ─────────────────────────────────────────────────────────────
echo ""
gum style --foreground 10 --bold "✓ Setup complete!"
echo ""
