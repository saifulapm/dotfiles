#!/usr/bin/env bash
# @vicinae.schemaVersion 1
# @vicinae.title Clock Format
# @vicinae.mode silent
# @vicinae.icon 🕑
# @vicinae.packageName Shell
# @vicinae.keywords ["time", "date", "bar"]
# Pick the bar clock's label from the presets its right-click cycles through
# (omarchy 5ec8bd30, their Appearance > Menu Bar > Indicators > Clock). Each
# row reads the way the label will, the current one is marked, and the pick
# goes through `bar setSetting`, which writes shell.json by the same path the
# right-click does. A vertical bar gets the stacked presets under its own key.
# The lists mirror CLOCK_FORMATS / VERTICAL_CLOCK_FORMATS in
# shell/Modules/Bar/widgets/ClockModel.js (ClockModel.test.js checks that);
# the labels are omarchy's.
set -euo pipefail
export PATH="$HOME/.dotfiles/bin:$HOME/.local/bin:$PATH"

if [[ $(qs ipc call bar status | jq -r .vertical) == true ]]; then
    key=verticalFormat
    fallback=$'HH\n—\nmm'
    formats=($'HH\n—\nmm' $'h\n—\nmm\nAP' $'dd\nMMM\n\'W\'ww\n\'\'yy' $'HH\nmm')
    labels=("14 — 30" "2 — 30 PM" "03 May W18 '26" "14 30")
else
    key=format
    fallback="dddd HH:mm"
    formats=("dddd HH:mm" "dddd h:mm AP" "dddd HH:mm:ss" "dddd h:mm:ss AP" "HH:mm" "h:mm AP" "ddd d MMM HH:mm" "ddd d MMM h:mm AP" "d MMMM 'W'ww yyyy" "yyyy-MM-dd HH:mm")
    labels=("Sunday 14:30" "Sunday 2:30 PM" "Sunday 14:30:05" "Sunday 2:30:05 PM" "14:30" "2:30 PM" "Sun 3 May 14:30" "Sun 3 May 2:30 PM" "3 May W18 2026" "2026-05-03 14:30")
fi

# The clock's entry is the bare string "clock" until a setting is written.
current="$(jq -r --arg key "$key" --arg fallback "$fallback" \
    'first(.bar | (.left, .center, .right) | arrays | .[] | objects | select(.id == "clock")) // {} | .[$key] // $fallback' \
    "$HOME/.config/quickshell/shell.json" 2>/dev/null)" || current="$fallback"

options=()
for i in "${!formats[@]}"; do
    marker=""
    [[ ${formats[i]} == "$current" ]] && marker=" (current)"
    options+=("${labels[i]}$marker")
done

pick="$(printf '%s\n' "${options[@]}" | menu-select "Clock format")" || exit 0
pick="${pick% (current)}"
for i in "${!labels[@]}"; do
    if [[ ${labels[i]} == "$pick" ]]; then
        exec qs ipc call bar setSetting clock "$key" "${formats[i]}"
    fi
done
exit 1
