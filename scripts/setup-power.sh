#!/bin/bash

# Power management setup:
# - Auto power profile switching (AC vs battery)
# - WiFi power save disable on AC
# - System sleep hooks (FUSE unmount, keyboard backlight)
# - Faster shutdown timeout

DOTFILES="${DOTFILES:-$HOME/.dotfiles}"

# ── Power profile switching (udev rules) ──
if nova-battery-present 2>/dev/null; then
    mapfile -t profiles < <(nova-powerprofiles-list 2>/dev/null)

    if (( ${#profiles[@]} > 1 )); then
        ac_profile="${profiles[2]:-${profiles[1]}}"
        battery_profile="${profiles[1]}"

        cat <<EOF | sudo tee "/etc/udev/rules.d/99-power-profile.rules" >/dev/null
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="0", RUN+="/usr/bin/powerprofilesctl set $battery_profile"
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="1", RUN+="/usr/bin/powerprofilesctl set $ac_profile"
EOF
        sudo udevadm control --reload 2>/dev/null
    fi
fi

# ── WiFi power save udev rule ──
if [[ ! -f /etc/udev/rules.d/99-wifi-powersave.rules ]]; then
    NOVA_WIFI=$(command -v nova-wifi-powersave)
    if [[ -n "$NOVA_WIFI" ]]; then
        cat <<EOF | sudo tee "/etc/udev/rules.d/99-wifi-powersave.rules" >/dev/null
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="1", RUN+="$NOVA_WIFI off"
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="0", RUN+="$NOVA_WIFI on"
EOF
    fi
fi

# ── System sleep hooks ──
SLEEP_DIR="/usr/lib/systemd/system-sleep"

# FUSE unmount before suspend
if [[ ! -f "$SLEEP_DIR/unmount-fuse" ]]; then
    sudo install -m 755 "$DOTFILES/config/systemd/system-sleep/unmount-fuse" "$SLEEP_DIR/unmount-fuse" 2>/dev/null || true
fi

# Keyboard backlight off before hibernate
if [[ ! -f "$SLEEP_DIR/keyboard-backlight" ]]; then
    sudo install -m 755 "$DOTFILES/config/systemd/system-sleep/keyboard-backlight" "$SLEEP_DIR/keyboard-backlight" 2>/dev/null || true
fi

# ── Disable suspend/hibernate (Asahi Linux wake issues) ──
if ! systemctl is-enabled sleep.target &>/dev/null 2>&1 || \
   systemctl status sleep.target 2>&1 | grep -q "masked"; then
    : # Already masked
else
    sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target 2>/dev/null || true
fi

# ── Faster shutdown ──
SHUTDOWN_CONF="/etc/systemd/system.conf.d/faster-shutdown.conf"
if [[ ! -f "$SHUTDOWN_CONF" ]]; then
    sudo mkdir -p "$(dirname "$SHUTDOWN_CONF")"
    printf '[Manager]\nDefaultTimeoutStopSec=5s\n' | sudo tee "$SHUTDOWN_CONF" >/dev/null
    sudo systemctl daemon-reload 2>/dev/null || true
fi
