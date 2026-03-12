# Omarchy Sync Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sync selected features from omarchy upstream into our dotfiles, adapting `omarchy-*` → `nova-*` naming.

**Architecture:** 8 independent tasks, each producing a commit. Shell functions/aliases first (no deps), then tmux (uses new aliases), then standalone tasks (power, battery, waybar, screenrecord, bg-selector), then theme sync last (large file ops).

**Tech Stack:** Bash, tmux, systemd, waybar (JSON/CSS), niri (KDL), swaybg, fuzzel, mako, wf-recorder

**Spec:** `docs/omarchy-sync-plan.md`

---

## Chunk 1: Shell, Tmux, Power, Battery

### Task 1: Shell Functions & Aliases

**Files:**
- Modify: `shell/functions` (append new sections)
- Modify: `shell/aliases` (add 3 aliases)

- [ ] **Step 1: Add git worktree functions to `shell/functions`**

Append to end of `shell/functions`:

```bash
# ─────────────────────────────────────────────────────────────
# Git Worktrees
# ─────────────────────────────────────────────────────────────

# Create a new worktree and branch from within current git directory
ga() {
    if [[ -z "$1" ]]; then
        echo "Usage: ga [branch name]"
        return 1
    fi

    local branch="$1"
    local base="$(basename "$PWD")"
    local path="../${base}--${branch}"

    git worktree add -b "$branch" "$path"
    mise trust "$path" 2>/dev/null || true
    cd "$path"
}

# Remove worktree and branch from within active worktree directory
gd() {
    if gum confirm "Remove worktree and branch?"; then
        local cwd base branch root worktree

        cwd="$(pwd)"
        worktree="$(basename "$cwd")"

        root="${worktree%%--*}"
        branch="${worktree#*--}"

        if [[ "$root" != "$worktree" ]]; then
            cd "../$root"
            git worktree remove "$cwd" --force || return 1
            git branch -D "$branch"
        fi
    fi
}
```

- [ ] **Step 2: Add SSH port forwarding functions to `shell/functions`**

Append:

```bash
# ─────────────────────────────────────────────────────────────
# SSH Port Forwarding
# ─────────────────────────────────────────────────────────────

# Forward ports over SSH
fip() {
    (( $# < 2 )) && echo "Usage: fip <host> <port1> [port2] ..." && return 1
    local host="$1"
    shift
    for port in "$@"; do
        ssh -f -N -L "$port:localhost:$port" "$host" && echo "Forwarding localhost:$port -> $host:$port"
    done
}

# Disconnect forwarded ports
dip() {
    (( $# == 0 )) && echo "Usage: dip <port1> [port2] ..." && return 1
    for port in "$@"; do
        pkill -f "ssh.*-L $port:localhost:$port" && echo "Stopped forwarding port $port" || echo "No forwarding on port $port"
    done
}

# List active port forwards
lip() {
    pgrep -af "ssh.*-L [0-9]+:localhost:[0-9]+" || echo "No active forwards"
}
```

- [ ] **Step 3: Add tmux layout functions to `shell/functions`**

Append:

```bash
# ─────────────────────────────────────────────────────────────
# Tmux Layouts
# ─────────────────────────────────────────────────────────────

# Create a Tmux Dev Layout with editor, ai, and terminal
# Usage: tdl <c|cx|codex|other_ai> [<second_ai>]
tdl() {
    [[ -z $1 ]] && { echo "Usage: tdl <c|cx|codex|other_ai> [<second_ai>]"; return 1; }
    [[ -z $TMUX ]] && { echo "You must start tmux to use tdl."; return 1; }

    local current_dir="${PWD}"
    local editor_pane ai_pane ai2_pane
    local ai="$1"
    local ai2="$2"

    editor_pane="$TMUX_PANE"
    tmux rename-window -t "$editor_pane" "$(basename "$current_dir")"
    tmux split-window -v -p 15 -t "$editor_pane" -c "$current_dir"
    ai_pane=$(tmux split-window -h -p 30 -t "$editor_pane" -c "$current_dir" -P -F '#{pane_id}')

    if [[ -n $ai2 ]]; then
        ai2_pane=$(tmux split-window -v -t "$ai_pane" -c "$current_dir" -P -F '#{pane_id}')
        tmux send-keys -t "$ai2_pane" "$ai2" C-m
    fi

    tmux send-keys -t "$ai_pane" "$ai" C-m
    tmux send-keys -t "$editor_pane" "$EDITOR ." C-m
    tmux select-pane -t "$editor_pane"
}

# Create multiple tdl windows with one per subdirectory
# Usage: tdlm <c|cx|codex|other_ai> [<second_ai>]
tdlm() {
    [[ -z $1 ]] && { echo "Usage: tdlm <c|cx|codex|other_ai> [<second_ai>]"; return 1; }
    [[ -z $TMUX ]] && { echo "You must start tmux to use tdlm."; return 1; }

    local ai="$1"
    local ai2="$2"
    local base_dir="$PWD"
    local first=true

    tmux rename-session "$(basename "$base_dir" | tr '.:' '--')"

    for dir in "$base_dir"/*/; do
        [[ -d $dir ]] || continue
        local dirpath="${dir%/}"

        if $first; then
            tmux send-keys -t "$TMUX_PANE" "cd '$dirpath' && tdl $ai $ai2" C-m
            first=false
        else
            local pane_id=$(tmux new-window -c "$dirpath" -P -F '#{pane_id}')
            tmux send-keys -t "$pane_id" "tdl $ai $ai2" C-m
        fi
    done
}

# Create a multi-pane swarm layout running same command in each pane
# Usage: tsl <pane_count> <command>
tsl() {
    [[ -z $1 || -z $2 ]] && { echo "Usage: tsl <pane_count> <command>"; return 1; }
    [[ -z $TMUX ]] && { echo "You must start tmux to use tsl."; return 1; }

    local count="$1"
    local cmd="$2"
    local current_dir="${PWD}"
    local -a panes

    tmux rename-window -t "$TMUX_PANE" "$(basename "$current_dir")"
    panes+=("$TMUX_PANE")

    while (( ${#panes[@]} < count )); do
        local new_pane
        local split_target="${panes[-1]}"
        new_pane=$(tmux split-window -h -t "$split_target" -c "$current_dir" -P -F '#{pane_id}')
        panes+=("$new_pane")
        tmux select-layout -t "${panes[0]}" tiled
    done

    for pane in "${panes[@]}"; do
        tmux send-keys -t "$pane" "$cmd" C-m
    done

    tmux select-pane -t "${panes[0]}"
}

# fzf pick a file then scp to remote
sff() {
    if [[ $# -eq 0 ]]; then
        echo "Usage: sff <destination> (e.g. sff host:/tmp/)"
        return 1
    fi
    local file
    file=$(find . -type f -printf '%T@\t%p\n' | sort -rn | cut -f2- | ff) && [[ -n "$file" ]] && scp "$file" "$1"
}
```

- [ ] **Step 4: Add new aliases to `shell/aliases`**

Add after the `ff` alias line (after `alias ff=...`):

```bash
alias eff='$EDITOR "$(ff)"'        # open fzf result in editor
```

Add in the Tools section (after existing tool aliases):

```bash
alias cx='claude --dangerously-skip-permissions'
alias t='tmux attach || tmux new -s Work'
```

- [ ] **Step 5: Verify syntax and commit**

```bash
bash -n shell/functions && bash -n shell/aliases && echo "OK"
git add shell/functions shell/aliases
git commit -m "feat: add git worktrees, SSH forwarding, tmux layouts, and new aliases

Synced from omarchy: ga/gd worktrees, fip/dip/lip SSH forwarding,
tdl/tdlm/tsl tmux layouts, sff remote file copy, eff/cx/t aliases."
```

---

### Task 2: Tmux Integration

**Files:**
- Create: `config/tmux/tmux.conf`
- Modify: `config/niri/binds.kdl` (add keybinding)

Note: `tmux` is already in `packages.list`.

- [ ] **Step 1: Create tmux config**

Create `config/tmux/tmux.conf` adapted from omarchy — uses hardcoded blue theme (no template needed since omarchy doesn't template it either):

```bash
# Prefix
set -g prefix C-Space
set -g prefix2 C-b
bind C-Space send-prefix

# Reload config
bind q source-file ~/.config/tmux/tmux.conf \; display "Configuration reloaded"

# Vi mode for copy
setw -g mode-keys vi
bind -T copy-mode-vi v send -X begin-selection
bind -T copy-mode-vi y send -X copy-selection-and-cancel

# Pane Controls
bind h split-window -v -c "#{pane_current_path}"
bind v split-window -h -c "#{pane_current_path}"
bind x kill-pane

bind -n C-M-Left select-pane -L
bind -n C-M-Right select-pane -R
bind -n C-M-Up select-pane -U
bind -n C-M-Down select-pane -D

bind -n C-M-S-Left resize-pane -L 5
bind -n C-M-S-Down resize-pane -D 5
bind -n C-M-S-Up resize-pane -U 5
bind -n C-M-S-Right resize-pane -R 5

# Window navigation
bind r command-prompt -I "#W" "rename-window -- '%%'"
bind c new-window -c "#{pane_current_path}"
bind k kill-window

bind -n M-1 select-window -t 1
bind -n M-2 select-window -t 2
bind -n M-3 select-window -t 3
bind -n M-4 select-window -t 4
bind -n M-5 select-window -t 5
bind -n M-6 select-window -t 6
bind -n M-7 select-window -t 7
bind -n M-8 select-window -t 8
bind -n M-9 select-window -t 9

bind -n M-Left select-window -t -1
bind -n M-Right select-window -t +1
bind -n M-S-Left swap-window -t -1 \; select-window -t -1
bind -n M-S-Right swap-window -t +1 \; select-window -t +1

# Session controls
bind R command-prompt -I "#S" "rename-session -- '%%'"
bind C new-session -c "#{pane_current_path}"
bind K kill-session
bind P switch-client -p
bind N switch-client -n

bind -n M-Up switch-client -p
bind -n M-Down switch-client -n

# General
set -g default-terminal "tmux-256color"
set -ag terminal-overrides ",foot*:RGB,*:RGB"
set -g mouse on
set -g base-index 1
setw -g pane-base-index 1
set -g renumber-windows on
set -g history-limit 50000
set -g escape-time 0
set -g focus-events on
set -g set-clipboard on
set -g allow-passthrough on
setw -g aggressive-resize on
set -g detach-on-destroy off

# Status bar
set -g status-position top
set -g status-interval 5
set -g status-left-length 30
set -g status-right-length 50
set -g window-status-separator ""
set -gw automatic-rename on
set -gw automatic-rename-format '#{b:pane_current_path}'

# Theme
set -g status-style "bg=default,fg=default"
set -g status-left "#[fg=black,bg=blue,bold] #S #[bg=default] "
set -g status-right "#[fg=blue]#{?client_prefix,PREFIX ,}#{?window_zoomed_flag,ZOOM ,}#[fg=brightblack]#h "
set -g window-status-format "#[fg=brightblack] #I:#W "
set -g window-status-current-format "#[fg=blue,bold] #I:#W "
set -g pane-border-style "fg=brightblack"
set -g pane-active-border-style "fg=blue"
set -g message-style "bg=default,fg=blue"
set -g message-command-style "bg=default,fg=blue"
set -g mode-style "bg=blue,fg=black"
setw -g clock-mode-colour blue
```

Note: Added `foot*:RGB` to terminal-overrides for foot compatibility.

- [ ] **Step 2: Add tmux keybinding to niri binds**

Add after the terminal keybinding (after `Mod+T` line, around line 9) in `config/niri/binds.kdl`:

```kdl
    Mod+Alt+Return hotkey-overlay-title="Tmux Terminal" { spawn "footclient" "bash" "-c" "tmux attach || tmux new -s Work"; }
```

- [ ] **Step 3: Commit**

```bash
git add config/tmux/tmux.conf config/niri/binds.kdl
git commit -m "feat: add tmux config with C-Space prefix and niri keybinding

Vi copy mode, Ctrl+Alt+Arrow pane navigation, Alt+N window switching,
auto-rename windows to cwd. Super+Alt+Return launches tmux in foot."
```

---

### Task 3: Power Management

**Files:**
- Create: `scripts/setup-power.sh`
- Create: `bin/nova-wifi-powersave`
- Create: `bin/nova-powerprofiles-list`

- [ ] **Step 1: Create `bin/nova-powerprofiles-list`**

```bash
#!/bin/bash

# Returns available power profiles (used by setup-power.sh)
powerprofilesctl list |
  awk '/^\s*[* ]\s*[a-zA-Z0-9\-]+:$/ { gsub(/^[*[:space:]]+|:$/,""); print }' |
  tac
```

- [ ] **Step 2: Create `bin/nova-wifi-powersave`**

```bash
#!/bin/bash
for iface in /sys/class/net/*/wireless; do
  iface="$(basename "$(dirname "$iface")")"
  iw dev "$iface" set power_save "$1" 2>/dev/null
done
```

- [ ] **Step 3: Create `scripts/setup-power.sh`**

This script is run by `setup.sh` automatically (it runs all `scripts/*.sh`).

```bash
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

# ── Faster shutdown ──
SHUTDOWN_CONF="/etc/systemd/system.conf.d/faster-shutdown.conf"
if [[ ! -f "$SHUTDOWN_CONF" ]]; then
    sudo mkdir -p "$(dirname "$SHUTDOWN_CONF")"
    printf '[Manager]\nDefaultTimeoutStopSec=5s\n' | sudo tee "$SHUTDOWN_CONF" >/dev/null
    sudo systemctl daemon-reload 2>/dev/null || true
fi
```

- [ ] **Step 4: Create systemd sleep hook source files**

Create `config/systemd/system-sleep/unmount-fuse`:

```bash
#!/bin/bash

# Lazy-unmount gvfsd-fuse filesystems before suspend/hibernate
if [[ $1 == "pre" ]]; then
  while IFS=' ' read -r _ mountpoint fstype _; do
    if [[ $fstype == fuse.gvfsd-fuse ]]; then
      mountpoint=$(printf '%b' "$mountpoint")
      fusermount3 -uz "$mountpoint" 2>/dev/null || fusermount -uz "$mountpoint" 2>/dev/null || true
    fi
  done < /proc/mounts
fi

if [[ $1 == "post" ]]; then
  (
    sleep 5
    for uid_dir in /run/user/*; do
      uid=$(basename "$uid_dir")
      if [[ -S $uid_dir/bus ]]; then
        sudo -u "#$uid" env \
          DBUS_SESSION_BUS_ADDRESS="unix:path=$uid_dir/bus" \
          XDG_RUNTIME_DIR="$uid_dir" \
          systemctl --user restart gvfs-daemon.service 2>/dev/null || true
      fi
    done
  ) &
  disown
fi
```

Create `config/systemd/system-sleep/keyboard-backlight`:

```bash
#!/bin/bash

# Turn off keyboard backlight before hibernate
if [[ $1 == "pre" && $2 == "hibernate" ]]; then
  device=""
  for candidate in /sys/class/leds/*kbd_backlight*; do
    if [[ -e "$candidate" ]]; then
      device="$(basename "$candidate")"
      break
    fi
  done

  if [[ -n "$device" ]]; then
    brightnessctl -d "$device" set 0 >/dev/null 2>&1
  fi
fi
```

- [ ] **Step 5: Commit**

```bash
chmod +x bin/nova-wifi-powersave bin/nova-powerprofiles-list scripts/setup-power.sh config/systemd/system-sleep/unmount-fuse config/systemd/system-sleep/keyboard-backlight
git add bin/nova-wifi-powersave bin/nova-powerprofiles-list scripts/setup-power.sh config/systemd/system-sleep/
git commit -m "feat: add power management setup

Auto power profile switching (AC/battery), WiFi power save control,
system sleep hooks (FUSE unmount, keyboard backlight), faster shutdown."
```

---

### Task 4: Battery Improvements

**Files:**
- Create: `bin/nova-battery-capacity`
- Create: `bin/nova-battery-present`
- Create: `bin/nova-battery-status`
- Modify: `bin/nova-battery-monitor` (use nova-battery-present)
- Modify: `bin/nova-notify-battery` (use nova-battery-status)

Note: We already have `bin/nova-battery-remaining` — compare with omarchy's version. Omarchy's version is `omarchy-battery-remaining-time` which parses upower output for time to empty/full. Our existing file is referenced as `nova-battery-remaining` in `nova-battery-monitor`. Check if it needs updating.

- [ ] **Step 1: Create `bin/nova-battery-present`**

```bash
#!/bin/bash

# Returns true (exit 0) if a battery is present on the system.
for bat in /sys/class/power_supply/BAT*; do
  [[ -r $bat/present ]] &&
  [[ $(cat $bat/present) == "1" ]] &&
  [[ $(cat $bat/type) == "Battery" ]] &&
  exit 0
done

exit 1
```

- [ ] **Step 2: Create `bin/nova-battery-capacity`**

```bash
#!/bin/bash

# Returns the battery full capacity in Wh (rounded to whole number).
battery_info=$(upower -i $(upower -e | grep BAT))

echo "$battery_info" | awk '/energy-full:/ {
    printf "%d", $2
    exit
}'
```

- [ ] **Step 3: Create `bin/nova-battery-remaining` (replace existing if different)**

Check current file first. If it doesn't use the improved upower parsing from omarchy, replace with:

```bash
#!/bin/bash

# Returns battery time remaining in compact format (e.g., "2h 15m").
battery_info=$(upower -i $(upower -e | grep BAT))

echo "$battery_info" | awk '/time to (empty|full)/ {
    value = $4
    unit = $5
    if (unit == "minutes") {
        hours = int(value / 60)
        minutes = int(value % 60)
    } else {
        hours = int(value)
        minutes = int((value - hours) * 60)
    }
    if (hours > 0 && minutes > 0) {
        printf "%dh %dm", hours, minutes
    } else if (hours > 0) {
        printf "%dh", hours
    } else {
        printf "%dm", minutes
    }
    exit
}'
```

- [ ] **Step 4: Create `bin/nova-battery-status`**

```bash
#!/bin/bash

# Returns a formatted battery status string for notifications.
battery_info=$(upower -i $(upower -e | grep BAT))

percentage=$(echo "$battery_info" | awk '/percentage/ {
    print int($2)
    exit
}')

power_rate=$(echo "$battery_info" | awk '/energy-rate/ {
    rounded = sprintf("%.1f", $2)
    sub(/\.0$/, "", rounded)
    print rounded
    exit
}')

state=$(echo "$battery_info" | awk '/state/ { print $2; exit }')
time_remaining=$(nova-battery-remaining)
capacity=$(nova-battery-capacity)

if [[ $state == "charging" ]]; then
    echo "󰁹    Battery ${percentage}%  ·  ${time_remaining} to full  ·   ${power_rate}W / ${capacity}Wh"
else
    echo "󰁹    Battery ${percentage}%  ·  ${time_remaining} left  ·   ${power_rate}W / ${capacity}Wh"
fi
```

- [ ] **Step 5: Update `bin/nova-notify-battery` to use nova-battery-status**

Replace the body with:

```bash
#!/bin/bash
# Show battery status notification

if ! nova-battery-present; then
    notify-send "Battery" "No battery found"
    exit 0
fi

notify-send "$(nova-battery-status)"
```

- [ ] **Step 6: Update `bin/nova-battery-monitor` to use nova-battery-present**

In `bin/nova-battery-monitor`, replace the `BATTERY_LEVEL` and `BATTERY_STATE` lines to use the new scripts. The key change: use `nova-battery-present` as a guard at the top.

Add at the top (after the shebang + comment):

```bash
nova-battery-present || exit 0
```

- [ ] **Step 7: Commit**

```bash
chmod +x bin/nova-battery-capacity bin/nova-battery-present bin/nova-battery-status
git add bin/nova-battery-capacity bin/nova-battery-present bin/nova-battery-remaining bin/nova-battery-status bin/nova-notify-battery bin/nova-battery-monitor
git commit -m "feat: add battery capacity/present/status scripts, improve monitor

New: nova-battery-present, nova-battery-capacity, nova-battery-status.
Updated: nova-battery-remaining (improved upower parsing),
nova-notify-battery (uses nova-battery-status),
nova-battery-monitor (guards with nova-battery-present)."
```

---

## Chunk 2: Waybar, Screen Recording, Background Selector

### Task 5: Waybar Indicators

**Files:**
- Create: `default/waybar/indicators/notification-silencing.sh`
- Create: `default/waybar/indicators/idle.sh`
- Create: `bin/nova-toggle-notification-silencing`
- Modify: `config/waybar/config.jsonc` (add 2 modules)
- Modify: `config/waybar/style.css` (add indicator styles)

- [ ] **Step 1: Create notification silencing indicator**

Create `default/waybar/indicators/notification-silencing.sh`:

```bash
#!/bin/bash

if makoctl mode | grep -q 'do-not-disturb'; then
  echo '{"text": "󰂛", "tooltip": "Notifications silenced", "class": "active"}'
else
  echo '{"text": ""}'
fi
```

- [ ] **Step 2: Create idle indicator**

Create `default/waybar/indicators/idle.sh`:

We use `swayidle` (not `hypridle`), so adapt the check. Our existing `nova-toggle-idle` manages a state file at `$HOME/.local/state/nova/toggles/idle-off`.

```bash
#!/bin/bash

if [[ -f "$HOME/.local/state/nova/toggles/idle-off" ]]; then
  echo '{"text": "󱫖", "tooltip": "Idle lock disabled", "class": "active"}'
else
  echo '{"text": ""}'
fi
```

- [ ] **Step 3: Create `bin/nova-toggle-notification-silencing`**

```bash
#!/bin/bash

makoctl mode -t do-not-disturb

if makoctl mode | grep -q 'do-not-disturb'; then
  notify-send "󰂛    Silenced notifications"
else
  notify-send "󰂚    Enabled notifications"
fi

pkill -RTMIN+10 waybar
```

- [ ] **Step 4: Add indicator modules to waybar config**

In `config/waybar/config.jsonc`, add to `modules-right` array (before `"group/tray-expander"`):

```json
    "custom/idle-indicator",
    "custom/dnd-indicator",
```

Add module definitions (before the closing `}`):

```json
  "custom/idle-indicator": {
    "format": "{}",
    "exec": "$HOME/.dotfiles/default/waybar/indicators/idle.sh",
    "interval": "once",
    "signal": 9,
    "return-type": "json"
  },
  "custom/dnd-indicator": {
    "format": "{}",
    "exec": "$HOME/.dotfiles/default/waybar/indicators/notification-silencing.sh",
    "interval": "once",
    "signal": 10,
    "return-type": "json"
  },
```

- [ ] **Step 5: Add indicator CSS**

In `config/waybar/style.css`, add before the closing styles:

```css
#custom-idle-indicator,
#custom-dnd-indicator {
  min-width: 12px;
  margin: 0 4px;
}

#custom-idle-indicator.active,
#custom-dnd-indicator.active {
  color: @accent;
}
```

- [ ] **Step 6: Update niri binds for DND toggle**

In `config/niri/binds.kdl`, replace the inline makoctl DND toggle (line 245):

```kdl
    Mod+Ctrl+N hotkey-overlay-title="Toggle DND" { spawn "nova-toggle-notification-silencing"; }
```

This replaces the direct `makoctl mode -t do-not-disturb` call with our wrapper that also signals waybar.

- [ ] **Step 7: Commit**

```bash
chmod +x default/waybar/indicators/notification-silencing.sh default/waybar/indicators/idle.sh bin/nova-toggle-notification-silencing
git add default/waybar/indicators/notification-silencing.sh default/waybar/indicators/idle.sh bin/nova-toggle-notification-silencing config/waybar/config.jsonc config/waybar/style.css config/niri/binds.kdl
git commit -m "feat: add waybar indicators for DND and idle lock status

Shows icons when notification silencing or idle lock is toggled.
nova-toggle-notification-silencing signals waybar on change."
```

---

### Task 6: Screen Recording Overhaul

**Files:**
- Modify: `bin/nova-cmd-screenrecord`

- [ ] **Step 1: Update screen recording script**

Replace `bin/nova-cmd-screenrecord` with improved version. Key changes from omarchy:
- Switch to h264 encoding via `--codec=h264` (Mac-compatible)
- Cap at 4K resolution for monitors above 4K
- Trim first 100ms to avoid noise frame
- Preview notification with click-to-open

However, omarchy uses `gpu-screen-recorder` while we use `wf-recorder`. We'll keep `wf-recorder` but adopt the improvements that apply:
- Trim first 100ms after recording
- Preview notification with click-to-open (using notify-send action)

Replace `bin/nova-cmd-screenrecord`:

```bash
#!/bin/bash
# Toggle screen recording with wf-recorder
# Usage: nova-cmd-screenrecord [--desktop|--mic|--both|--no-audio]

[[ -f ~/.config/user-dirs.dirs ]] && source ~/.config/user-dirs.dirs
OUTPUT_DIR="${XDG_VIDEOS_DIR:-$HOME/Videos}/Recordings"
mkdir -p "$OUTPUT_DIR"

# Check if recording is active
if pgrep -x wf-recorder > /dev/null; then
    pkill -SIGINT wf-recorder

    for i in {1..50}; do
        pgrep -x wf-recorder > /dev/null || break
        sleep 0.1
    done

    pkill -RTMIN+8 waybar 2>/dev/null

    # Trim first 100ms to remove noise frame
    local latest="$OUTPUT_DIR/$(ls -t "$OUTPUT_DIR" | head -1)"
    if [[ -n "$latest" && -f "$latest" ]]; then
        local trimmed="${latest%.mp4}-trimmed.mp4"
        if ffmpeg -y -ss 0.1 -i "$latest" -c copy "$trimmed" -loglevel quiet 2>/dev/null; then
            mv "$trimmed" "$latest"
        else
            rm -f "$trimmed"
        fi

        # Generate preview and notify with click-to-open
        local preview="${latest%.mp4}-preview.png"
        ffmpeg -y -i "$latest" -ss 00:00:00.1 -vframes 1 -q:v 2 "$preview" -loglevel quiet 2>/dev/null

        (
            ACTION=$(notify-send "Screen recording saved" "Click to open" -t 10000 -i "${preview:-$latest}" -A "default=open")
            [[ "$ACTION" == "default" ]] && mpv "$latest"
            rm -f "$preview"
        ) &
    fi

    exit 0
fi

# Parse arguments
AUDIO_MODE="${1:---desktop}"
AUDIO_ARGS=""

get_default_sink() { pactl get-default-sink 2>/dev/null; }
get_default_source() { pactl get-default-source 2>/dev/null; }

case "$AUDIO_MODE" in
    --desktop)
        SINK=$(get_default_sink)
        [[ -n "$SINK" ]] && AUDIO_ARGS="--audio=${SINK}.monitor"
        ;;
    --mic)
        SOURCE=$(get_default_source)
        [[ -n "$SOURCE" ]] && AUDIO_ARGS="--audio=$SOURCE"
        ;;
    --both)
        AUDIO_ARGS="--audio"
        ;;
    --no-audio)
        AUDIO_ARGS=""
        ;;
    *)
        SINK=$(get_default_sink)
        [[ -n "$SINK" ]] && AUDIO_ARGS="--audio=${SINK}.monitor"
        ;;
esac

OUTPUT=$(niri msg outputs --json 2>/dev/null | jq -r '.[] | select(.focused) | .name' | head -1)
OUTPUT=${OUTPUT:-eDP-1}

FILENAME="$OUTPUT_DIR/screenrecording-$(date +'%Y-%m-%d_%H-%M-%S').mp4"

# Use h264 codec for better compatibility
wf-recorder -o "$OUTPUT" -c h264_vaapi -f "$FILENAME" $AUDIO_ARGS >/dev/null 2>&1 &

notify-send "Screen Recording" "Recording started..."
pkill -RTMIN+8 waybar 2>/dev/null
```

**Note:** The `local` keyword doesn't work outside functions in bash. We need to restructure this as a function or remove `local`. Let me fix:

Actually, replace the entire file properly:

```bash
#!/bin/bash
# Toggle screen recording with wf-recorder
# Usage: nova-cmd-screenrecord [--desktop|--mic|--both|--no-audio]

[[ -f ~/.config/user-dirs.dirs ]] && source ~/.config/user-dirs.dirs
OUTPUT_DIR="${XDG_VIDEOS_DIR:-$HOME/Videos}/Recordings"
mkdir -p "$OUTPUT_DIR"

trim_and_notify() {
    local latest="$1"
    if [[ -n "$latest" && -f "$latest" ]]; then
        # Trim first 100ms to remove noise frame
        local trimmed="${latest%.mp4}-trimmed.mp4"
        if ffmpeg -y -ss 0.1 -i "$latest" -c copy "$trimmed" -loglevel quiet 2>/dev/null; then
            mv "$trimmed" "$latest"
        else
            rm -f "$trimmed"
        fi

        # Generate preview and notify with click-to-open
        local preview="${latest%.mp4}-preview.png"
        ffmpeg -y -i "$latest" -ss 00:00:00.1 -vframes 1 -q:v 2 "$preview" -loglevel quiet 2>/dev/null

        (
            ACTION=$(notify-send "Screen recording saved" "Click to open" -t 10000 -i "${preview:-$latest}" -A "default=open")
            [[ "$ACTION" == "default" ]] && mpv "$latest"
            rm -f "$preview"
        ) &
    fi
}

# Stop if already recording
if pgrep -x wf-recorder > /dev/null; then
    pkill -SIGINT wf-recorder
    for i in {1..50}; do
        pgrep -x wf-recorder > /dev/null || break
        sleep 0.1
    done
    pkill -RTMIN+8 waybar 2>/dev/null

    latest="$OUTPUT_DIR/$(ls -t "$OUTPUT_DIR" | head -1)"
    trim_and_notify "$latest"
    exit 0
fi

# Parse arguments
AUDIO_MODE="${1:---desktop}"
AUDIO_ARGS=""

case "$AUDIO_MODE" in
    --desktop)
        SINK=$(pactl get-default-sink 2>/dev/null)
        [[ -n "$SINK" ]] && AUDIO_ARGS="--audio=${SINK}.monitor"
        ;;
    --mic)
        SOURCE=$(pactl get-default-source 2>/dev/null)
        [[ -n "$SOURCE" ]] && AUDIO_ARGS="--audio=$SOURCE"
        ;;
    --both)   AUDIO_ARGS="--audio" ;;
    --no-audio) AUDIO_ARGS="" ;;
    *)
        SINK=$(pactl get-default-sink 2>/dev/null)
        [[ -n "$SINK" ]] && AUDIO_ARGS="--audio=${SINK}.monitor"
        ;;
esac

OUTPUT=$(niri msg outputs --json 2>/dev/null | jq -r '.[] | select(.focused) | .name' | head -1)
OUTPUT=${OUTPUT:-eDP-1}

FILENAME="$OUTPUT_DIR/screenrecording-$(date +'%Y-%m-%d_%H-%M-%S').mp4"

# Use h264 codec for Mac-compatible sharing
wf-recorder -o "$OUTPUT" -c h264_vaapi -f "$FILENAME" $AUDIO_ARGS >/dev/null 2>&1 &

notify-send "Screen Recording" "Recording started..."
pkill -RTMIN+8 waybar 2>/dev/null
```

- [ ] **Step 2: Commit**

```bash
git add bin/nova-cmd-screenrecord
git commit -m "feat: overhaul screen recording with h264, trim, and preview

Switch to h264 encoding for Mac-compatible sharing.
Trim first 100ms to avoid noise frame.
Show preview notification with click-to-open via mpv."
```

---

### Task 7: Background Selector & Theme Refresh

**Files:**
- Create: `bin/nova-theme-bg-set`
- Create: `bin/nova-theme-refresh`
- Create: `bin/nova-bg-menu`
- Modify: `config/niri/binds.kdl` (change bg keybinding)

- [ ] **Step 1: Create `bin/nova-theme-bg-set`**

```bash
#!/bin/bash

# Sets the specified image as the current background

if [[ -z $1 ]]; then
  echo "Usage: nova-theme-bg-set <path-to-image>" >&2
  exit 1
fi

BACKGROUND="$1"
CURRENT_BACKGROUND_LINK="$HOME/.config/nova/current/background"

ln -nsf "$BACKGROUND" "$CURRENT_BACKGROUND_LINK"

pkill -x swaybg
setsid swaybg -i "$CURRENT_BACKGROUND_LINK" -m fill >/dev/null 2>&1 &
disown
```

Note: Removed `uwsm-app --` wrapper from omarchy since we don't use uwsm.

- [ ] **Step 2: Create `bin/nova-theme-refresh`**

```bash
#!/bin/bash

# Re-apply current theme (useful after config changes)
theme set "$(theme current)"
```

- [ ] **Step 3: Create `bin/nova-bg-menu`**

```bash
#!/bin/bash

# Fuzzel-based background picker for current theme

DOTFILES="${DOTFILES:-$HOME/.dotfiles}"
CURRENT_THEME=$(theme current)

if [[ "$CURRENT_THEME" == "none" ]]; then
    notify-send "No theme set" "Set a theme first with: theme set <name>"
    exit 1
fi

BG_DIR="$DOTFILES/themes/$CURRENT_THEME/backgrounds"

if [[ ! -d "$BG_DIR" ]]; then
    notify-send "No backgrounds" "Theme '$CURRENT_THEME' has no backgrounds directory"
    exit 1
fi

# List background filenames and let user pick
CHOICE=$(ls -1 "$BG_DIR" | fuzzel --dmenu --prompt "Background: ")

if [[ -n "$CHOICE" ]]; then
    nova-theme-bg-set "$BG_DIR/$CHOICE"
fi
```

- [ ] **Step 4: Update niri keybinding**

In `config/niri/binds.kdl`, change the background keybinding (line 217) from:

```kdl
    Mod+Alt+B hotkey-overlay-title="Next Background" { spawn "nova-bg-next"; }
```

to:

```kdl
    Mod+Alt+B hotkey-overlay-title="Next Background" { spawn "nova-bg-next"; }
    Mod+Ctrl+Space hotkey-overlay-title="Background Menu" { spawn "nova-bg-menu"; }
```

(Keep the existing Mod+Alt+B for quick cycling, add Mod+Ctrl+Space for the menu picker.)

- [ ] **Step 5: Commit**

```bash
chmod +x bin/nova-theme-bg-set bin/nova-theme-refresh bin/nova-bg-menu
git add bin/nova-theme-bg-set bin/nova-theme-refresh bin/nova-bg-menu config/niri/binds.kdl
git commit -m "feat: add background selector menu and theme refresh

nova-bg-menu: fuzzel-based background picker for current theme.
nova-theme-bg-set: set specific background by path.
nova-theme-refresh: re-apply current theme.
Super+Ctrl+Space opens background menu."
```

---

## Chunk 3: Theme Sync

### Task 8: Theme Sync — Background Renames, New Themes, Cleanup

**Files:**
- Rename: backgrounds in 13 theme directories
- Copy: 3 new backgrounds from omarchy
- Copy: 3 new theme directories from omarchy
- Create: `themes/rose-pine/light.mode`
- Delete: `chromium.theme` and `fuzzel.ini` from all 14 themes

This task is large file operations. Use `git mv` for renames to preserve history.

- [ ] **Step 1: Rename catppuccin backgrounds**

```bash
cd themes/catppuccin/backgrounds
git mv 1-catppuccin.png 1-totoro.png
git mv 2-cat-waves-mocha.png 2-waves.png
git mv 3-cat-blue-eye-mocha.png 3-blue-eye.png
```

- [ ] **Step 2: Rename catppuccin-latte backgrounds**

```bash
cd themes/catppuccin-latte/backgrounds
git mv 1-catppuccin-latte.png 1-color-fade.png
```

- [ ] **Step 3: Rename ethereal backgrounds**

```bash
cd themes/ethereal/backgrounds
git mv 1.jpg 1-cosmic.jpg
git mv 2.jpg 2-meadow.jpg
```

- [ ] **Step 4: Rename everforest backgrounds**

```bash
cd themes/everforest/backgrounds
git mv 1-everforest.jpg 1-tree-tops.jpg
```

- [ ] **Step 5: Rename flexoki-light backgrounds**

```bash
cd themes/flexoki-light/backgrounds
git mv 1-flexoki-light-orb.png 1-orb.png
git mv 2-flexoki-light-omarchy.png 2-omarchy.png
```

- [ ] **Step 6: Rename gruvbox backgrounds**

```bash
cd themes/gruvbox/backgrounds
git mv 1-grubox.jpg 1-the-backwater.jpg
git mv 2-gruvbox.jpg 2-leaves.jpg
```

- [ ] **Step 7: Rename hackerman backgrounds**

```bash
cd themes/hackerman/backgrounds
git mv 1.jpg 1-synth-scape.jpg
git mv 2.jpg 2-geometric.jpg
```

- [ ] **Step 8: Rename matte-black backgrounds**

```bash
cd themes/matte-black/backgrounds
git mv 1-matte-black.jpg 1-dark-waters.jpg
git mv 2-matte-black-hands.jpg 2-dot-hands.jpg
```
(Note: `0-ship-at-sea.jpg` stays — already correct name.)

- [ ] **Step 9: Rename nord backgrounds and copy new one**

```bash
cd themes/nord/backgrounds
git mv 1-nord.png 1-city-view.png
git mv 2-nord.png 2-night-hawks.png
cp ../../../resources/omarchy/themes/nord/backgrounds/0-black-moon.jpg .
```

- [ ] **Step 10: Rename osaka-jade backgrounds**

```bash
cd themes/osaka-jade/backgrounds
git mv 1-osaka-jade-bg.jpg 1-glowing-city.jpg
git mv 2-osaka-jade-bg.jpg 2-shaded-entrance.jpg
git mv 3-osaka-jade-bg.jpg 3-mountain-moon.jpg
```

- [ ] **Step 11: Rename ristretto backgrounds**

```bash
cd themes/ristretto/backgrounds
git mv 1-ristretto.jpg 1-color-curves.jpg
git mv 2-ristretto.jpg 2-coffee-beans.jpg
git mv 3-ristretto.jpg 3-industrial-moon.jpg
```

- [ ] **Step 12: Rename rose-pine backgrounds**

```bash
cd themes/rose-pine/backgrounds
git mv 1-rose-pine.jpg 1-funky-shapes.jpg
git mv 2-wave-light.png 2-dot-map.png
git mv 3-leafy-dawn-omarchy.png 3-omarchy-plants.png
```

- [ ] **Step 13: Rename tokyo-night backgrounds and copy new ones**

Our current files:
- `1-scenery-pink-lakeside-sunset-lake-landscape-scenic-panorama-7680x3215-144.png`
- `2-Pawel-Czerwinski-Abstract-Purple-Blue.jpg`
- `3-Milad-Fakurian-Abstract-Purple-Blue.jpg`

Omarchy target files:
- `0-swirl-buck.jpg` (new)
- `1-sunset-lake.png`
- `2-pawel-czerwinski.jpg`
- `3-milad-fakurian.jpg`

```bash
cd themes/tokyo-night/backgrounds
git mv "1-scenery-pink-lakeside-sunset-lake-landscape-scenic-panorama-7680x3215-144.png" 1-sunset-lake.png
git mv "2-Pawel-Czerwinski-Abstract-Purple-Blue.jpg" 2-pawel-czerwinski.jpg
git mv "3-Milad-Fakurian-Abstract-Purple-Blue.jpg" 3-milad-fakurian.jpg
cp ../../../resources/omarchy/themes/tokyo-night/backgrounds/0-swirl-buck.jpg .
```

- [ ] **Step 14: Add rose-pine light.mode marker**

```bash
echo "light mode" > themes/rose-pine/light.mode
```

- [ ] **Step 15: Copy 3 new themes from omarchy**

```bash
# Copy entire theme directories (colors.toml, btop.theme, backgrounds/, icons.theme)
# Skip: neovim.lua, vscode.json, preview.png (not used by our theme system)
for theme in vantablack miasma white; do
    mkdir -p "themes/$theme/backgrounds"
    cp "resources/omarchy/themes/$theme/colors.toml" "themes/$theme/"
    cp "resources/omarchy/themes/$theme/btop.theme" "themes/$theme/"
    cp "resources/omarchy/themes/$theme/icons.theme" "themes/$theme/"
    cp resources/omarchy/themes/$theme/backgrounds/* "themes/$theme/backgrounds/"
    # Copy light.mode if present
    [[ -f "resources/omarchy/themes/$theme/light.mode" ]] && cp "resources/omarchy/themes/$theme/light.mode" "themes/$theme/"
done
```

- [ ] **Step 16: Remove chromium.theme and fuzzel.ini from all themes**

```bash
find themes/ -name "chromium.theme" -delete
find themes/ -name "fuzzel.ini" -delete
```

- [ ] **Step 17: Commit**

```bash
git add themes/
git commit -m "feat: sync theme backgrounds, add vantablack/miasma/white themes

Renamed backgrounds to match omarchy naming convention.
Added 3 new themes: vantablack, miasma, white.
Added rose-pine light.mode marker.
Removed obsolete chromium.theme and fuzzel.ini (handled by templates)."
```

---

## Post-Implementation Checklist

After all 8 tasks are complete:

- [ ] Run `bash -n` on all new/modified shell scripts to verify syntax
- [ ] Verify `setup.sh` still runs without errors (dry-run check: `bash -n setup.sh`)
- [ ] Verify `theme list` shows all 17 themes (14 existing + 3 new)
- [ ] Verify `theme set vantablack` generates all config files without errors
- [ ] Check `.gitignore` still covers all generated files
