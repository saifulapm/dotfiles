#!/bin/bash
# Setup hibernation on Fedora with swap file
# Configures kernel resume parameters and regenerates initramfs

set -e

echo "=== Hibernate Setup for Fedora ==="
echo ""

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    echo "Don't run as root, script will use sudo when needed"
    exit 1
fi

# Check if hibernation is supported
if [[ ! -f /sys/power/image_size ]]; then
    echo "Error: Hibernation is not supported on this system"
    exit 1
fi

# Find swap file
SWAP_FILE=$(swapon --show=NAME --noheadings | head -1)
if [[ -z "$SWAP_FILE" ]]; then
    echo "Error: No swap file found. Create swap first."
    exit 1
fi

echo "Swap file: $SWAP_FILE"

# Check swap size vs RAM
SWAP_SIZE=$(swapon --show=SIZE --bytes --noheadings | head -1)
RAM_SIZE=$(free -b | awk '/Mem:/ {print $2}')

if [[ $SWAP_SIZE -lt $RAM_SIZE ]]; then
    echo ""
    echo "Warning: Swap ($((SWAP_SIZE/1024/1024/1024))GB) is smaller than RAM ($((RAM_SIZE/1024/1024/1024))GB)"
    echo "Hibernation may fail if RAM usage exceeds swap size"
    echo ""
    read -p "Continue anyway? [y/N] " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
fi

# Get partition UUID
SWAP_MOUNT=$(df "$SWAP_FILE" | awk 'NR==2 {print $6}')
SWAP_UUID=$(findmnt -no UUID "$SWAP_MOUNT")

if [[ -z "$SWAP_UUID" ]]; then
    echo "Error: Could not find UUID for $SWAP_MOUNT"
    exit 1
fi

echo "Partition UUID: $SWAP_UUID"

# Get swap file offset
SWAP_OFFSET=$(sudo filefrag -v "$SWAP_FILE" | awk 'NR==4 {print $4}' | sed 's/\.\.//')

if [[ -z "$SWAP_OFFSET" ]]; then
    echo "Error: Could not determine swap file offset"
    exit 1
fi

echo "Swap offset: $SWAP_OFFSET"

# Check current kernel cmdline
RESUME_PARAM="resume=UUID=$SWAP_UUID resume_offset=$SWAP_OFFSET"
echo ""
echo "Resume parameters: $RESUME_PARAM"

# Check if already configured
if grep -q "resume=" /proc/cmdline; then
    echo ""
    echo "Resume parameter already in kernel cmdline:"
    grep -o 'resume[^ ]*' /proc/cmdline
    echo ""
    read -p "Update anyway? [y/N] " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && exit 0
fi

# Backup grub config
GRUB_FILE="/etc/default/grub"
sudo cp "$GRUB_FILE" "$GRUB_FILE.bak.$(date +%Y%m%d%H%M%S)"

# Update GRUB_CMDLINE_LINUX
echo ""
echo "Updating $GRUB_FILE..."

# Remove old resume parameters if present
sudo sed -i 's/resume=[^ "]*//g; s/resume_offset=[^ "]*//g' "$GRUB_FILE"

# Add new resume parameters (check both GRUB_CMDLINE_LINUX and GRUB_CMDLINE_LINUX_DEFAULT)
if grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB_FILE"; then
    sudo sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=\"|GRUB_CMDLINE_LINUX_DEFAULT=\"$RESUME_PARAM |" "$GRUB_FILE"
    echo "Updated GRUB_CMDLINE_LINUX_DEFAULT:"
    grep '^GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB_FILE"
elif grep -q '^GRUB_CMDLINE_LINUX=' "$GRUB_FILE"; then
    sudo sed -i "s|^GRUB_CMDLINE_LINUX=\"|GRUB_CMDLINE_LINUX=\"$RESUME_PARAM |" "$GRUB_FILE"
    echo "Updated GRUB_CMDLINE_LINUX:"
    grep '^GRUB_CMDLINE_LINUX=' "$GRUB_FILE"
else
    echo "GRUB_CMDLINE_LINUX_DEFAULT=\"$RESUME_PARAM\"" | sudo tee -a "$GRUB_FILE"
    echo "Added GRUB_CMDLINE_LINUX_DEFAULT"
fi

# Regenerate grub config
echo ""
echo "Regenerating GRUB config..."
if [[ -d /sys/firmware/efi ]]; then
    sudo grub2-mkconfig -o /boot/efi/EFI/fedora/grub.cfg
else
    sudo grub2-mkconfig -o /boot/grub2/grub.cfg
fi

# Add resume to dracut
echo ""
echo "Configuring dracut for resume..."
echo 'add_dracutmodules+=" resume "' | sudo tee /etc/dracut.conf.d/resume.conf

# Regenerate initramfs
echo ""
echo "Regenerating initramfs (this may take a minute)..."
sudo dracut -f

echo ""
echo "=== Hibernate setup complete ==="
echo ""
echo "Reboot required for changes to take effect."
echo "After reboot, test with: systemctl hibernate"
