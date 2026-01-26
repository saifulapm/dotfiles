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


# Detect architecture for banner
ARCH=$(uname -m)
if [[ "$ARCH" == "aarch64" ]]; then
    BANNER_TEXT="Fedora Asahi Setup"
else
    BANNER_TEXT="Fedora Setup"
fi

# Banner
echo ""
gum style --border rounded --padding "0 2" --border-foreground 14 --bold "$BANNER_TEXT"
echo ""

# ─────────────────────────────────────────────────────────────
# COPR Repositories
# ─────────────────────────────────────────────────────────────
if [[ -f "$DOTFILES/copr.list" ]]; then
    repos=$(read_list "$DOTFILES/copr.list")
    if [[ -n "$repos" ]]; then
        header "COPR Repositories"
        # Ensure copr plugin is available
        if ! rpm -q dnf-plugins-core &>/dev/null; then
            spin "  Installing dnf-plugins-core" sudo dnf install -y dnf-plugins-core
        fi
        count=0
        while IFS= read -r repo; do
            if ! dnf repolist | grep -q "${repo##*/}"; then
                spin "  Enabling $repo" sudo dnf -y copr enable "$repo"
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
    spin "  Enabling RPMFusion Free" sudo dnf install -y "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm"
    spin "  Enabling RPMFusion Non-Free" sudo dnf install -y "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"
    done_msg "RPMFusion enabled"
else
    skip_msg "RPMFusion already enabled"
fi

# Function to add dnf config if not present in a file
add_config_if_not_present() {
  local file="$1"
  local config="$2"
  grep -qF "$config" "$file" || echo "$config" | sudo tee -a "$file" >/dev/null
}

# Check and add configuration settings to /etc/dnf/dnf.conf
add_config_if_not_present "/etc/dnf/dnf.conf" "max_parallel_downloads=5"
add_config_if_not_present "/etc/dnf/dnf.conf" "fastestmirror=True"
add_config_if_not_present "/etc/dnf/dnf.conf" "defaultyes=True"

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
        fi

	# Ensure Flathub remote exists
        if ! flatpak remotes --columns=name | grep -qx flathub; then
            spin "  Adding Flathub remote" flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
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
        fi
        # Always source cargo env if it exists (needed even if system cargo was found)
        [[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
        installed=0
        skipped=0
        while IFS= read -r pkg; do
            if ! command -v "$pkg" &>/dev/null; then
                spin "  Installing $pkg" cargo install "$pkg" || true
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
# Pip Packages
# ─────────────────────────────────────────────────────────────
if [[ -f "$DOTFILES/pip.list" ]]; then
    pip_pkgs=$(read_list "$DOTFILES/pip.list")
    if [[ -n "$pip_pkgs" ]]; then
        header "Pip Packages"
        if ! command -v pip3 &>/dev/null; then
            spin "  Installing python3-pip" sudo dnf install -y python3-pip
        fi
        installed=0
        skipped=0
        while IFS= read -r pkg; do
            if ! pip3 show "$pkg" &>/dev/null; then
                spin "  Installing $pkg" pip3 install --user "$pkg" || true
                ((installed++))
            else
                ((skipped++))
            fi
        done <<< "$pip_pkgs"
        done_msg "$installed installed, $skipped skipped"
    fi
fi

# ─────────────────────────────────────────────────────────────
# NPM Packages
# ─────────────────────────────────────────────────────────────
if [[ -f "$DOTFILES/npm.list" ]]; then
    npm_pkgs=$(read_list "$DOTFILES/npm.list")
    if [[ -n "$npm_pkgs" ]]; then
        header "NPM Packages"
        if ! command -v npm &>/dev/null; then
            spin "  Installing nodejs-npm" sudo dnf install -y nodejs-npm
        fi
        installed=0
        skipped=0
        while IFS= read -r pkg; do
            if ! npm list -g "$pkg" &>/dev/null; then
                spin "  Installing $pkg" npm install -g "$pkg" || true
                ((installed++))
            else
                ((skipped++))
            fi
        done <<< "$npm_pkgs"
        done_msg "$installed installed, $skipped skipped"
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
    shopt -s nullglob dotglob
    home_files=("$DOTFILES/config/home"/*)
    shopt -u nullglob dotglob
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
