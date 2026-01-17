#!/bin/bash
# Setup x86-specific packages (GPU drivers, etc.)
# Only runs on x86_64 architecture

set -e

ARCH=$(uname -m)

# Only run on x86_64
if [[ "$ARCH" != "x86_64" ]]; then
    exit 0
fi

UPDATE_MODE=false
[[ "$1" == "--update" ]] && UPDATE_MODE=true

echo "Setting up x86-specific packages..."

# Detect GPU vendor
detect_gpu() {
    if lspci | grep -qi nvidia; then
        echo "nvidia"
    elif lspci | grep -qi "amd.*radeon\|amd.*graphics\|ati.*radeon"; then
        echo "amd"
    elif lspci | grep -qi "intel.*graphics\|intel.*uhd\|intel.*iris"; then
        echo "intel"
    else
        echo "unknown"
    fi
}

GPU_VENDOR=$(detect_gpu)
echo "Detected GPU: $GPU_VENDOR"

case "$GPU_VENDOR" in
    nvidia)
        # NVIDIA needs proprietary drivers for Ghostty/GPU acceleration
        # Requires RPMFusion non-free repository (already enabled by setup.sh)
        if ! rpm -q akmod-nvidia &>/dev/null || [[ "$UPDATE_MODE" == "true" ]]; then
            echo "Installing NVIDIA proprietary drivers..."
            sudo dnf install -y akmod-nvidia
            # Optionally install CUDA support
            # sudo dnf install -y xorg-x11-drv-nvidia-cuda
            echo "NVIDIA drivers installed. Reboot required for changes to take effect."
        else
            echo "NVIDIA drivers already installed"
        fi
        ;;
    amd)
        # AMD uses Mesa drivers (usually pre-installed on Fedora)
        # Ensure Vulkan support is installed for better performance
        if ! rpm -q mesa-vulkan-drivers &>/dev/null || [[ "$UPDATE_MODE" == "true" ]]; then
            echo "Installing AMD Mesa Vulkan drivers..."
            sudo dnf install -y mesa-vulkan-drivers mesa-va-drivers
            echo "AMD drivers configured"
        else
            echo "AMD Mesa drivers already installed"
        fi
        ;;
    intel)
        # Intel uses Mesa drivers (usually pre-installed on Fedora)
        # Ensure Vulkan support is installed
        if ! rpm -q mesa-vulkan-drivers &>/dev/null || [[ "$UPDATE_MODE" == "true" ]]; then
            echo "Installing Intel Mesa Vulkan drivers..."
            sudo dnf install -y mesa-vulkan-drivers intel-media-driver
            echo "Intel drivers configured"
        else
            echo "Intel Mesa drivers already installed"
        fi
        ;;
    *)
        echo "Unknown GPU vendor, skipping driver installation"
        echo "You may need to manually install GPU drivers for Ghostty to work properly"
        ;;
esac

echo "x86 setup complete"
